# V3.4.1 Setup

Base: V3.4.

## Database
Run only the new additive migration:

`supabase/migrations/011_v3_4_1_guest_inherit_leader_data.sql`

No wipe is required.

The migration immediately backfills current GUEST rows from their LEADER custom_data and updates registration/admin RPC behavior for future registrations.

## Expected behavior
Leader custom fields are group-level information. Guest rows use their own core identity (name, phone, email), while custom field columns display the same values as the leader.
