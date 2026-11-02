-- Read-only regression checks. Safe to run in the SQL Editor after the repair.
begin;
do $$
begin
  if not has_table_privilege('service_role', 'public.device_tokens', 'SELECT')
     or not has_table_privilege('service_role', 'public.device_tokens', 'DELETE') then
    raise exception 'Dispatcher cannot verify or retire device tokens';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.device_tokens'::regclass) then
    raise exception 'Device token RLS must remain enabled';
  end if;
  if has_function_privilege('authenticated', 'public.claim_sale_notification_events(uuid,integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.claim_sale_notification_events(uuid,integer)', 'EXECUTE') then
    raise exception 'Only the trusted server may claim notifications';
  end if;
end $$;
rollback;
