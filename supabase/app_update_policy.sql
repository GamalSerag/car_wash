-- Run in Supabase SQL Editor. This does not force any update by default.
-- Publish the new build and confirm users can download it BEFORE raising minimum_build.
begin;
create table if not exists public.app_update_policy (
  platform text primary key check (platform = 'android'),
  enabled boolean not null default false,
  minimum_build integer not null check (minimum_build > 0),
  update_url text not null check (update_url ~ '^https://[^/]+/.+'),
  updated_at timestamptz not null default now()
);
alter table public.app_update_policy enable row level security;
revoke all on public.app_update_policy from anon, authenticated;
grant select on public.app_update_policy to anon, authenticated;
grant all on public.app_update_policy to service_role;
drop policy if exists "Public can read app update policy" on public.app_update_policy;
create policy "Public can read app update policy"
  on public.app_update_policy for select to anon, authenticated using (true);
insert into public.app_update_policy(platform, enabled, minimum_build, update_url)
values ('android', false, 11,
  'https://play.google.com/store/apps/details?id=com.maghsala.car_wash')
on conflict (platform) do nothing;
commit;

-- After a future build (e.g. 12) is available to ALL intended users:
-- update public.app_update_policy
-- set enabled = true, minimum_build = 12, updated_at = now()
-- where platform = 'android';
-- Emergency disable: update public.app_update_policy set enabled = false;
