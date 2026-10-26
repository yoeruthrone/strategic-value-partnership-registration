# V3.4.2 Setup

Run only:

`supabase/migrations/012_v3_4_2_guest_settings.sql`

This migration is additive and preserves all existing event/participant data.

New per-event settings:
- Maximum additional participants: 2-10 (default 10)
- Additional participant section name: free text (default `Peserta Tambahan`)

Existing events automatically keep the previous behavior until edited.
