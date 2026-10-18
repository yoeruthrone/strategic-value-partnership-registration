# SENA Registration Platform V3

Multi-event registration + QR attendance platform for SENA.

## V3 capabilities
- Single internal admin (secret login)
- Multi-event/project
- Simple per-event form builder
- Core fields always required: Nama Lengkap, No. Telepon, Email
- Custom field types: text, number, dropdown, radio, checkbox, textarea
- Phone + email unique per event (hard duplicate prevention)
- Unique QR generated for every registration
- QR download PNG/PDF
- Lost QR recovery via phone OR email, no OTP, no ticket code
- Per-event camera QR scanner + attendance confirmation
- External viewer per event: Total Peserta / Hadir / Belum Hadir + Excel/PDF export
- Dark mode default + light mode toggle
- SENA brand palette + supplied SENA logo
- Vercel SPA rewrite included

## Upgrade from current V2 database
Because V3 changes the data model substantially and existing test data was approved for deletion:

1. Run `supabase/maintenance/000_wipe_v2_data.sql`
2. Run `supabase/migrations/003_v3_multi_event.sql`
3. If admin secret is not set / you want to rotate it, edit and run `supabase/maintenance/001_set_admin_secret.sql`

Migration 003 rebuilds event-related tables and preserves `dashboard_access`.

## Local
```bash
cp .env.example .env
npm install
npm run dev
```

## Routes
- `/admin` — single admin login
- `/admin/events` — all events
- `/admin/events/:eventId` — event overview
- `/admin/events/:eventId/participants`
- `/admin/events/:eventId/attendance`
- `/admin/events/:eventId/form`
- `/admin/events/:eventId/settings`
- `/e/:slug/register` — public registration
- `/e/:slug/recover` — recover QR by phone/email
- `/e/:slug/ticket/:token` — QR pass
- `/view/:token` — external read-only dashboard + export

## Security notes
- No service role key in frontend.
- Public/admin data mutations happen via SECURITY DEFINER RPCs.
- Admin secret remains server-validated against bcrypt hash.
- External viewer is token-scoped to one event.
- Recovery intentionally has no OTP per product decision; anyone knowing a registrant's phone/email could retrieve the QR. Use for intended event context only.
