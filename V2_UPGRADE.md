# V2 QR Attendance Upgrade

## What changed
- One unique QR per new registration.
- Unique registration code, e.g. `SVP-A1B2C3D4`.
- Success page shows ticket + QR.
- Download QR as PNG.
- Download ticket as PDF.
- Lost QR recovery at `/ticket` using phone + registration code.
- Direct ticket URL `/ticket/:token` encoded in QR.
- Internal `Scan QR` tab for browser camera check-in.
- Confirm attendance action, protected by existing dashboard secret.
- Re-scan shows already checked-in status/time.
- Dashboard counters for `Sudah Hadir` and `Belum Hadir`.
- Participant table/export/spreadsheet now include registration code and attendance.

## Database upgrade
Run only this migration on the existing Supabase project:

`supabase/migrations/002_qr_attendance.sql`

If you need QR credentials for rows created before V2, then run:

`supabase/maintenance/backfill_qr_for_existing.sql`

## Frontend dependencies
After replacing/pulling source:

```bash
npm install
npm run dev
```

New packages:
- `qrcode`
- `html5-qrcode`

## Camera requirement
Browser camera scanning requires HTTPS in production (Vercel is fine) or localhost during development.
