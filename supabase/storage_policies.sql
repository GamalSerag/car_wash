-- Supabase Storage setup for uploaded vehicle type icons.
--
-- How to run:
-- 1. Open Supabase Dashboard > SQL Editor.
-- 2. Create a new query.
-- 3. Paste this whole file.
-- 4. Click Run.
--
-- This creates a public bucket named vehicle-icons and allows only admins
-- from public.profiles to upload/update/delete icons.

insert into storage.buckets (id, name, public)
values ('vehicle-icons', 'vehicle-icons', true)
on conflict (id) do update
set public = true;

grant usage on schema storage to authenticated;
grant select, insert, update, delete on storage.objects to authenticated;

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

drop policy if exists "Users can read vehicle icons" on storage.objects;
drop policy if exists "Admins can upload vehicle icons" on storage.objects;
drop policy if exists "Admins can update vehicle icons" on storage.objects;
drop policy if exists "Admins can delete vehicle icons" on storage.objects;

create policy "Users can read vehicle icons"
on storage.objects
for select
to authenticated
using (bucket_id = 'vehicle-icons');

create policy "Admins can upload vehicle icons"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'vehicle-icons'
  and public.is_admin()
);

create policy "Admins can update vehicle icons"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'vehicle-icons'
  and public.is_admin()
)
with check (
  bucket_id = 'vehicle-icons'
  and public.is_admin()
);

create policy "Admins can delete vehicle icons"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'vehicle-icons'
  and public.is_admin()
);
