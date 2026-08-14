-- Automatic sale push notifications.
--
-- How to run:
-- 1. Deploy the Edge Function:
--    supabase functions deploy notify-sale
-- 2. Add the Edge Function secrets shown in the project notes / final answer.
-- 3. Check Supabase Dashboard > Edge Functions > notify-sale > Settings and
--    make sure JWT verification is OFF.
-- 4. Open Supabase Dashboard > SQL Editor.
-- 5. Replace CHANGE_ME_NOTIFY_SALE_SECRET below with the same value you saved
--    as the NOTIFY_SALE_SECRET Edge Function secret.
-- 6. Paste and run this whole file.
--
-- This trigger sends an async HTTP request after a sale is inserted.
-- It does not store Firebase service-account keys in the database or Flutter.

create extension if not exists pg_net with schema extensions;

grant usage on schema net to postgres, authenticated, service_role;

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

drop trigger if exists notify_admins_after_sale_insert_trigger
on public.sales;

create trigger notify_admins_after_sale_insert_trigger
after insert on public.sales
for each row
execute function public.notify_admins_after_sale_insert();

-- Optional debugging after inserting a sale:
-- select *
-- from net._http_response
-- order by created desc
-- limit 10;
