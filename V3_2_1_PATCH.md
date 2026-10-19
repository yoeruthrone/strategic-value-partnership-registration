# V3.2.1 Minor Public Form Polish

Changes:
- Registration page removes the top SENA brand mark; theme toggle remains.
- Registration page adds a simple SENA footer with `Develop by Senapro` linking to https://senapro.id.
- Adds `Date / Calendar` custom field type for dates such as date of birth.
- Event logo no longer falls back to the SENA logo when empty. Empty means no logo is shown.
- Banner/background behavior remains unchanged.

Database upgrade for an existing V3.2 database:

```sql
supabase/migrations/008_v3_2_1_date_field.sql
```

This migration is additive and does not wipe existing event or registration data.
