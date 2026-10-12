-- SaaS multi-tenancy migration for the car wash app.
--
-- How to run:
-- 1. Open Supabase Dashboard > SQL Editor.
-- 2. Run this whole file after the existing schema files.
-- 3. Existing data is moved into one default company named "مغسلة سراج".
--
-- Model:
-- - One Supabase project and one PostgreSQL database.
-- - Every business row has company_id.
-- - RLS limits admins/employees to their own company.
-- - super_admin can manage all companies.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.companies (id, name)
values ('00000000-0000-0000-0000-000000000001', 'مغسلة سراج')
on conflict (id) do nothing;

alter table public.profiles
drop constraint if exists profiles_role_check;

alter table public.profiles
add constraint profiles_role_check
check (role in ('super_admin', 'admin', 'employee'));

alter table public.profiles
add column if not exists company_id uuid references public.companies(id);

update public.profiles
set company_id = '00000000-0000-0000-0000-000000000001'
where company_id is null;

alter table public.profiles
alter column company_id set not null;

alter table public.vehicle_types
add column if not exists company_id uuid references public.companies(id);

update public.vehicle_types
set company_id = '00000000-0000-0000-0000-000000000001'
where company_id is null;

alter table public.vehicle_types
alter column company_id set not null;

alter table public.sales
add column if not exists company_id uuid references public.companies(id);

update public.sales
set company_id = coalesce(
  (
    select profiles.company_id
    from public.profiles
    where profiles.id = sales.employee_id
  ),
  '00000000-0000-0000-0000-000000000001'
)
where company_id is null;

alter table public.sales
alter column company_id set not null;

alter table public.carpet_orders
add column if not exists company_id uuid references public.companies(id);

update public.carpet_orders
set company_id = coalesce(
  (
    select profiles.company_id
    from public.profiles
    where profiles.id = carpet_orders.employee_id
  ),
  '00000000-0000-0000-0000-000000000001'
)
where company_id is null;

alter table public.carpet_orders
alter column company_id set not null;

alter table public.carpet_order_photos
add column if not exists company_id uuid references public.companies(id);

update public.carpet_order_photos
set company_id = coalesce(
  (
    select carpet_orders.company_id
    from public.carpet_orders
    where carpet_orders.id = carpet_order_photos.order_id
  ),
  '00000000-0000-0000-0000-000000000001'
)
where company_id is null;

alter table public.carpet_order_photos
alter column company_id set not null;

alter table public.device_tokens
add column if not exists company_id uuid references public.companies(id);

update public.device_tokens
set company_id = coalesce(
  (
    select profiles.company_id
    from public.profiles
    where profiles.id = device_tokens.user_id
  ),
  '00000000-0000-0000-0000-000000000001'
)
where company_id is null;

alter table public.device_tokens
alter column company_id set not null;

create index if not exists profiles_company_id_idx
on public.profiles(company_id);

create index if not exists vehicle_types_company_id_idx
on public.vehicle_types(company_id);

create index if not exists sales_company_id_created_at_idx
on public.sales(company_id, created_at desc);

create index if not exists carpet_orders_company_id_created_at_idx
on public.carpet_orders(company_id, created_at desc);

create index if not exists carpet_order_photos_company_id_idx
on public.carpet_order_photos(company_id);

create index if not exists device_tokens_company_id_idx
on public.device_tokens(company_id);

create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select company_id
  from public.profiles
  where id = auth.uid()
    and is_active = true
$$;

create or replace function public.is_super_admin()
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
      and role = 'super_admin'
      and is_active = true
  );
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
      and role in ('admin', 'super_admin')
      and is_active = true
  );
$$;

create or replace function public.is_company_admin(target_company_id uuid)
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
      and (
        role = 'super_admin'
        or (role = 'admin' and company_id = target_company_id)
      )
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

