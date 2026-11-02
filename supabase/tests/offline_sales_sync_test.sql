-- Transactional tests. Apply only to a dedicated test database with schema installed.
begin;
insert into public.companies(id,name) values
 ('10000000-0000-4000-8000-000000000001','Offline test A'),
 ('10000000-0000-4000-8000-000000000002','Offline test B');
insert into public.profiles(id,company_id,full_name,role) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Test employee','employee'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Other employee','employee');
insert into public.vehicle_types(id,company_id,name,price) values
 (910001,'10000000-0000-4000-8000-000000000001','Car',200),
 (910002,'10000000-0000-4000-8000-000000000002','Other car',200);
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);

create function pg_temp.make_batch(n integer, bad integer default 0, cancelled integer default 0)
returns uuid language plpgsql as $$
declare batch uuid:=gen_random_uuid(); op uuid; action_id uuid; items jsonb:='[]'; actions jsonb:='[]'; item jsonb; metadata jsonb;
begin
 for i in 1..n+cancelled loop
   op:=gen_random_uuid(); action_id:=gen_random_uuid();
   item:=jsonb_build_object('id',op,'cancelled',i>n,'payload',jsonb_build_object(
     'vehicle_type_id',case when i<=bad then 910002 else 910001 end,'price_cents',15000,
     'created_at','2026-11-01T10:00:00.000Z','vehicle_type_name','سيارة','vehicle_name',null,'plate_number',null,'notes',null));
   items:=items||jsonb_build_array(item);
   actions:=actions||jsonb_build_array(jsonb_build_object('id',action_id,'sale_id',op,'kind','create',
     'sequence_no',i,'occurred_at','2026-11-01T10:00:00.000Z','before',null,'after',item->'payload'));
 end loop;
 select jsonb_agg(value order by value->>'id') into items from jsonb_array_elements(items);
 metadata:=jsonb_build_object('device_id',gen_random_uuid(),'expected_order_count',n,
   'expected_item_count',n+cancelled,'expected_action_count',n+cancelled,
   'manifest_hash',public.offline_hash(jsonb_build_object('items',items,'actions',actions)));
 perform public.begin_offline_sale_batch(batch,metadata);
 perform public.begin_offline_sale_batch(batch,metadata);
 -- Deliberately transport one item at a time; N must remain the full batch size.
 for item in select value from jsonb_array_elements(items) loop
   perform public.stage_offline_sale_chunk(batch,jsonb_build_array(item),'[]');
   perform public.stage_offline_sale_chunk(batch,jsonb_build_array(item),'[]');
 end loop;
 perform public.stage_offline_sale_chunk(batch,'[]',actions);
 perform public.seal_offline_sale_batch(batch);
 return batch;
end $$;

do $$
declare batch uuid; r jsonb; before_count integer; payload jsonb; op uuid:=gen_random_uuid(); sid bigint;
  individuals integer; summaries integer; expected integer;
