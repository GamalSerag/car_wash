-- Run after saas_multitenancy.sql and signup_requests.sql in SQL Editor.
-- Setting companies.is_active = false suspends business access without deleting
-- data or changing individual user flags. Setting it back to true restores access.
-- Own profile/company status remains readable so the app can explain suspension.

begin;

create or replace function public.is_company_active(target_company_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.companies c
    where c.id = target_company_id and c.is_active = true
  );
$$;

revoke all on function public.is_company_active(uuid) from public, anon;
grant execute on function public.is_company_active(uuid) to authenticated, service_role;

create or replace function public.current_company_id()
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select p.company_id from public.profiles p
  where p.id = auth.uid() and p.is_active = true
    and (p.role = 'super_admin' or public.is_company_active(p.company_id));
$$;

create or replace function public.is_active_user()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true
      and (p.role = 'super_admin' or public.is_company_active(p.company_id))
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true
      and (p.role = 'super_admin' or (
        p.role = 'admin' and public.is_company_active(p.company_id)
      ))
  );
$$;

create or replace function public.is_company_admin(target_company_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true
      and (p.role = 'super_admin' or (
        p.role = 'admin' and p.company_id = target_company_id
        and public.is_company_active(p.company_id)
      ))
  );
$$;

drop policy if exists "Users can read own company" on public.companies;
create policy "Users can read own company"
on public.companies for select to authenticated
using (
  public.is_super_admin() or id = (
    select p.company_id from public.profiles p where p.id = (select auth.uid())
  )
);

-- A company admin must not bypass suspension by promoting themselves to
-- super_admin or moving a profile into a different company.
create or replace function public.protect_profile_access_fields()
returns trigger
language plpgsql security invoker
set search_path = ''
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_auth_admin')
      or public.is_super_admin() then
    return new;
  end if;
  if new.role is distinct from old.role
      or new.company_id is distinct from old.company_id
      or old.role = 'super_admin' then
    raise exception 'Only super admins can change profile access fields'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_access_fields on public.profiles;
create trigger protect_profile_access_fields
before update on public.profiles
for each row execute function public.protect_profile_access_fields();

-- Allow users to unregister their own device even while suspended.
drop policy if exists "Users can read their own device tokens" on public.device_tokens;
create policy "Users can read their own device tokens"
on public.device_tokens for select to authenticated
using (user_id = auth.uid());
drop policy if exists "Users can delete their own device tokens" on public.device_tokens;
create policy "Users can delete their own device tokens"
on public.device_tokens for delete to authenticated
using (user_id = auth.uid());

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
      and not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public'
          and tablename = 'companies'
      ) then
    alter publication supabase_realtime add table public.companies;
  end if;
end;
$$;

commit;
