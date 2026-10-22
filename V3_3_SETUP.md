# SENA Registration Platform V3.3 — Leader + Guests

V3.3 adds group registration while keeping a single QR on the leader.

## Behavior
- One leader registration can add 0–10 guests.
- Guests fill core data only: Nama Lengkap, No. Telepon, Email.
- Guests do not receive a QR.
- The leader QR checks in the leader and all guests in the group at once.
- Guests appear as individual participant rows in the admin dashboard and exports.
- Admin rows show `Tipe` (LEADER/GUEST) and the guest's `Leader`.
- Capacity counts actual people, not QR codes.
- Phone/email uniqueness remains per event across leaders and guests.
- QR recovery works only for leaders because guests intentionally have no QR.
- External Viewer continues to use the existing privacy-limited columns; guests are included as participant rows with masked phone numbers.

## Database upgrade
For an existing V3.2.1 database, run only:

```sql
supabase/migrations/009_v3_3_group_registration.sql
```

This migration is additive and preserves existing registrations, QR tokens and attendance data. Existing registrations are treated as LEADER rows.

## QA checklist
1. Register leader only → one participant, one QR.
2. Register leader + 2 guests → 3 dashboard rows, one QR.
3. Verify guest rows show `GUEST` + leader name.
4. Scan leader QR → leader + both guests become HADIR.
5. Try >10 guests → blocked.
6. Try duplicate phone/email inside group → blocked.
7. Try duplicate phone/email already registered in event → blocked.
8. Verify capacity counts leader + guests.
9. Excel/PDF admin export contains Tipe + Leader.
10. External Viewer still exposes only privacy-safe fields.
