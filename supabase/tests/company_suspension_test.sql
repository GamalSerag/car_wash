-- Run after company_access_control.sql. Every fixture is rolled back.
-- This uses transaction-local users and companies, never existing customer data.
begin;

insert into public.companies (id, name, is_active) values
('f3f50000-0000-4000-8000-000000000001', 'Suspension test active', true),
('f3f50000-0000-4000-8000-000000000002', 'Suspension test inactive', false),
('f3f50000-0000-4000-8000-000000000003', 'Suspension test super admin', false);

insert into auth.users (id, email, raw_user_meta_data) values
('f3f50000-0000-4000-8000-000000000011', 'suspension-admin-active@example.invalid', '{"full_name":"test","company_id":"f3f50000-0000-4000-8000-000000000001"}'),
('f3f50000-0000-4000-8000-000000000012', 'suspension-employee-active@example.invalid', '{"full_name":"test","company_id":"f3f50000-0000-4000-8000-000000000001"}'),
('f3f50000-0000-4000-8000-000000000021', 'suspension-admin-inactive@example.invalid', '{"full_name":"test","company_id":"f3f50000-0000-4000-8000-000000000002"}'),
('f3f50000-0000-4000-8000-000000000022', 'suspension-employee-inactive@example.invalid', '{"full_name":"test","company_id":"f3f50000-0000-4000-8000-000000000002"}'),
('f3f50000-0000-4000-8000-000000000031', 'suspension-super-admin@example.invalid', '{"full_name":"test","company_id":"f3f50000-0000-4000-8000-000000000003"}');

update public.profiles set role = 'admin'
where id in ('f3f50000-0000-4000-8000-000000000011', 'f3f50000-0000-4000-8000-000000000021');
update public.profiles set role = 'super_admin' where id = 'f3f50000-0000-4000-8000-000000000031';

insert into public.vehicle_types (id, company_id, name, price) values
(-940001, 'f3f50000-0000-4000-8000-000000000001', 'test', 10),
(-940002, 'f3f50000-0000-4000-8000-000000000002', 'test', 10);
insert into public.sales (id, company_id, vehicle_type_id, price, employee_id) values
(-940001, 'f3f50000-0000-4000-8000-000000000001', -940001, 10, 'f3f50000-0000-4000-8000-000000000012'),
(-940002, 'f3f50000-0000-4000-8000-000000000002', -940002, 10, 'f3f50000-0000-4000-8000-000000000022');
insert into public.carpet_orders (id, company_id, customer_name, phone_number, total_price, employee_id) values
(-940001, 'f3f50000-0000-4000-8000-000000000001', 'test', '0', 10, 'f3f50000-0000-4000-8000-000000000012'),
(-940002, 'f3f50000-0000-4000-8000-000000000002', 'test', '0', 10, 'f3f50000-0000-4000-8000-000000000022');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f3f50000-0000-4000-8000-000000000012","role":"authenticated"}', true);
do $$
begin
  assert public.is_active_user(), 'Active employee blocked';
  assert public.current_company_id() = 'f3f50000-0000-4000-8000-000000000001', 'Wrong active company';
  assert (select count(*) from public.sales where id in (-940001, -940002)) = 1, 'Cross-tenant sales visibility';
  assert (select count(*) from public.carpet_orders where id in (-940001, -940002)) = 1, 'Cross-tenant carpet visibility';
  insert into public.sales (id, company_id, vehicle_type_id, price, employee_id)
  values (-940003, 'f3f50000-0000-4000-8000-000000000001', -940001, 10, auth.uid());
  begin
    insert into public.sales (id, company_id, vehicle_type_id, price, employee_id)
    values (-940004, 'f3f50000-0000-4000-8000-000000000002', -940002, 10, auth.uid());
    raise exception 'Cross-tenant sale insert allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claims', '{"sub":"f3f50000-0000-4000-8000-000000000011","role":"authenticated"}', true);
