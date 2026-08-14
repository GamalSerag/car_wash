-- Supabase Row Level Security policies for the car wash sales app.
--
-- How to run:
-- 1. Open your Supabase project dashboard.
-- 2. Go to SQL Editor.
-- 3. Create a new query.
-- 4. Paste this whole file and click Run.
--
-- Notes:
-- - These policies assume the tables already exist:
--   public.profiles, public.vehicle_types, public.sales.
-- - Keep the service role key on the server only.
-- - Flutter should use only the anon/publishable key.

alter table public.profiles enable row level security;
alter table public.vehicle_types enable row level security;
alter table public.sales enable row level security;

grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant select, insert, update on public.vehicle_types to authenticated;
grant select, insert, update, delete on public.sales to authenticated;
grant usage, select on all sequences in schema public to authenticated;

insert into storage.buckets (id, name, public)
values ('vehicle-icons', 'vehicle-icons', true)
on conflict (id) do update
set public = true;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sales'
  ) then
    alter publication supabase_realtime add table public.sales;
  end if;
end;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and is_active = true
  );
$$;

create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_active = true
  );
$$;

drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Admins can read all profiles" on public.profiles;
drop policy if exists "Admins can update profiles" on public.profiles;

create policy "Users can read own profile"
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy "Admins can read all profiles"
on public.profiles
for select
to authenticated
using (public.is_admin());

-- Normal users receive no update policy on profiles, so they cannot change
-- their own role or any profile fields. Admins can update profiles.
create policy "Admins can update profiles"
on public.profiles
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Users can read active vehicle types" on public.vehicle_types;
drop policy if exists "Admins can read all vehicle types" on public.vehicle_types;
drop policy if exists "Admins can insert vehicle types" on public.vehicle_types;
drop policy if exists "Admins can update vehicle types" on public.vehicle_types;

create policy "Users can read active vehicle types"
on public.vehicle_types
for select
to authenticated
using (is_active = true and public.is_active_user());

create policy "Admins can read all vehicle types"
on public.vehicle_types
for select
to authenticated
using (public.is_admin());

create policy "Admins can insert vehicle types"
on public.vehicle_types
for insert
to authenticated
with check (public.is_admin());

-- Only admins can update vehicle types, including price changes,
-- activation, and deactivation.
create policy "Admins can update vehicle types"
on public.vehicle_types
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Active users can insert own sales" on public.sales;
drop policy if exists "Employees can read own sales" on public.sales;
drop policy if exists "Employees can update own sales" on public.sales;
drop policy if exists "Admins can read all sales" on public.sales;
drop policy if exists "Admins can update sales" on public.sales;
drop policy if exists "Admins can delete sales" on public.sales;
drop policy if exists "Users can read vehicle icons" on storage.objects;
drop policy if exists "Admins can upload vehicle icons" on storage.objects;
drop policy if exists "Admins can update vehicle icons" on storage.objects;
drop policy if exists "Admins can delete vehicle icons" on storage.objects;

create policy "Active users can insert own sales"
on public.sales
for insert
to authenticated
with check (
  public.is_active_user()
  and employee_id = auth.uid()
);

create policy "Employees can read own sales"
on public.sales
for select
to authenticated
using (
  public.is_active_user()
  and employee_id = auth.uid()
);

create policy "Employees can update own sales"
on public.sales
for update
to authenticated
using (
  public.is_active_user()
  and employee_id = auth.uid()
)
with check (
  public.is_active_user()
  and employee_id = auth.uid()
);

create policy "Admins can read all sales"
on public.sales
for select
to authenticated
using (public.is_admin());

create policy "Admins can update sales"
on public.sales
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "Admins can delete sales"
on public.sales
for delete
to authenticated
using (public.is_admin());

create policy "Users can read vehicle icons"
on storage.objects
for select
to authenticated
using (bucket_id = 'vehicle-icons');

create policy "Admins can upload vehicle icons"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'vehicle-icons' and public.is_admin());

create policy "Admins can update vehicle icons"
on storage.objects
for update
to authenticated
using (bucket_id = 'vehicle-icons' and public.is_admin())
with check (bucket_id = 'vehicle-icons' and public.is_admin());

create policy "Admins can delete vehicle icons"
on storage.objects
for delete
to authenticated
using (bucket_id = 'vehicle-icons' and public.is_admin());
