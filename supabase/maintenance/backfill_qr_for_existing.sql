-- Optional: issue QR credentials for participants created before migration 002.
-- Safe to run once; only rows with NULL credentials are changed.

update public.participants
set
  registration_code = public.generate_registration_code(),
  qr_token = replace(gen_random_uuid()::text, '-', ''),
  attendance_status = coalesce(attendance_status, 'REGISTERED')
where registration_code is null or qr_token is null;

insert into public.dashboard_signal default values;

select count(*) as participants_without_qr
from public.participants
where registration_code is null or qr_token is null;