do $$
begin
  assert public.is_company_admin('f3f50000-0000-4000-8000-000000000001'), 'Active admin blocked';
  assert not public.is_company_admin('f3f50000-0000-4000-8000-000000000002'), 'Cross-company admin access';
  begin
    update public.profiles set role = 'super_admin' where id = auth.uid();
    raise exception 'Admin promoted themselves to bypass suspension';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claims', '{"sub":"f3f50000-0000-4000-8000-000000000022","role":"authenticated"}', true);
do $$
begin
  assert not public.is_active_user(), 'Suspended employee still active';
  assert public.current_company_id() is null, 'Suspended employee retains company access';
  assert (select count(*) from public.sales where id in (-940001, -940002)) = 0, 'Suspended employee reads sales';
  assert (select count(*) from public.carpet_orders where id in (-940001, -940002)) = 0, 'Suspended employee reads carpets';
  assert (select count(*) from public.vehicle_types where id in (-940001, -940002)) = 0, 'Suspended employee reads vehicle types';
  assert (select count(*) from public.profiles where id = auth.uid()) = 1, 'Own profile hidden during suspension';
  assert (select count(*) from public.companies where id = 'f3f50000-0000-4000-8000-000000000002' and not is_active) = 1, 'Suspension status cannot be read';
  begin
    insert into public.sales (id, company_id, vehicle_type_id, price, employee_id)
    values (-940004, 'f3f50000-0000-4000-8000-000000000002', -940002, 10, auth.uid());
    raise exception 'Suspended employee inserted sale';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.carpet_orders (id, company_id, customer_name, phone_number, total_price, employee_id)
    values (-940004, 'f3f50000-0000-4000-8000-000000000002', 'test', '0', 10, auth.uid());
    raise exception 'Suspended employee inserted carpet order';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claims', '{"sub":"f3f50000-0000-4000-8000-000000000021","role":"authenticated"}', true);
do $$
declare affected integer;
begin
  assert not public.is_admin(), 'Suspended admin still has admin access';
  assert not public.is_company_admin('f3f50000-0000-4000-8000-000000000002'), 'Suspended company admin permitted';
  assert (select count(*) from public.sales where id = -940002) = 0, 'Suspended admin reads sales';
  update public.sales set notes = 'not allowed' where id = -940002;
  get diagnostics affected = row_count;
  assert affected = 0, 'Suspended admin updated sale';
  delete from public.carpet_orders where id = -940002;
  get diagnostics affected = row_count;
  assert affected = 0, 'Suspended admin deleted carpet order';
  update public.companies set is_active = true where id = 'f3f50000-0000-4000-8000-000000000002';
  get diagnostics affected = row_count;
  assert affected = 0, 'Suspended admin reactivated company';
end;
$$;

select set_config('request.jwt.claims', '{"sub":"f3f50000-0000-4000-8000-000000000031","role":"authenticated"}', true);
do $$
begin
  assert public.is_super_admin(), 'Super admin lost management access';
  assert public.is_active_user(), 'Super admin blocked by own inactive company';
  assert public.is_company_admin('f3f50000-0000-4000-8000-000000000002'), 'Super admin cannot manage suspended company';
  assert (select count(*) from public.sales where id in (-940001, -940002)) = 2, 'Super admin cannot inspect records';
  update public.companies set is_active = true where id = 'f3f50000-0000-4000-8000-000000000002';
end;
$$;

select set_config('request.jwt.claims', '{"sub":"f3f50000-0000-4000-8000-000000000022","role":"authenticated"}', true);
do $$
begin
  assert public.is_active_user(), 'Employee not restored after reactivation';
  assert (select count(*) from public.sales where id = -940002) = 1, 'Historical sale not restored';
  assert (select is_active from public.profiles where id = auth.uid()), 'User flags changed by suspension';
end;
$$;
reset role;
rollback;
