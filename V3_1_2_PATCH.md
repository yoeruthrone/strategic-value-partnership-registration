# V3.1.2 Patch

Additive UI + schema patch. Existing events, registrations, QR tokens, attendance, branding, conditional logic and ordering remain intact.

## Added
- Optional helper/description text for every custom field.
- Optional helper/description text for the three locked core fields: Nama Lengkap, No. Telepon, Email.
- Helper text rendered directly under the field label on the public registration form.
- Mobile containment pass for admin header, tabs, scanner, panels and builder.
- QR scanner preview forced to stay within its mobile container.

## Database
Run only:

`supabase/migrations/005_v3_1_2_field_descriptions.sql`

Do not rerun older migrations and do not wipe data.
