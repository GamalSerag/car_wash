param(
  [string]$Psql = 'C:/Program Files/PostgreSQL/17/pgsql/bin/psql.exe',
  [int]$Port = 56439
)
$ErrorActionPreference = 'Stop'
# Dedicated local fixture database only. No production credentials or push delivery.
$setup = @'
insert into public.companies(id,name) values('60000000-0000-4000-8000-000000000001','Concurrency test');
insert into public.profiles(id,company_id,full_name) values('70000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','Concurrency employee');
insert into public.vehicle_types(id,company_id,name,price) values(920001,'60000000-0000-4000-8000-000000000001','Car',200);
'@
$setup | & $Psql -h 127.0.0.1 -p $Port -U postgres -d maghsala_test -v ON_ERROR_STOP=1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to create isolated concurrency fixture' }
$sql = @'
begin;
select set_config('request.jwt.claim.sub','70000000-0000-4000-8000-000000000001',true);
select public.submit_online_sale('80000000-0000-4000-8000-000000000001',
'{"vehicle_type_id":920001,"price_cents":20000,"created_at":"2026-11-01T10:00:00Z"}'::jsonb);
select pg_sleep(2);
commit;
'@
try {
  $jobs = @()
  1..2 | ForEach-Object {
    $jobs += Start-Job -ArgumentList $Psql,$Port,$sql -ScriptBlock {
      param($binary,$port,$query)
      $query | & $binary -h 127.0.0.1 -p $port -U postgres -d maghsala_test -v ON_ERROR_STOP=1
      if ($LASTEXITCODE -ne 0) { throw 'Concurrent SQL failed' }
    }
  }
  $jobs | Wait-Job | Out-Null
  $output = $jobs | Receive-Job
  if ($jobs.State -contains 'Failed') { throw 'Concurrent connection failed' }
  $check = @'
do $$ begin
 if (select count(*) from public.sales where company_id='60000000-0000-4000-8000-000000000001')<>1
 or (select count(*) from public.sale_sync_receipts where company_id='60000000-0000-4000-8000-000000000001')<>1
 or (select count(*) from public.sale_notification_outbox where company_id='60000000-0000-4000-8000-000000000001')<>1
 then raise exception 'Concurrent retry duplicated a sale or event'; end if;
end $$;
'@
  $check | & $Psql -h 127.0.0.1 -p $Port -U postgres -d maghsala_test -v ON_ERROR_STOP=1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Concurrency assertions failed' }
  Write-Output 'Two concurrent connections produced one sale, one receipt and one event.'
} finally {
  $cleanup = @'
delete from public.sale_notification_outbox where company_id='60000000-0000-4000-8000-000000000001';
delete from public.sale_sync_receipts where company_id='60000000-0000-4000-8000-000000000001';
delete from public.sales where company_id='60000000-0000-4000-8000-000000000001';
delete from public.vehicle_types where id=920001;
delete from public.profiles where id='70000000-0000-4000-8000-000000000001';
delete from public.companies where id='60000000-0000-4000-8000-000000000001';
'@
  $cleanup | & $Psql -h 127.0.0.1 -p $Port -U postgres -d maghsala_test -v ON_ERROR_STOP=1 | Out-Null
  if ($jobs) { $jobs | Remove-Job -Force }
}
