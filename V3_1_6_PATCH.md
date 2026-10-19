# V3.1.6 — Final pre-production polish

- Attendance/check-in filter on admin registration tables.
- Removed explanatory paragraph from Form Builder header.
- Added image dimension guidance for event logo, banner, and background uploads.
- Added SENA favicon.
- QR recovery now requires both phone and email.
- External viewer spacing refined.
- External viewer no longer exports Excel/PDF.
- External viewer only receives/displays date, time, name, masked phone, attendance status, and check-in.
- Includes all V3.1.5 admin secret eye + 1-hour session behavior.

## Database
Run only `supabase/migrations/006_v3_1_6_privacy_recovery.sql` on an existing V3.1.5 database. Do not wipe data.
