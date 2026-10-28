# SENA Registration Platform V3.5.1 — Consolidated Upgrade

Baseline: V3.4.8

Includes:
- V3.4.9 performance payload split / lazy image assets
- V3.5.0 QR Token column + Copy button in Admin Participants
- V3.5.1 custom Field Scope

## Field Scope
- `GROUP_SHARED` (default): guest follows leader value.
- `PER_PARTICIPANT`: leader and each guest fill their own value.
- `LEADER_ONLY`: only leader data is shown/stored for that field; guest row is empty.

Existing fields automatically remain `GROUP_SHARED` to preserve current behavior.

## Database migrations
Run in order after deploying a compatible V3.5.1 frontend:
1. `supabase/migrations/016_v3_4_9_performance_payload_split.sql`
2. `supabase/migrations/017_v3_5_1_field_scope.sql`

Both are additive / function replacement migrations. 017 adds only `event_fields.data_scope` with default `GROUP_SHARED`.

## Recommended QA
1. Existing event opens normally before changing any scope.
2. GROUP_SHARED field: guest does not see input; dashboard guest shows leader value.
3. PER_PARTICIPANT field: every guest gets its own input and dashboard shows each value.
4. LEADER_ONLY field: leader fills it; guest row shows blank.
5. Test required/optional PER_PARTICIPANT field.
6. Test conditional PER_PARTICIPANT field.
7. Register leader + 2 guests, scan one leader QR, verify group check-in remains unchanged.
8. Data Participants displays leader QR token and Copy button.
9. Network: `v3_public_event_config` / admin metadata RPCs should be much smaller; image assets load separately.
