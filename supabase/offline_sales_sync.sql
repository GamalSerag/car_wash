-- Additive migration. Test against an isolated database before applying to production.
-- Run in SQL Editor AFTER existing company/input-limit migrations.
-- Deploy dispatch-sale-notifications and apply offline_notification_schedule.sql too.
begin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

alter table public.sales add column if not exists client_operation_id uuid;
alter table public.sales add column if not exists synced_at timestamptz;
alter table public.sales add column if not exists offline_batch_id uuid;
create unique index if not exists sales_client_operation_unique
  on public.sales(company_id, client_operation_id) where client_operation_id is not null;

create table if not exists public.sale_sync_batches (
  id uuid primary key, company_id uuid not null references public.companies(id),
  employee_id uuid not null references public.profiles(id), device_id uuid not null,
  expected_order_count integer not null check(expected_order_count >= 0),
  expected_item_count integer not null check(expected_item_count >= 1),
  expected_action_count integer not null check(expected_action_count >= 1),
  manifest_hash text not null check(manifest_hash ~ '^[0-9a-f]{64}$'),
  state text not null default 'receiving' check(state in ('receiving','processing','completed')),
  created_at timestamptz not null default now(), finished_at timestamptz,
  unique(company_id, id)
);
create table if not exists public.sale_sync_items (
  batch_id uuid not null, company_id uuid not null,
  employee_id uuid not null references public.profiles(id), client_operation_id uuid not null,
  payload jsonb not null, payload_hash text not null, cancelled boolean not null,
  state text not null default 'receiving' check(state in ('receiving','accepted','rejected','cancelled')),
  sale_id bigint, error_code text, already_online boolean not null default false,
  synced_at timestamptz, primary key(batch_id,client_operation_id),
  unique(company_id,client_operation_id),
  foreign key(company_id,batch_id) references public.sale_sync_batches(company_id,id)
);
create table if not exists public.sale_sync_actions (
  id uuid primary key, batch_id uuid not null, company_id uuid not null,
  employee_id uuid not null references public.profiles(id), client_operation_id uuid not null,
  sequence_no bigint not null check(sequence_no > 0),
  kind text not null check(kind in ('create','edit','cancel')), occurred_at timestamptz not null,
  body jsonb not null, unique(batch_id,sequence_no),
  foreign key(company_id,batch_id) references public.sale_sync_batches(company_id,id)
);
create table if not exists public.sale_sync_receipts (
  company_id uuid not null references public.companies(id), client_operation_id uuid not null,
  employee_id uuid not null references public.profiles(id),
  mode text not null check(mode in ('online','offline')), batch_id uuid,
  payload_hash text not null, sale_id bigint,
  outcome text not null check(outcome in ('accepted','rejected')), error_code text,
  server_received_at timestamptz not null default clock_timestamp(),
  primary key(company_id,client_operation_id)
);
create table if not exists public.sale_notification_outbox (
  id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id),
  employee_id uuid not null references public.profiles(id), batch_id uuid, client_operation_id uuid,
  event_key text unique not null, kind text not null check(kind in ('online_sale','offline_sale','offline_summary')),
  title text not null, body text not null, data jsonb not null,
  state text not null default 'pending' check(state in ('pending','processing','sent','failed','skipped')),
  attempts integer not null default 0, next_attempt_at timestamptz not null default now(),
  lease_owner uuid, lease_until timestamptz, last_error text,
  created_at timestamptz not null default now(), sent_at timestamptz
);
create table if not exists public.sale_notification_deliveries (
  event_id uuid not null references public.sale_notification_outbox(id),
  token text not null, recipient_id uuid not null references public.profiles(id),
  state text not null default 'pending' check(state in ('pending','sent','invalid','failed')),
  attempts integer not null default 0, fcm_message_name text, last_error text,
  primary key(event_id,token)
);
create index if not exists sale_outbox_due on public.sale_notification_outbox(next_attempt_at)
  where state in ('pending','processing');
create index if not exists sync_batch_owner on public.sale_sync_batches(company_id,employee_id,created_at desc);