begin
 foreach expected in array array[1,3,5,6,10,11] loop
   batch:=pg_temp.make_batch(expected);
   loop
     r:=public.process_offline_sale_batch(batch,2);
     exit when (r->>'completed')::boolean;
     if exists(select 1 from public.sale_notification_outbox where batch_id=batch and kind='offline_summary') then
       raise exception 'Premature summary'; end if;
   end loop;
   select count(*) filter(where kind='offline_sale'),count(*) filter(where kind='offline_summary')
     into individuals,summaries from public.sale_notification_outbox where batch_id=batch;
   if summaries<>1 or individuals<>(case when expected<=5 then expected else 0 end) then
     raise exception 'Wrong notification count for N=%: individuals %, summaries %',expected,individuals,summaries; end if;
   if exists(select 1 from public.sale_notification_outbox where batch_id=batch
       and (body ~ '[.][0-9]{3,}' or body like '%T10:00:%' or body like '%0 مرفوضة%')) then
     raise exception 'Notification contains unformatted price, timestamp or empty counters'; end if;
   select count(*) into before_count from public.sales;
   perform public.process_offline_sale_batch(batch,50);
   if (select count(*) from public.sales)<>before_count then raise exception 'Duplicate sale on retry'; end if;
   if (select count(*) from public.sale_notification_outbox where batch_id=batch)<>individuals+1 then
     raise exception 'Duplicate notification on retry'; end if;
 end loop;
 batch:=pg_temp.make_batch(6,1);
 r:=public.process_offline_sale_batch(batch,50);
 if (select count(*) from public.sale_sync_items where batch_id=batch and state='accepted')<>5
     or (select count(*) from public.sale_sync_items where batch_id=batch and state='rejected')<>1
     or (select count(*) from public.sale_notification_outbox where batch_id=batch)<>1 then
   raise exception 'Partial failures changed notification threshold'; end if;
 batch:=pg_temp.make_batch(0,0,1);
 perform public.process_offline_sale_batch(batch,50);
 if (select count(*) from public.sale_notification_outbox where batch_id=batch)<>1 then raise exception 'Missing cancellation summary'; end if;
 batch:=pg_temp.make_batch(1,1);
 perform public.process_offline_sale_batch(batch,50);
 if (select count(*) from public.sale_notification_outbox where batch_id=batch)<>1 then raise exception 'Missing all-rejected summary'; end if;
 payload:=jsonb_build_object('vehicle_type_id',910001,'price_cents',10000,'created_at','2026-11-01T08:00:00.000Z');
 r:=public.submit_online_sale(op,payload); sid:=(r->>'sale_id')::bigint;
 r:=public.submit_online_sale(op,payload);
 if (r->>'sale_id')::bigint<>sid then raise exception 'Online retry changed id'; end if;
 delete from public.sales where id=sid;
 perform public.submit_online_sale(op,payload);
 if exists(select 1 from public.sales where id=sid) then raise exception 'Retry resurrected deleted sale'; end if;
 begin
   perform public.submit_online_sale(op,payload||'{"price_cents":20000}');
   raise exception 'Changed payload accepted';
 exception when sqlstate '22023' then null; end;
 perform set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
 begin
   perform public.get_offline_sale_batch_report(batch);
   raise exception 'Cross-tenant report leaked';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
 update public.companies set is_active=false where id='10000000-0000-4000-8000-000000000001';
 begin
   perform public.submit_online_sale(gen_random_uuid(),payload);
   raise exception 'Suspended company wrote sale';
 exception when insufficient_privilege then null; end;
 update public.companies set is_active=true where id='10000000-0000-4000-8000-000000000001';
end $$;

set local role authenticated;
do $$ begin
 perform public.register_current_device('offline-registration-test-token','android');
 begin
   insert into public.sales(company_id,employee_id,vehicle_type_id,price,offline_batch_id)
   values('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',910001,10,gen_random_uuid());
   raise exception 'Client forged offline notification suppression';
 exception when insufficient_privilege then null; end;
 if exists(select 1 from public.sale_sync_batches where company_id='10000000-0000-4000-8000-000000000002') then
   raise exception 'Cross-tenant batch leaked'; end if;
 begin
   perform public.insert_verified_sync_sale(null,gen_random_uuid(),'{}',null);
   raise exception 'Client invoked privileged helper';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.device_tokens where token='offline-registration-test-token'
      and user_id='20000000-0000-4000-8000-000000000001') then raise exception 'Device registration owner mismatch'; end if;
  perform set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
  perform public.register_current_device('offline-registration-test-token','android');
  if not exists(select 1 from public.device_tokens where token='offline-registration-test-token'
      and user_id='20000000-0000-4000-8000-000000000002' and company_id='10000000-0000-4000-8000-000000000002') then
    raise exception 'Device ownership failed to follow the active account'; end if;
  perform set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
end $$;
insert into public.profiles(id,company_id,full_name,role) values
 ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','Test admin','admin');
insert into public.device_tokens(token,user_id,company_id) values
 ('offline-test-device','20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001');
do $$
declare worker uuid:=gen_random_uuid(); event public.sale_notification_outbox; target public.sale_notification_deliveries;
begin
 select * into event from public.claim_sale_notification_events(worker,1);
 if event.id is null then raise exception 'Missing outbox event'; end if;
 if exists(select 1 from public.claim_sale_notification_events(gen_random_uuid(),20) where id=event.id) then
   raise exception 'Two workers claimed the same live lease'; end if;
 select * into target from public.prepare_sale_notification_deliveries(event.id,worker);
 if target.token <> 'offline-test-device' then raise exception 'Wrong recipient'; end if;
 begin
   perform public.record_sale_notification_delivery(event.id,gen_random_uuid(),target.token,'sent');
   raise exception 'Wrong worker wrote delivery';
 exception when raise_exception then
   if sqlerrm <> 'Notification lease lost' then raise; end if;
 end;
 perform public.record_sale_notification_delivery(event.id,worker,target.token,'sent','test-only-provider');
 perform public.finish_sale_notification_event(event.id,worker,'sent');
 if not exists(select 1 from public.sale_notification_outbox where id=event.id and state='sent') then
   raise exception 'Event acknowledgement failed'; end if;
end $$;
rollback;
