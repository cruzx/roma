-- Apply after membership.sql. Grants can only be maintained by the server administrator.
begin;
create table public.roam_sync_grants (
 user_id uuid primary key references auth.users(id) on delete cascade,
 enabled boolean not null default true,
 valid_until timestamptz,
 created_at timestamptz not null default now()
);
alter table public.roam_sync_grants enable row level security;
alter table public.roam_sync_grants force row level security;
revoke all on public.roam_sync_grants from public, anon, authenticated;
grant all on public.roam_sync_grants to service_role;
create function public.roam_complimentary_status() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('active',true,'complimentary',true,
 'validUntil',extract(epoch from valid_until)) from public.roam_sync_grants
 where user_id=auth.uid() and enabled and (valid_until is null or valid_until>now())),
 jsonb_build_object('active',false,'complimentary',false,'validUntil',null));
$$;
revoke all on function public.roam_complimentary_status() from public, anon;
grant execute on function public.roam_complimentary_status() to authenticated;
create or replace function public.roam_has_membership() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.roam_sync_grants where user_id=auth.uid()
 and enabled and (valid_until is null or valid_until>now()))
 or exists(select 1 from public.roam_memberships where user_id=auth.uid()
 and valid_until>now() and checked_until>now());
$$;
commit;