create or replace function public.offline_canonical_json(value jsonb) returns text
language plpgsql immutable set search_path = '' as $$
declare result text;
begin
  case jsonb_typeof(value)
    when 'object' then
      select '{' || coalesce(string_agg(to_jsonb(key)::text || ':' || public.offline_canonical_json(v), ',' order by key collate "C"), '') || '}'
      into result from jsonb_each(value) as e(key,v);
    when 'array' then
      select '[' || coalesce(string_agg(public.offline_canonical_json(v), ',' order by n), '') || ']'
      into result from jsonb_array_elements(value) with ordinality as e(v,n);
    else result := coalesce(value::text,'null');
  end case;
  return result;
end $$;

create or replace function public.offline_hash(value jsonb) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(public.offline_canonical_json(value),'UTF8'),'sha256'),'hex');
$$;

create or replace function public.offline_actor() returns public.profiles
language plpgsql stable security definer set search_path = '' as $$
declare actor public.profiles;
begin
  select * into actor from public.profiles where id = auth.uid();
  if actor.id is null or not actor.is_active or actor.role not in ('employee','admin')
      or not public.is_company_active(actor.company_id) then
    raise exception 'الحساب أو الشركة غير مفعلين' using errcode='42501';
  end if;
  return actor;
end $$;

create or replace function public.protect_sale_sync_metadata() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if current_user not in ('postgres','service_role') then
    if (tg_op='INSERT' and (new.offline_batch_id is not null or new.synced_at is not null or new.client_operation_id is not null))
        or (tg_op='UPDATE' and (new.client_operation_id is distinct from old.client_operation_id
          or new.offline_batch_id is distinct from old.offline_batch_id or new.synced_at is distinct from old.synced_at)) then
      raise exception 'Sync metadata is server managed' using errcode='42501';
    end if;
  end if;
  if tg_op='INSERT' then new.synced_at := clock_timestamp(); end if;
  return new;
end $$;
drop trigger if exists protect_sale_sync_metadata on public.sales;
create trigger protect_sale_sync_metadata before insert or update on public.sales
for each row execute function public.protect_sale_sync_metadata();

create or replace function public.try_wake_sale_notifications() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if to_regprocedure('public.wake_sale_notification_dispatcher()') is not null then
    begin
      execute 'select public.wake_sale_notification_dispatcher()';
    exception when others then
      -- Wake-up is best effort. The committed outbox and cron retain delivery.
      null;
    end;
  end if;
end $$;
revoke all on function public.try_wake_sale_notifications() from public,anon,authenticated;

-- One event source for both legacy APKs and RPC online inserts. Offline inserts
-- are protected by the trigger above and queued only by the batch processor.
create or replace function public.notification_amount(amount numeric) returns text
language sql immutable set search_path = '' as $$
  select chr(8294) || rtrim(rtrim(to_char(amount, 'FM999999999999990.00'), '0'), '.') || chr(8297);
$$;

create or replace function public.notification_time(happened timestamptz) returns text
language sql stable set search_path = '' as $$
  select chr(8294) || to_char(happened at time zone 'Africa/Cairo', 'DD/MM - HH24:MI') || chr(8297);
$$;

create or replace function public.notify_admins_after_sale_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.offline_batch_id is null then
    insert into public.sale_notification_outbox(company_id,employee_id,client_operation_id,event_key,kind,title,body,data)
    values(new.company_id,new.employee_id,new.client_operation_id,
      'online/' || new.company_id || '/' || coalesce(new.client_operation_id::text,'legacy-' || new.id),
      'online_sale','عملية غسيل جديدة',
      coalesce((select v.name from public.vehicle_types v where v.id=new.vehicle_type_id),'مركبة') ||
      ' | ' || public.notification_amount(new.price) || ' ج.م' || E'\n' || public.notification_time(new.created_at),
      jsonb_build_object('type','sale_inserted','company_id',new.company_id,'sale_id',new.id::text))
    on conflict(event_key) do nothing;
    perform public.try_wake_sale_notifications();
  end if;
  return new;
end $$;
drop trigger if exists notify_admins_after_sale_insert_trigger on public.sales;
create trigger notify_admins_after_sale_insert_trigger after insert on public.sales
for each row execute function public.notify_admins_after_sale_insert();

