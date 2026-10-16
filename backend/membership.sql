-- Apply once AFTER account-sync.sql, only when verification functions and IAP are ready.
begin;
create table public.roam_memberships (
 user_id uuid primary key references auth.users(id) on delete cascade,
 original_transaction_id text unique not null,
 product_id text not null check (product_id = 'com.xiangchengjin.roam.sync.annual'),
 environment text not null check (environment in ('Production','Sandbox')),
 valid_until timestamptz not null,
 checked_until timestamptz not null,
 updated_at timestamptz not null default now()
);
alter table public.roam_memberships enable row level security;
alter table public.roam_memberships force row level security;
revoke all on public.roam_memberships from public, anon, authenticated;
grant all on public.roam_memberships to service_role;
create function public.roam_has_membership() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.roam_memberships
 where user_id=auth.uid() and valid_until>now() and checked_until>now());
$$;
revoke all on function public.roam_has_membership() from public, anon;
grant execute on function public.roam_has_membership() to authenticated;
-- Also gate direct REST SELECT: hiding UI or calling the table is not a bypass.
drop policy owner_read on public.roam_documents;
create policy owner_read on public.roam_documents for select to authenticated
 using (user_id=(select auth.uid()) and (select public.roam_has_membership()));
create or replace function public.roam_read(document_key text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise sqlstate 'PT401' using message='Authentication required'; end if;
 if not public.roam_has_membership() then raise sqlstate 'PT402' using message='Membership required'; end if;
 select jsonb_build_object('revision',revision,'payload',payload) into result
 from public.roam_documents where user_id=auth.uid() and key=document_key;
 return result;
end $$;
alter function public.roam_write(text,bigint,text) rename to roam_write_internal;
revoke all on function public.roam_write_internal(text,bigint,text) from public, anon, authenticated;
create function public.roam_write(document_key text, expected_revision bigint, document_payload text) returns bigint
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise sqlstate 'PT401' using message='Authentication required'; end if;
 if not public.roam_has_membership() then raise sqlstate 'PT402' using message='Membership required'; end if;
 return public.roam_write_internal(document_key,expected_revision,document_payload);
end $$;
revoke all on function public.roam_write(text,bigint,text) from public, anon;
grant execute on function public.roam_write(text,bigint,text) to authenticated;
-- Account deletion remains available without payment. No document is deleted on expiry.
commit;
