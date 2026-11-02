-- Restore only the backend privileges needed by create-company-user.
-- Run this entire file in Supabase Dashboard > SQL Editor.
-- service_role is a server-only role. Do not put its key in Flutter.
-- Existing authenticated-user grants and RLS policies remain unchanged.

begin;

grant usage on schema public to service_role;
grant select, insert on public.companies to service_role;
grant select, insert, update on public.profiles to service_role;
grant select, update on public.signup_requests to service_role;

commit;