create or replace function public.storage_path_company_id(path text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return split_part(path, '/', 1)::uuid;
exception
  when others then
    return null;
end;
$$;

create or replace function public.set_company_id_from_employee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.company_id is null then
    select profiles.company_id
    into new.company_id
    from public.profiles
    where profiles.id = new.employee_id;
  end if;

  return new;
end;
$$;

create or replace function public.set_company_id_from_current_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.company_id is null then
    new.company_id := public.current_company_id();
  end if;

  return new;
end;
$$;

create or replace function public.set_carpet_photo_company_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.company_id is null then
    select carpet_orders.company_id
    into new.company_id
    from public.carpet_orders
    where carpet_orders.id = new.order_id;
  end if;

  return new;
end;
$$;

drop trigger if exists set_sales_company_id on public.sales;
create trigger set_sales_company_id
before insert on public.sales
for each row execute function public.set_company_id_from_employee();

drop trigger if exists set_carpet_orders_company_id on public.carpet_orders;
create trigger set_carpet_orders_company_id
before insert on public.carpet_orders
for each row execute function public.set_company_id_from_employee();

drop trigger if exists set_vehicle_types_company_id on public.vehicle_types;
create trigger set_vehicle_types_company_id
before insert on public.vehicle_types
for each row execute function public.set_company_id_from_current_user();

drop trigger if exists set_device_tokens_company_id on public.device_tokens;
create trigger set_device_tokens_company_id
before insert or update on public.device_tokens
for each row execute function public.set_company_id_from_current_user();

drop trigger if exists set_carpet_order_photos_company_id on public.carpet_order_photos;
create trigger set_carpet_order_photos_company_id
before insert on public.carpet_order_photos
for each row execute function public.set_carpet_photo_company_id();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_company_id uuid;
begin
  requested_company_id := nullif(new.raw_user_meta_data ->> 'company_id', '')::uuid;

  insert into public.profiles (id, company_id, full_name)
  values (
    new.id,
    coalesce(requested_company_id, '00000000-0000-0000-0000-000000000001'),
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', ''),
      new.email,
      'مستخدم جديد'
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.vehicle_types enable row level security;
alter table public.sales enable row level security;
alter table public.carpet_orders enable row level security;
alter table public.carpet_order_photos enable row level security;
alter table public.device_tokens enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update on public.companies to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update on public.vehicle_types to authenticated;
grant select, insert, update, delete on public.sales to authenticated;
grant select, insert, update, delete on public.carpet_orders to authenticated;
grant select, insert, update, delete on public.carpet_order_photos to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;
grant usage, select on all sequences in schema public to authenticated;

drop policy if exists "Users can read own company" on public.companies;
drop policy if exists "Super admins can manage companies" on public.companies;

create policy "Users can read own company"
on public.companies
for select
to authenticated
using (id = public.current_company_id() or public.is_super_admin());

create policy "Super admins can manage companies"
on public.companies
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Admins can read all profiles" on public.profiles;
drop policy if exists "Admins can update profiles" on public.profiles;
drop policy if exists "Users can read company profiles" on public.profiles;
drop policy if exists "Company admins can update company profiles" on public.profiles;

create policy "Users can read own profile"
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy "Users can read company profiles"
on public.profiles
for select
to authenticated
using (
  public.is_super_admin()
  or company_id = public.current_company_id()
);

create policy "Company admins can update company profiles"
on public.profiles
for update
to authenticated
using (public.is_company_admin(company_id))
with check (public.is_company_admin(company_id));

drop policy if exists "Users can read active vehicle types" on public.vehicle_types;
drop policy if exists "Active users can read active vehicle types" on public.vehicle_types;
drop policy if exists "Admins can read all vehicle types" on public.vehicle_types;
drop policy if exists "Admins can insert vehicle types" on public.vehicle_types;
drop policy if exists "Admins can create vehicle types" on public.vehicle_types;
drop policy if exists "Admins can update vehicle types" on public.vehicle_types;

create policy "Users can read active vehicle types"
on public.vehicle_types
for select
to authenticated
using (
  is_active = true
  and (
    public.is_super_admin()
    or company_id = public.current_company_id()
  )
);

create policy "Admins can read all vehicle types"
on public.vehicle_types
for select
to authenticated
using (public.is_company_admin(company_id));

create policy "Admins can insert vehicle types"
on public.vehicle_types
for insert
to authenticated
with check (public.is_company_admin(company_id));

create policy "Admins can update vehicle types"
on public.vehicle_types
for update
to authenticated
using (public.is_company_admin(company_id))
with check (public.is_company_admin(company_id));

drop policy if exists "Active users can insert own sales" on public.sales;
drop policy if exists "Employees can read own sales" on public.sales;
drop policy if exists "Employees can update own sales" on public.sales;
drop policy if exists "Admins can read all sales" on public.sales;
drop policy if exists "Admins can update sales" on public.sales;
drop policy if exists "Admins can delete sales" on public.sales;
drop policy if exists "Active users can read sales" on public.sales;
drop policy if exists "Active users can create own sales" on public.sales;

create policy "Active users can insert own sales"
on public.sales
for insert
to authenticated
with check (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
);

create policy "Employees can read own sales"
on public.sales
for select
to authenticated
using (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
);

create policy "Employees can update own sales"
on public.sales
for update
to authenticated
using (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
)
with check (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
);

create policy "Admins can read all sales"
on public.sales
for select
to authenticated
using (public.is_company_admin(company_id));

create policy "Admins can update sales"
on public.sales
for update
to authenticated
using (public.is_company_admin(company_id))
with check (public.is_company_admin(company_id));

create policy "Admins can delete sales"
on public.sales
for delete
to authenticated
using (public.is_company_admin(company_id));

drop policy if exists "Active users can insert own carpet orders" on public.carpet_orders;
drop policy if exists "Employees can read own carpet orders" on public.carpet_orders;
drop policy if exists "Employees can update own carpet orders" on public.carpet_orders;
drop policy if exists "Admins can read all carpet orders" on public.carpet_orders;
drop policy if exists "Admins can update carpet orders" on public.carpet_orders;
drop policy if exists "Admins can delete carpet orders" on public.carpet_orders;

create policy "Active users can insert own carpet orders"
on public.carpet_orders
for insert
to authenticated
with check (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
);

create policy "Employees can read own carpet orders"
on public.carpet_orders
for select
to authenticated
using (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
);

create policy "Employees can update own carpet orders"
on public.carpet_orders
for update
to authenticated
using (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
)
with check (
  public.is_active_user()
  and employee_id = auth.uid()
  and company_id = public.current_company_id()
);

create policy "Admins can read all carpet orders"
on public.carpet_orders
for select
to authenticated
using (public.is_company_admin(company_id));

create policy "Admins can update carpet orders"
on public.carpet_orders
for update
to authenticated
using (public.is_company_admin(company_id))
with check (public.is_company_admin(company_id));

create policy "Admins can delete carpet orders"
on public.carpet_orders
for delete
to authenticated
using (public.is_company_admin(company_id));

drop policy if exists "Users can read carpet order photos" on public.carpet_order_photos;
drop policy if exists "Users can insert photos for own carpet orders" on public.carpet_order_photos;
drop policy if exists "Admins can delete carpet order photos" on public.carpet_order_photos;

create policy "Users can read carpet order photos"
on public.carpet_order_photos
for select
to authenticated
using (
  public.is_super_admin()
  or company_id = public.current_company_id()
);

create policy "Users can insert photos for own carpet orders"
on public.carpet_order_photos
for insert
to authenticated
with check (
  company_id = public.current_company_id()
  and exists (
    select 1
    from public.carpet_orders
    where carpet_orders.id = carpet_order_photos.order_id
      and carpet_orders.company_id = public.current_company_id()
      and (
        carpet_orders.employee_id = auth.uid()
        or public.is_company_admin(carpet_orders.company_id)
      )
  )
);

create policy "Admins can delete carpet order photos"
on public.carpet_order_photos
for delete
to authenticated
using (public.is_company_admin(company_id));

drop policy if exists "Users can read their own device tokens" on public.device_tokens;
drop policy if exists "Users can insert their own device tokens" on public.device_tokens;
drop policy if exists "Users can update their own device tokens" on public.device_tokens;
drop policy if exists "Users can delete their own device tokens" on public.device_tokens;
drop policy if exists "Admins can read all device tokens" on public.device_tokens;

create policy "Users can read their own device tokens"
on public.device_tokens
for select
to authenticated
using (user_id = auth.uid() and company_id = public.current_company_id());

create policy "Users can insert their own device tokens"
on public.device_tokens
for insert
to authenticated
with check (user_id = auth.uid() and company_id = public.current_company_id());

create policy "Users can update their own device tokens"
on public.device_tokens
for update
to authenticated
using (user_id = auth.uid() and company_id = public.current_company_id())
with check (user_id = auth.uid() and company_id = public.current_company_id());

create policy "Users can delete their own device tokens"
on public.device_tokens
for delete
to authenticated
using (user_id = auth.uid() and company_id = public.current_company_id());

create policy "Admins can read all device tokens"
on public.device_tokens
for select
to authenticated
using (public.is_company_admin(company_id));

drop policy if exists "Users can read vehicle icons" on storage.objects;
drop policy if exists "Admins can upload vehicle icons" on storage.objects;
drop policy if exists "Admins can update vehicle icons" on storage.objects;
drop policy if exists "Admins can delete vehicle icons" on storage.objects;
drop policy if exists "Users can read carpet photos" on storage.objects;
drop policy if exists "Users can upload carpet photos" on storage.objects;
drop policy if exists "Admins can delete carpet photos" on storage.objects;

create policy "Users can read vehicle icons"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'vehicle-icons'
  and (
    public.is_super_admin()
    or public.storage_path_company_id(name) = public.current_company_id()
  )
);

create policy "Admins can upload vehicle icons"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'vehicle-icons'
  and public.is_company_admin(public.storage_path_company_id(name))
);