create or replace function public.insert_verified_sync_sale(actor public.profiles, operation_id uuid, payload jsonb, batch_id uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare type_id bigint; cents bigint; happened timestamptz; sale_id bigint;
begin
  if not coalesce(payload->>'price_cents','') ~ '^[0-9]{1,8}$' then
    raise exception 'السعر غير صالح' using errcode='22023';
  end if;
  cents := (payload->>'price_cents')::bigint;
  if cents < 1 or cents > 99999999 then raise exception 'السعر خارج الحدود' using errcode='22023'; end if;
  type_id := (payload->>'vehicle_type_id')::bigint;
  if not exists(select 1 from public.vehicle_types where id=type_id and company_id=actor.company_id and is_active) then
    raise exception 'نوع المركبة غير متاح لهذه الشركة' using errcode='22023';
  end if;
  if char_length(payload->>'vehicle_name') > 100 or char_length(payload->>'plate_number') > 20
      or char_length(payload->>'notes') > 500 then raise exception 'تجاوز حد الحقول' using errcode='22001'; end if;
  happened := (payload->>'created_at')::timestamptz;
  if happened is null or not isfinite(happened) then raise exception 'وقت التسجيل غير صالح' using errcode='22023'; end if;
  insert into public.sales(company_id,employee_id,vehicle_type_id,vehicle_name,plate_number,notes,price,created_at,
    client_operation_id,offline_batch_id,synced_at)
  values(actor.company_id,actor.id,type_id,payload->>'vehicle_name',payload->>'plate_number',payload->>'notes',
    cents::numeric / 100,happened,operation_id,batch_id,clock_timestamp()) returning id into sale_id;
  return sale_id;
end $$;

create or replace function public.submit_online_sale(operation_id uuid, payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; receipt public.sale_sync_receipts; result_id bigint; hash text;
begin
  actor := public.offline_actor(); hash := public.offline_hash(payload);
  perform pg_advisory_xact_lock(hashtextextended(actor.company_id::text || operation_id::text,0));
  select * into receipt from public.sale_sync_receipts where company_id=actor.company_id and client_operation_id=operation_id;
  if found then
    if receipt.employee_id <> actor.id or receipt.payload_hash <> hash then
      raise exception 'operation_payload_conflict' using errcode='22023';
    end if;
    return jsonb_build_object('sale_id',receipt.sale_id,'outcome',receipt.outcome,'error_code',receipt.error_code,
      'sale',(select to_jsonb(s) from public.sales s where s.id=receipt.sale_id));
  end if;
  result_id := public.insert_verified_sync_sale(actor,operation_id,payload,null);
  insert into public.sale_sync_receipts(company_id,client_operation_id,employee_id,mode,payload_hash,sale_id,outcome)
  values(actor.company_id,operation_id,actor.id,'online',hash,result_id,'accepted');
  return jsonb_build_object('sale_id',result_id,'outcome','accepted',
    'sale',(select to_jsonb(s) from public.sales s where s.id=result_id));
end $$;

create or replace function public.begin_offline_sale_batch(batch_id uuid, metadata jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; batch public.sale_sync_batches;
begin
  actor := public.offline_actor();
  insert into public.sale_sync_batches(id,company_id,employee_id,device_id,expected_order_count,
    expected_item_count,expected_action_count,manifest_hash)
  values(batch_id,actor.company_id,actor.id,(metadata->>'device_id')::uuid,
    (metadata->>'expected_order_count')::integer,(metadata->>'expected_item_count')::integer,
    (metadata->>'expected_action_count')::integer,metadata->>'manifest_hash') on conflict(id) do nothing;
  select * into batch from public.sale_sync_batches where id=batch_id for update;
  if batch.employee_id <> actor.id or batch.company_id <> actor.company_id or
      batch.device_id <> (metadata->>'device_id')::uuid or batch.manifest_hash <> metadata->>'manifest_hash'
      or batch.expected_order_count <> (metadata->>'expected_order_count')::integer
      or batch.expected_item_count <> (metadata->>'expected_item_count')::integer
      or batch.expected_action_count <> (metadata->>'expected_action_count')::integer then
    raise exception 'batch_metadata_conflict' using errcode='42501';
  end if;
  return jsonb_build_object('state',batch.state);
end $$;

create or replace function public.stage_offline_sale_chunk(batch_id uuid, items jsonb, actions jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; batch public.sale_sync_batches; element jsonb; existing jsonb; item_hash text;
begin
  actor := public.offline_actor();
  select * into batch from public.sale_sync_batches b where b.id=batch_id for update;
  if batch.id is null or batch.company_id <> actor.company_id or batch.employee_id <> actor.id then
    raise exception 'دفعة غير مصرح بها' using errcode='42501';
  end if;
  if jsonb_typeof(items) <> 'array' or jsonb_typeof(actions) <> 'array'
      or jsonb_array_length(items)>50 or jsonb_array_length(actions)>50
      or octet_length(items::text)+octet_length(actions::text)>180000 then
    raise exception 'حجم دفعة النقل غير صالح' using errcode='22023';
  end if;
  for element in select value from jsonb_array_elements(items) loop
    item_hash := public.offline_hash(element);
    select jsonb_build_object('id',i.client_operation_id,'payload',i.payload,'cancelled',i.cancelled)
      into existing from public.sale_sync_items i where i.batch_id=batch.id and i.client_operation_id=(element->>'id')::uuid;
    if existing is not null then
      if public.offline_hash(existing) <> item_hash then raise exception 'item_payload_conflict' using errcode='22023'; end if;
      continue;
    end if;
    if batch.state <> 'receiving' then raise exception 'دفعة مثبتة' using errcode='22023'; end if;
    insert into public.sale_sync_items(batch_id,company_id,employee_id,client_operation_id,payload,payload_hash,cancelled)
    values(batch.id,actor.company_id,actor.id,(element->>'id')::uuid,element->'payload',
      public.offline_hash(element->'payload'),(element->>'cancelled')::boolean);
  end loop;
  for element in select value from jsonb_array_elements(actions) loop
    select a.body into existing from public.sale_sync_actions a where a.id=(element->>'id')::uuid;
    if existing is not null then
      if public.offline_hash(existing) <> public.offline_hash(element)
          or not exists(select 1 from public.sale_sync_actions a where a.id=(element->>'id')::uuid and a.batch_id=batch.id) then
        raise exception 'action_payload_conflict' using errcode='22023';
      end if;
      continue;
    end if;
    if batch.state <> 'receiving' then raise exception 'دفعة مثبتة' using errcode='22023'; end if;
    insert into public.sale_sync_actions(id,batch_id,company_id,employee_id,client_operation_id,sequence_no,kind,occurred_at,body)
    values((element->>'id')::uuid,batch.id,actor.company_id,actor.id,(element->>'sale_id')::uuid,
      (element->>'sequence_no')::bigint,element->>'kind',(element->>'occurred_at')::timestamptz,element);
  end loop;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.seal_offline_sale_batch(batch_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; batch public.sale_sync_batches; manifest jsonb; n integer; a integer; c integer;
begin
  actor := public.offline_actor();
  select * into batch from public.sale_sync_batches b where b.id=batch_id for update;
  if batch.id is null or batch.company_id <> actor.company_id or batch.employee_id <> actor.id then
    raise exception 'دفعة غير مصرح بها' using errcode='42501'; end if;
  if batch.state <> 'receiving' then return jsonb_build_object('state',batch.state); end if;
  select count(*),count(*) filter(where not cancelled) into c,n from public.sale_sync_items i where i.batch_id=batch.id;
  select count(*) into a from public.sale_sync_actions s where s.batch_id=batch.id;
  select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',i.client_operation_id,
    'payload',i.payload,'cancelled',i.cancelled) order by i.client_operation_id)
    from public.sale_sync_items i where i.batch_id=batch.id),'[]'::jsonb),
    'actions',coalesce((select jsonb_agg(s.body order by s.sequence_no) from public.sale_sync_actions s where s.batch_id=batch.id),'[]'::jsonb)) into manifest;
  if n <> batch.expected_order_count or c <> batch.expected_item_count or a <> batch.expected_action_count
      or public.offline_hash(manifest) <> batch.manifest_hash then
    raise exception 'الدفعة غير مكتملة أو تغير محتواها' using errcode='22023'; end if;
  if exists(select 1 from public.sale_sync_actions s where s.batch_id=batch.id and not exists
    (select 1 from public.sale_sync_items i where i.batch_id=batch.id and i.client_operation_id=s.client_operation_id)) then
    raise exception 'حدث بدون طلب' using errcode='22023'; end if;
  update public.sale_sync_batches b set state='processing' where b.id=batch.id;
  return jsonb_build_object('state','processing');
