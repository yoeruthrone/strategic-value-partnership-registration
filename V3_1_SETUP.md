# SENA Registration Platform V3.1 — Upgrade Guide

V3.1 is an additive upgrade over V3.0. It preserves existing events, registrations, QR tokens, attendance, and the single admin secret.

## Existing V3 installation
Run only:

`supabase/migrations/004_v3_1_branding_logic_tables.sql`

Do **not** run the wipe script again if current event/test data should be preserved.

Then replace/pull the V3.1 frontend source and run:

```bash
npm install
npm run dev
```

## Fresh installation
1. Run the existing V3 setup/migration sequence.
2. Run `003_v3_multi_event.sql`.
3. Run `004_v3_1_branding_logic_tables.sql`.
4. Configure `.env` with the Supabase URL and anon key.

## V3.1 features
- Simple conditional form logic: one `Ya / Tidak` trigger can reveal one target field when answer = `YA`.
- Per-event logo, banner, and background upload from Event Settings.
- Images are optimized in-browser and stored as event data; no Storage bucket is required.
- Event header/date layout refreshed on public registration, admin overview, and external viewer.
- Human-readable event date.
- Registration table added to admin overview and external viewer.
- Sort button on every table column; initial sort is newest registration first.
- Registration date and registration time are separate columns.
- Manual Refresh button.
- Global table search.
- Pagination/page size: 20, 50, 100, 200.
- External viewer exports still support Excel/PDF.
- External viewer no longer receives QR tokens in its RPC payload.
