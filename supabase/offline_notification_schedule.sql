-- Run AFTER offline_sales_sync.sql and deploying dispatch-sale-notifications.
-- Configure SALE_OUTBOX_DISPATCH_SECRET as an Edge Function secret, and create a
-- Vault secret named sale_outbox_dispatch_secret with the SAME random value.
-- Never commit the value to SQL/Flutter/Git. This file deliberately has no secret value.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

create or replace function public.wake_sale_notification_dispatcher() returns void
language plpgsql security definer set search_path='' as $$
declare secret text;
begin
  select decrypted_secret into secret from vault.decrypted_secrets where name='sale_outbox_dispatch_secret' limit 1;
  if secret is null then raise exception 'Missing sale_outbox_dispatch_secret in Vault'; end if;
  perform net.http_post(
    url:='https://gjpqxsrsprenrhrenjxc.supabase.co/functions/v1/dispatch-sale-notifications',
    headers:=jsonb_build_object('Content-Type','application/json','x-sale-dispatch-secret',secret,
      'apikey','sb_publishable_JF-sPRmg9swIq6Pz7DYgPQ_InE_zUzs',
      'Authorization','Bearer sb_publishable_JF-sPRmg9swIq6Pz7DYgPQ_InE_zUzs'),
    body:='{}'::jsonb,timeout_milliseconds:=45000);
end $$;
revoke all on function public.wake_sale_notification_dispatcher() from public,anon,authenticated;
do $$ begin
  if exists(select 1 from cron.job where jobname='sale-outbox-dispatch') then perform cron.unschedule('sale-outbox-dispatch'); end if;
end $$;
select cron.schedule('sale-outbox-dispatch','* * * * *','select public.wake_sale_notification_dispatcher()');