end $$;

create or replace function public.process_offline_sale_batch(batch_id uuid, limit_count integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; batch public.sale_sync_batches; item public.sale_sync_items; receipt public.sale_sync_receipts;
  sid bigint; result jsonb := '[]'; code text; success_count integer; failed_count integer; cancelled_count integer;
  edit_count integer; total_cents bigint; is_completed boolean; period_start text; period_end text;
begin
  actor := public.offline_actor();
  select * into batch from public.sale_sync_batches b where b.id=batch_id for update;
  if batch.id is null or batch.company_id <> actor.company_id or batch.employee_id <> actor.id then
    raise exception 'دفعة غير مصرح بها' using errcode='42501'; end if;
  if batch.state='receiving' then raise exception 'لم تكتمل بيانات الدفعة' using errcode='22023'; end if;
  for item in select * from public.sale_sync_items i where i.batch_id=batch.id and i.state='receiving'
      order by i.client_operation_id limit greatest(1,least(limit_count,50)) for update loop
    code := null; sid := null;
    if item.cancelled then
      update public.sale_sync_items i set state='cancelled',synced_at=clock_timestamp()
        where i.batch_id=batch.id and i.client_operation_id=item.client_operation_id;
    else
      perform pg_advisory_xact_lock(hashtextextended(actor.company_id::text || item.client_operation_id::text,0));
      select * into receipt from public.sale_sync_receipts r where r.company_id=actor.company_id and r.client_operation_id=item.client_operation_id;
      if found then
        if receipt.employee_id <> actor.id or receipt.payload_hash <> item.payload_hash then
          raise exception 'receipt_payload_conflict' using errcode='22023'; end if;
        sid := receipt.sale_id; code := receipt.error_code;
        update public.sale_sync_items i set already_online=receipt.mode='online'
          where i.batch_id=batch.id and i.client_operation_id=item.client_operation_id;
      else
        begin
          sid := public.insert_verified_sync_sale(actor,item.client_operation_id,item.payload,batch.id);
        exception when sqlstate '22001' or sqlstate '22003' or sqlstate '22023' or sqlstate '22P02'
            or sqlstate '22007' or sqlstate '22008' or sqlstate '23503' or sqlstate '23514' then
          code := sqlerrm;
        end;
        insert into public.sale_sync_receipts(company_id,client_operation_id,employee_id,mode,batch_id,payload_hash,sale_id,outcome,error_code)
        values(actor.company_id,item.client_operation_id,actor.id,'offline',batch.id,item.payload_hash,sid,
          case when sid is null then 'rejected' else 'accepted' end,code);
      end if;
      update public.sale_sync_items i set state=case when sid is null then 'rejected' else 'accepted' end,
        sale_id=sid,error_code=code,synced_at=clock_timestamp() where i.batch_id=batch.id and i.client_operation_id=item.client_operation_id;
      if sid is not null and batch.expected_order_count between 1 and 5
          and not exists(select 1 from public.sale_sync_items i where i.batch_id=batch.id and i.client_operation_id=item.client_operation_id and i.already_online) then
        insert into public.sale_notification_outbox(company_id,employee_id,batch_id,client_operation_id,event_key,kind,title,body,data)
        values(actor.company_id,actor.id,batch.id,item.client_operation_id,
          'offline/' || actor.company_id || '/' || batch.id || '/sale/' || item.client_operation_id,
          'offline_sale','غسلة جديدة (بدون إنترنت)',
          coalesce(item.payload->>'vehicle_type_name','مركبة') || ' | ' ||
          public.notification_amount((item.payload->>'price_cents')::numeric/100) ||
          ' ج.م' || E'\n' || public.notification_time((item.payload->>'created_at')::timestamptz),
          jsonb_build_object('type','sale_inserted','company_id',actor.company_id,'sale_id',sid::text,'batch_id',batch.id))
        on conflict(event_key) do nothing;
      end if;
    end if;
    select result || jsonb_build_array(jsonb_build_object('id',i.client_operation_id,'state',i.state,
      'sale_id',i.sale_id,'error_code',i.error_code)) into result
      from public.sale_sync_items i where i.batch_id=batch.id and i.client_operation_id=item.client_operation_id;
  end loop;
  is_completed := not exists(select 1 from public.sale_sync_items i where i.batch_id=batch.id and i.state='receiving');
  if is_completed and batch.state <> 'completed' then
    select count(*) filter(where state='accepted' and not already_online),count(*) filter(where state='rejected'),
      count(*) filter(where state='cancelled'),coalesce(sum((payload->>'price_cents')::bigint)
        filter(where state='accepted' and not already_online),0)
      into success_count,failed_count,cancelled_count,total_cents from public.sale_sync_items i where i.batch_id=batch.id;
    select count(*) into edit_count from public.sale_sync_actions a where a.batch_id=batch.id and a.kind='edit';
    select public.notification_time(min(occurred_at)),
      public.notification_time(max(occurred_at)) into period_start,period_end
      from public.sale_sync_actions a where a.batch_id=batch.id;
    insert into public.sale_notification_outbox(company_id,employee_id,batch_id,event_key,kind,title,body,data)
    values(actor.company_id,actor.id,batch.id,'offline/' || actor.company_id || '/' || batch.id || '/summary',
      'offline_summary','ملخص العمليات بدون إنترنت',
      success_count || ' غسلات | الإجمالي: ' || public.notification_amount(total_cents::numeric/100) || ' ج.م' ||
      E'\n' || left(actor.full_name,100) || E'\n' || coalesce(period_start,'') ||
      case when period_start is distinct from period_end then ' إلى ' || coalesce(period_end,'') else '' end ||
      case when failed_count+cancelled_count+edit_count>0 then E'\n' || concat_ws(' | ',
        case when failed_count>0 then 'مرفوضة: ' || failed_count end,
        case when cancelled_count>0 then 'ملغاة: ' || cancelled_count end,
        case when edit_count>0 then 'تعديلات: ' || edit_count end) else '' end,
      jsonb_build_object('type','offline_sale_summary','company_id',actor.company_id,'batch_id',batch.id))
    on conflict(event_key) do nothing;
    update public.sale_sync_batches b set state='completed',finished_at=clock_timestamp() where b.id=batch.id;
  end if;
  if result <> '[]'::jsonb and (batch.expected_order_count <= 5 or is_completed) then
    perform public.try_wake_sale_notifications();
  end if;
  return jsonb_build_object('completed',is_completed,'results',result);
end $$;

create or replace function public.get_offline_sale_batch_report(batch_id uuid, page_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare batch public.sale_sync_batches; results jsonb; actions jsonb; totals jsonb; header jsonb;
begin
  select * into batch from public.sale_sync_batches b where b.id=batch_id;
  if batch.id is null or not ((public.is_active_user() and batch.employee_id=auth.uid()
      and batch.company_id=public.current_company_id()) or public.is_company_admin(batch.company_id)) then
    raise exception 'التقرير غير متاح لهذا الحساب' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into results from
    (select i.* from public.sale_sync_items i where i.batch_id=batch.id order by i.client_operation_id
      limit 50 offset greatest(page_offset,0)) r;
  select coalesce(jsonb_agg(r.body),'[]') into actions from
    (select a.body from public.sale_sync_actions a where a.batch_id=batch.id order by a.sequence_no
      limit 50 offset greatest(page_offset,0)) r;
  select jsonb_build_object('accepted',count(*) filter(where state='accepted' and not already_online),
    'rejected',count(*) filter(where state='rejected'),'cancelled',count(*) filter(where state='cancelled'),
    'total_cents',coalesce(sum((payload->>'price_cents')::bigint) filter(where state='accepted' and not already_online),0))
    into totals from public.sale_sync_items where sale_sync_items.batch_id=batch.id;
  select to_jsonb(batch) || jsonb_build_object('employee_name',
    (select full_name from public.profiles where id=batch.employee_id),
    'period_start',min(occurred_at),'period_end',max(occurred_at)) into header
    from public.sale_sync_actions where sale_sync_actions.batch_id=batch.id;
  return jsonb_build_object('batch',header,'items',results,'actions',actions,'totals',totals);
end $$;

-- Reports are readable with tenant/owner checks; writes are RPC-only.
do $$ declare table_name text; begin
  foreach table_name in array array['sale_sync_batches','sale_sync_items','sale_sync_actions','sale_sync_receipts',
      'sale_notification_outbox','sale_notification_deliveries'] loop
    execute format('alter table public.%I enable row level security',table_name);
    execute format('revoke all on public.%I from anon,authenticated',table_name);
    execute format('grant all on public.%I to service_role',table_name);
    if table_name like 'sale_sync_%' then
      execute format('grant select on public.%I to authenticated',table_name);
      execute format('drop policy if exists "Read own sync or company admin" on public.%I',table_name);
      execute format('create policy "Read own sync or company admin" on public.%I for select to authenticated using
        ((public.is_active_user() and employee_id=auth.uid() and company_id=public.current_company_id()) or public.is_company_admin(company_id))',table_name);
    end if;
  end loop;
end $$;

-- Helpers cannot be invoked by clients to forge actors or bypass batch rules.
revoke all on function public.offline_actor() from public,anon,authenticated;
revoke all on function public.insert_verified_sync_sale(public.profiles,uuid,jsonb,uuid) from public,anon,authenticated;
revoke all on function public.notify_admins_after_sale_insert() from public,anon,authenticated;
do $$ declare signature text; begin
  foreach signature in array array['submit_online_sale(uuid,jsonb)','begin_offline_sale_batch(uuid,jsonb)',
    'stage_offline_sale_chunk(uuid,jsonb,jsonb)','seal_offline_sale_batch(uuid)',
    'process_offline_sale_batch(uuid,integer)','get_offline_sale_batch_report(uuid,integer)'] loop
    execute 'revoke all on function public.' || signature || ' from public,anon';
    execute 'grant execute on function public.' || signature || ' to authenticated';
  end loop;
end $$;

create or replace function public.claim_sale_notification_events(worker uuid, limit_count integer default 20)
returns setof public.sale_notification_outbox
language plpgsql security definer set search_path = '' as $$
begin
  update public.sale_notification_outbox set state='failed',last_error='Lease expired after final attempt'
    where state='processing' and lease_until<clock_timestamp() and attempts>=8;
  return query update public.sale_notification_outbox o
    set state='processing',lease_owner=worker,lease_until=clock_timestamp()+interval '3 minutes',attempts=o.attempts+1
    where o.id in (select n.id from public.sale_notification_outbox n
      where n.attempts<8 and ((n.state='pending' and n.next_attempt_at<=clock_timestamp())
        or (n.state='processing' and n.lease_until<clock_timestamp()))
      order by n.created_at for update skip locked limit greatest(1,least(limit_count,20))) returning o.*;
end $$;

create or replace function public.prepare_sale_notification_deliveries(event_id uuid, worker uuid)
returns setof public.sale_notification_deliveries
language plpgsql security definer set search_path = '' as $$
declare event public.sale_notification_outbox;
begin
  select * into event from public.sale_notification_outbox o where o.id=event_id
    and o.lease_owner=worker and o.lease_until>clock_timestamp() for update;
  if event.id is null then raise exception 'Notification lease lost'; end if;
  if not public.is_company_active(event.company_id) then return; end if;
  insert into public.sale_notification_deliveries(event_id,token,recipient_id)
  select event.id,t.token,p.id from public.device_tokens t join public.profiles p on p.id=t.user_id
    where p.role='admin' and p.is_active and p.company_id=event.company_id and t.company_id=event.company_id
  on conflict do nothing;
  return query select d.* from public.sale_notification_deliveries d
    where d.event_id=event.id and d.state in ('pending','failed') and d.attempts<8;
end $$;

create or replace function public.record_sale_notification_delivery(event_id uuid, worker uuid, device_token text,
    delivery_state text, provider_name text default null, failure text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if delivery_state not in ('sent','invalid','failed') then raise exception 'Invalid delivery state'; end if;
  perform 1 from public.sale_notification_outbox o where o.id=event_id and o.lease_owner=worker
    and o.lease_until>clock_timestamp() for update;
  if not found then raise exception 'Notification lease lost'; end if;
  update public.sale_notification_deliveries d set state=delivery_state,attempts=d.attempts+1,
    fcm_message_name=provider_name,last_error=left(failure,500)
    where d.event_id=record_sale_notification_delivery.event_id and d.token=device_token;
end $$;

create or replace function public.finish_sale_notification_event(event_id uuid, worker uuid, desired_state text,
    failure text default null, retry_after integer default 30) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if desired_state not in ('sent','pending','failed','skipped') then raise exception 'Invalid event state'; end if;
  update public.sale_notification_outbox o set
    state=case when o.attempts>=8 and desired_state='pending' then 'failed' else desired_state end,
    sent_at=case when desired_state='sent' then clock_timestamp() else null end,
    next_attempt_at=clock_timestamp()+make_interval(secs=>greatest(30,least(retry_after,1800))),
    last_error=left(failure,500),lease_owner=null,lease_until=null
    where o.id=event_id and o.lease_owner=worker and o.lease_until>clock_timestamp();
end $$;

do $$ declare signature text; begin
  foreach signature in array array['claim_sale_notification_events(uuid,integer)',
    'prepare_sale_notification_deliveries(uuid,uuid)',
    'record_sale_notification_delivery(uuid,uuid,text,text,text,text)',
    'finish_sale_notification_event(uuid,uuid,text,text,integer)'] loop
    execute 'revoke all on function public.' || signature || ' from public,anon,authenticated';
    execute 'grant execute on function public.' || signature || ' to service_role';
  end loop;
end $$;

create or replace function public.enqueue_legacy_sale_notification(sale_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare sale public.sales;
begin
  select * into sale from public.sales s where s.id=sale_id and s.offline_batch_id is null;
  if sale.id is null or not public.is_company_active(sale.company_id) then return; end if;
  insert into public.sale_notification_outbox(company_id,employee_id,client_operation_id,event_key,kind,title,body,data)
  values(sale.company_id,sale.employee_id,sale.client_operation_id,
    'online/' || sale.company_id || '/' || coalesce(sale.client_operation_id::text,'legacy-' || sale.id),
    'online_sale','عملية غسيل جديدة',
    coalesce((select v.name from public.vehicle_types v where v.id=sale.vehicle_type_id),'مركبة') ||
    ' | ' || public.notification_amount(sale.price) || ' ج.م' || E'\n' || public.notification_time(sale.created_at),
    jsonb_build_object('type','sale_inserted','company_id',sale.company_id,'sale_id',sale.id::text))
  on conflict(event_key) do nothing;
end $$;
revoke all on function public.enqueue_legacy_sale_notification(bigint) from public,anon,authenticated;
grant execute on function public.enqueue_legacy_sale_notification(bigint) to service_role;

create or replace function public.register_current_device(device_token text, device_platform text) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles;
begin
  select * into actor from public.profiles where id=auth.uid();
  if actor.id is null or not actor.is_active or (actor.role<>'super_admin' and not public.is_company_active(actor.company_id)) then
    raise exception 'Inactive account' using errcode='42501'; end if;
  if char_length(device_token) not between 20 and 4096 or char_length(device_platform)>20 then
    raise exception 'Invalid device token' using errcode='22023'; end if;
  insert into public.device_tokens(user_id,company_id,token,platform,updated_at)
  values(actor.id,actor.company_id,device_token,device_platform,clock_timestamp())
  on conflict(token) do update set user_id=excluded.user_id,company_id=excluded.company_id,
    platform=excluded.platform,updated_at=excluded.updated_at;
end $$;
revoke all on function public.register_current_device(text,text) from public,anon;
grant execute on function public.register_current_device(text,text) to authenticated;

-- BYPASSRLS does not grant table access. The dispatcher rechecks token ownership
-- and removes tokens only after Firebase reports them as unregistered.
grant select, delete on public.device_tokens to service_role;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists
      (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='sales') then
    alter publication supabase_realtime add table public.sales;
  end if;
end $$;
commit;
