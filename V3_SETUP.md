# V3 Setup / Upgrade

## 1. Backup (recommended)
Export anything you still need from V2 before continuing.

## 2. Wipe old event data
Run:
`supabase/maintenance/000_wipe_v2_data.sql`

## 3. Apply V3 schema
Run:
`supabase/migrations/003_v3_multi_event.sql`

This intentionally rebuilds event-related tables because V3 is a multi-event architecture. `dashboard_access` is preserved.

## 4. Admin secret
If your old dashboard secret already works, no action is required.
To rotate/set it, edit and run:
`supabase/maintenance/001_set_admin_secret.sql`

## 5. Frontend env
Create `.env`:
```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
```

## 6. Run
```
npm install
npm run dev
```

## 7. First login
Open `/admin`, enter the same admin secret stored in `dashboard_access`.
Migration seeds `Strategic Value Partnership` as the first event.

## 8. Recommended QA
- Admin login
- Create second event
- Add custom fields
- Register public participant
- Duplicate same phone -> rejected
- Duplicate same email -> rejected
- Recover QR by phone
- Recover QR by email
- PNG/PDF QR download
- QR scan + attendance confirm
- Re-scan already attended
- External viewer counters
- External Excel/PDF export
- Dark/light mode
- Mobile registration + scanner
