-- Run after carpet_order_piece_count.sql. All fixtures are rolled back.
begin;
insert into public.companies (id, name) values
('f4f60000-0000-4000-8000-000000000001', 'Piece count test');
insert into auth.users (id, email, raw_user_meta_data) values
('f4f60000-0000-4000-8000-000000000011', 'piece-count-test@example.invalid',
'{"full_name":"test","company_id":"f4f60000-0000-4000-8000-000000000001"}');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f4f60000-0000-4000-8000-000000000011","role":"authenticated"}', true);
do $$
begin
  insert into public.carpet_orders
    (id, company_id, customer_name, phone_number, total_price, paid_amount, remaining_amount, employee_id)
  values (-950001, 'f4f60000-0000-4000-8000-000000000001', 'test', '0', 100, 20, 80, auth.uid());
  assert (select piece_count from public.carpet_orders where id = -950001) = 1,
    'Old clients must default to one piece';
  update public.carpet_orders set piece_count = 5 where id = -950001;
  assert (select piece_count from public.carpet_orders where id = -950001) = 5,
    'New piece count was not saved';
  assert (select total_price = 100 and paid_amount = 20 and remaining_amount = 80
    from public.carpet_orders where id = -950001), 'Piece count changed order money';
  begin
    update public.carpet_orders set piece_count = 0 where id = -950001;
    raise exception 'Zero pieces accepted';
  exception when check_violation then null;
  end;
  begin
    update public.carpet_orders set piece_count = -1 where id = -950001;
    raise exception 'Negative pieces accepted';
  exception when check_violation or numeric_value_out_of_range then null;
  end;
  begin
    update public.carpet_orders set piece_count = null where id = -950001;
    raise exception 'Null pieces accepted';
  exception when not_null_violation then null;
  end;
  begin
    update public.carpet_orders set piece_count = 10000 where id = -950001;
    raise exception 'Oversized pieces accepted';
  exception when check_violation or numeric_value_out_of_range then null;
  end;
  update public.carpet_orders set notes = 'Old client update' where id = -950001;
  assert (select piece_count from public.carpet_orders where id = -950001) = 5,
    'Old client update reset piece count';
end;
$$;
reset role;
rollback;
