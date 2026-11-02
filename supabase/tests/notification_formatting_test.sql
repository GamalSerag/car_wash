-- Read-only formatting checks; no sales, devices or notifications are inserted.
begin;
do $$
declare formatted text;
begin
  if public.notification_amount(60.0000000000000000) <> chr(8294)||'60'||chr(8297)
     or public.notification_amount(100.50) <> chr(8294)||'100.5'||chr(8297)
     or public.notification_amount(1234.56) <> chr(8294)||'1234.56'||chr(8297)
     or public.notification_amount(0) <> chr(8294)||'0'||chr(8297) then
    raise exception 'Amounts must have at most two decimal places and no redundant zeros';
  end if;
  formatted := public.notification_time('2026-11-02T00:55:32.495336Z');
  if formatted <> chr(8294)||'02/11 - 02:55'||chr(8297) then
    raise exception 'Notification time must use Cairo time, minutes only, isolated LTR';
  end if;
  if public.notification_time('2026-07-01T00:05:00Z') <> chr(8294)||'01/07 - 03:05'||chr(8297) then
    raise exception 'Cairo daylight saving conversion failed';
  end if;
end $$;
rollback;
