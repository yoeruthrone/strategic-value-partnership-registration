# V3.4 Patch

## Added
- Conditional Choice field with exactly 2 custom options.
- One target field per option.
- Existing Ya/Tidak conditionals remain compatible.
- Safe field archive instead of destructive delete.
- Restore archived fields from Form Builder.
- Optional archived columns in Data Pendaftaran.
- Historical archived values can be exported to Excel/PDF when shown.

## Migration
Run only:

`supabase/migrations/010_v3_4_conditional_archive.sql`

This migration is additive and preserves registrations, QR, attendance, leader/guest links, uploaded files, and existing custom_data.
