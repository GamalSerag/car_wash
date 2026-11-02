begin;
set local role anon;
do $$
begin
  if not exists (select 1 from public.app_update_policy where platform = 'android') then
    raise exception 'Anonymous clients must be able to read version policy';
  end if;
  begin
    update public.app_update_policy set minimum_build = 999;
    raise exception 'Anonymous update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role authenticated;
do $$
begin
  if not exists (select 1 from public.app_update_policy where platform = 'android') then
    raise exception 'Authenticated clients must read version policy';
  end if;
  begin
    delete from public.app_update_policy;
    raise exception 'Client deletion unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
