-- Run in the Supabase SQL Editor to repair the server notification dispatcher.
-- No anonymous/authenticated grants or RLS policies are changed.
begin;
grant select, delete on public.device_tokens to service_role;

-- These attempts stopped before contacting Firebase. Retry only this failure;
-- successful deliveries remain in the ledger and must never be replayed.
update public.sale_notification_outbox
set state = 'pending', attempts = 0, next_attempt_at = now(),
    last_error = null, lease_owner = null, lease_until = null
where state in ('pending', 'failed')
  and last_error = 'Recipient lookup failed';
commit;