create policy "Admins can update vehicle icons"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'vehicle-icons'
  and public.is_company_admin(public.storage_path_company_id(name))
)
with check (
  bucket_id = 'vehicle-icons'
  and public.is_company_admin(public.storage_path_company_id(name))
);

create policy "Admins can delete vehicle icons"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'vehicle-icons'
  and public.is_company_admin(public.storage_path_company_id(name))
);

create policy "Users can read carpet photos"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'carpet-orders'
  and (
    public.is_super_admin()
    or public.storage_path_company_id(name) = public.current_company_id()
  )
);

create policy "Users can upload carpet photos"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'carpet-orders'
  and public.storage_path_company_id(name) = public.current_company_id()
  and public.is_active_user()
);

create policy "Admins can delete carpet photos"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'carpet-orders'
  and public.is_company_admin(public.storage_path_company_id(name))
);

create or replace function public.notify_admins_after_sale_insert()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  notify_sale_secret text := 'CHANGE_ME_NOTIFY_SALE_SECRET';
  supabase_publishable_key text := 'sb_publishable_JF-sPRmg9swIq6Pz7DYgPQ_InE_zUzs';
begin
  perform net.http_post(
    url := 'https://gjpqxsrsprenrhrenjxc.supabase.co/functions/v1/notify-sale',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', supabase_publishable_key,
      'Authorization', 'Bearer ' || supabase_publishable_key,
      'x-notify-sale-secret', notify_sale_secret
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'sales',
      'schema', 'public',
      'record', row_to_json(new)
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;
