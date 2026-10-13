-- Automatic signup request push notifications.
--
-- How to run:
-- 1. Deploy the Edge Function:
--    supabase functions deploy notify-signup-request
-- 2. Set the required Edge Function secrets:
--    supabase secrets set NOTIFY_SIGNUP_REQUEST_SECRET="choose-a-long-random-secret"
--    supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<firebase-service-account-json>'
-- 3. Check Supabase Dashboard > Edge Functions > notify-signup-request >
--    Settings and make sure JWT verification is OFF.
-- 4. Open Supabase Dashboard > SQL Editor.
-- 5. Replace CHANGE_ME_NOTIFY_SIGNUP_REQUEST_SECRET below with the same value
--    saved as NOTIFY_SIGNUP_REQUEST_SECRET.
-- 6. Paste and run this whole file.
--
-- This trigger sends an async HTTP request after a signup request is inserted.
-- Firebase service-account keys must stay in Edge Function secrets only.

create extension if not exists pg_net with schema extensions;

grant usage on schema net to postgres, authenticated, service_role;

create or replace function public.notify_super_admins_after_signup_request_insert()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  notify_signup_request_secret text := 'CHANGE_ME_NOTIFY_SIGNUP_REQUEST_SECRET';
  supabase_publishable_key text := 'sb_publishable_JF-sPRmg9swIq6Pz7DYgPQ_InE_zUzs';
begin
  perform net.http_post(
    url := 'https://gjpqxsrsprenrhrenjxc.supabase.co/functions/v1/notify-signup-request',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', supabase_publishable_key,
      'Authorization', 'Bearer ' || supabase_publishable_key,
      'x-notify-signup-request-secret', notify_signup_request_secret
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'signup_requests',
      'schema', 'public',
      'record', row_to_json(new)
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

drop trigger if exists notify_super_admins_after_signup_request_insert_trigger
on public.signup_requests;

create trigger notify_super_admins_after_signup_request_insert_trigger
after insert on public.signup_requests
for each row
execute function public.notify_super_admins_after_signup_request_insert();

-- Optional debugging after submitting a signup request:
-- select id, status_code, content
-- from net._http_response
-- order by created desc
-- limit 10;
