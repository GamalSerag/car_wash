-- Run after carpet_order_piece_count.sql in Supabase SQL Editor.
-- Enforces the same input bounds as Flutter for direct API writes too.
-- Existing data is not truncated. Unchanged legacy values are left alone.
-- Passwords stay in Supabase Auth; create-company-user validates their length.
begin;

create or replace function public.enforce_input_limits()
returns trigger
language plpgsql security invoker
set search_path = ''
as $$
declare
  current_data jsonb := to_jsonb(new);
  previous_data jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  field_name text;
  field_limit text;
  amount numeric;
begin
  for field_name, field_limit in select key, value from jsonb_each_text(tg_argv[0]::jsonb)
  loop
    if tg_op = 'UPDATE' and current_data -> field_name is not distinct from previous_data -> field_name then
      continue;
    end if;
    if char_length(current_data ->> field_name) > field_limit::integer then
      raise exception 'Field % exceeds its maximum length (%)', field_name, field_limit
        using errcode = '22001';
    end if;
  end loop;

  for field_name, field_limit in select key, value from jsonb_each_text(tg_argv[1]::jsonb)
  loop
    if (tg_op = 'UPDATE' and current_data -> field_name is not distinct from previous_data -> field_name)
        or current_data ->> field_name is null then
      continue;
    end if;
    amount := (current_data ->> field_name)::numeric;
    if not (amount >= 0 and amount <= field_limit::numeric) then
      raise exception 'Field % must be between zero and %', field_name, field_limit
        using errcode = '22003';
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists input_limits on public.companies;
create trigger input_limits before insert or update on public.companies
for each row execute function public.enforce_input_limits('{"name":100}', '{}');

drop trigger if exists input_limits on public.profiles;
create trigger input_limits before insert or update on public.profiles
for each row execute function public.enforce_input_limits('{"full_name":100}', '{}');

drop trigger if exists input_limits on public.vehicle_types;
create trigger input_limits before insert or update on public.vehicle_types
for each row execute function public.enforce_input_limits('{"name":100}', '{"price":999999.99}');

drop trigger if exists input_limits on public.sales;
create trigger input_limits before insert or update on public.sales
for each row execute function public.enforce_input_limits(
  '{"vehicle_name":100,"plate_number":20,"notes":500}', '{"price":999999.99}');

drop trigger if exists input_limits on public.carpet_orders;
create trigger input_limits before insert or update on public.carpet_orders
for each row execute function public.enforce_input_limits(
  '{"customer_name":100,"phone_number":20,"notes":500}',
  '{"total_price":999999.99,"paid_amount":999999.99,"remaining_amount":999999.99,"piece_count":9999}');

drop trigger if exists input_limits on public.signup_requests;
create trigger input_limits before insert or update on public.signup_requests
for each row execute function public.enforce_input_limits(
  '{"company_name":100,"owner_name":100,"phone":20,"email":254,"address":250,"notes":500}', '{}');

commit;
