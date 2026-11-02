-- Run after input_limits.sql. All fixtures use a temporary table and roll back.
begin;
create temporary table input_limit_test (
  id integer primary key,
  name text,
  notes text,
  price numeric(10,2),
  piece_count integer check (piece_count > 0)
);
-- Simulate historical records created before limits existed.
insert into input_limit_test values (1, repeat('a', 101), 'old', 1000000, 1);
create trigger input_limits before insert or update on input_limit_test
for each row execute function public.enforce_input_limits(
  '{"name":100,"notes":500}', '{"price":999999.99,"piece_count":9999}');
do $$
begin
  update input_limit_test set notes = 'changed' where id = 1;
  assert (select length(name) = 101 and price = 1000000 from input_limit_test where id = 1),
    'Unchanged historical values were modified';
  insert into input_limit_test values (2, repeat('a',100), repeat('n',500), 999999.99, 9999);
  begin
    insert into input_limit_test values (3, repeat('a',101), null, 1, 1);
    raise exception 'Overlong name accepted';
  exception when string_data_right_truncation then null;
  end;
  begin
    update input_limit_test set notes = repeat('n',501) where id = 2;
    raise exception 'Overlong notes accepted';
  exception when string_data_right_truncation then null;
  end;
  begin
    update input_limit_test set price = 1000000 where id = 2;
    raise exception 'Oversized price accepted';
  exception when numeric_value_out_of_range then null;
  end;
  begin
    update input_limit_test set price = 'NaN'::numeric where id = 2;
    raise exception 'NaN price accepted';
  exception when numeric_value_out_of_range then null;
  end;
  begin
    update input_limit_test set price = -1 where id = 2;
    raise exception 'Negative price accepted';
  exception when numeric_value_out_of_range then null;
  end;
  begin
    update input_limit_test set piece_count = 10000 where id = 2;
    raise exception 'Oversized piece count accepted';
  exception when numeric_value_out_of_range then null;
  end;
end;
$$;
rollback;
