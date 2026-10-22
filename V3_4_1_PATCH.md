# V3.4.1 — Guest Inherit Leader Data

Minor behavior fix on top of V3.4.

- Guest still only fills core fields: Nama, No. Telepon, Email.
- Every guest row inherits all custom field values from its leader in admin Data Pendaftaran.
- Existing guest records are backfilled by migration 011.
- New guest records store the leader custom_data at registration time.
- Admin participant RPC also resolves the leader custom_data for guest rows as a safety/source-of-truth fallback.
- Excel/PDF exports therefore show the inherited custom values too.
- QR/check-in remains one QR per leader/group.

Run only:
`supabase/migrations/011_v3_4_1_guest_inherit_leader_data.sql`
