## V3.4.2
Per-event configurable additional-participant limit (2-10) and editable section label.

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

## V3.1 UI + Form Logic upgrade
See `V3_1_SETUP.md` and run the additive migration `004_v3_1_branding_logic_tables.sql` on an existing V3 database. This upgrade does not wipe registrations.

## V3.1.2
Run `supabase/migrations/005_v3_1_2_field_descriptions.sql` after V3.1.1. Adds optional helper text to all fields and mobile overflow fixes without deleting data.

## V3.1.6 final pre-production polish
Run `supabase/migrations/006_v3_1_6_privacy_recovery.sql` on an existing V3.1.5 database. This release adds admin check-in filtering, double-check QR recovery (phone + email), upload dimension guidance, SENA favicon, and a privacy-limited external viewer with masked phone numbers and no export buttons.

## V3.2
Per-event public color theme, custom private image/PDF upload fields (1 MB), reference images on custom fields, and normalized image-safe public form spacing. See `V3_2_SETUP.md`.


## V3.2.1
Minor public form polish: clean registration header, Senapro footer, Date/Calendar custom field, and no event-logo fallback when no logo is configured.

## V3.3 — Leader + Guests
V3.3 adds leader + guest registration (maximum 10 guests), with one QR for the leader and group check-in. Run `supabase/migrations/009_v3_3_group_registration.sql` on top of V3.2.1.

## V3.4.1
Guest rows now inherit leader custom-field values in admin tables and exports while still only collecting core guest identity fields in the public form. Migration 011 also backfills existing guest rows.


## V3.4.4
Active custom fields can be renamed safely without changing their internal field keys. No SQL migration required.
