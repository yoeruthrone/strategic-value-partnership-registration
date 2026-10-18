-- USER-APPROVED WIPE BEFORE V3
-- Removes old registration/event data only. Keeps dashboard_access (admin secret).
begin;
truncate table public.dashboard_signal restart identity cascade;
truncate table public.participants restart identity cascade;
truncate table public.registrations restart identity cascade;
commit;
select 'WIPED' as status;
