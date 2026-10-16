-- Run once in the Supabase SQL editor. No service-role secret belongs in the App.
begin;
create table public.roam_documents (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null check (key in ('trips','journal')),
  revision bigint not null check (revision > 0),
  payload text not null check (octet_length(payload) <= 67108864),
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table public.roam_documents enable row level security;
alter table public.roam_documents force row level security;
create policy owner_read on public.roam_documents for select to authenticated using (user_id = (select auth.uid()));
-- Only RPCs can write: clients cannot bypass compare-and-swap with direct REST updates.
revoke all on public.roam_documents from anon, authenticated;
grant select on public.roam_documents to authenticated;

create function public.roam_read(document_key text) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message = 'Authentication required'; end if;
  select jsonb_build_object('revision', revision, 'payload', payload) into result
    from public.roam_documents where user_id = auth.uid() and key = document_key;
  return result;
end $$;

create function public.roam_write(document_key text, expected_revision bigint, document_payload text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_revision bigint; current_size bigint; used_size bigint; decoded jsonb;
begin
  if owner_id is null then raise sqlstate 'PT401' using message = 'Authentication required'; end if;
  if document_key is null or not (document_key in ('trips','journal'))
     or document_payload is null or expected_revision is null or expected_revision < 0 then
    raise sqlstate 'PT400' using message = 'Invalid document';
  end if;
  if octet_length(document_payload) > 67108864 then raise sqlstate 'PT413' using message = 'Document exceeds 64 MiB'; end if;
  begin
    decoded := convert_from(decode(document_payload, 'base64'), 'UTF8')::jsonb;
  exception when others then raise sqlstate 'PT400' using message = 'Expected metadata JSON'; end;
  if jsonb_path_exists(decoded, '$.**.coverPhoto ? (@ != null)')
     or jsonb_path_exists(decoded, '$.**.photos ? (@ != null)')
     or jsonb_path_exists(decoded, '$.**.imageData ? (@ != null)') then
    raise sqlstate 'PT400' using message = 'Images belong in private iCloud';
  end if;
  -- Serializes creates and all writes for this user, including quota checks.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text, 0));
  select revision, octet_length(payload) into current_revision, current_size
    from public.roam_documents where user_id = owner_id and key = document_key;
  if coalesce(current_revision,0) <> expected_revision then raise sqlstate 'PT409' using message = 'Revision conflict'; end if;
  select coalesce(sum(octet_length(payload)),0) into used_size from public.roam_documents where user_id = owner_id;
  if used_size - coalesce(current_size,0) + octet_length(document_payload) > 268435456 then
    raise sqlstate 'PT413' using message = 'Account quota exceeded';
  end if;
  insert into public.roam_documents(user_id,key,revision,payload) values(owner_id,document_key,1,document_payload)
    on conflict (user_id,key) do update set revision = public.roam_documents.revision + 1,
      payload = excluded.payload, updated_at = now()
    returning revision into current_revision;
  return current_revision;
end $$;
revoke all on function public.roam_read(text) from public, anon;
revoke all on function public.roam_write(text,bigint,text) from public, anon;
grant execute on function public.roam_read(text) to authenticated;
grant execute on function public.roam_write(text,bigint,text) to authenticated;
create function public.roam_delete_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message = 'Authentication required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 0));
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.roam_delete_account() from public, anon;
grant execute on function public.roam_delete_account() to authenticated;
commit;
