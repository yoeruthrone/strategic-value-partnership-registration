# V3.4 Setup — Conditional Choice + Field Archive

Run only this new additive migration after V3.3:

```sql
supabase/migrations/010_v3_4_conditional_archive.sql
```

## What changes
- New **Conditional Choice** custom field with exactly 2 custom options.
- Each option can reveal one target field.
- Existing Ya/Tidak fields remain compatible.
- No nested conditional logic and no AND/OR engine.
- Hidden target fields are ignored by required validation and hidden values are removed from new submissions.
- Deleting a custom field now **archives** it instead of deleting the field definition.
- Archived fields are excluded from new public forms and new registration validation.
- Historical `custom_data` remains untouched.
- Form Builder has **Field Diarsipkan** + Restore.
- Participants dashboard can toggle **Tampilkan Field Arsip** to read/export old values.

## QA
1. Create `Asal Peserta` as Conditional Choice with `Sekolah` and `Komunitas`.
2. Create `Nama Sekolah`, set conditional to `Asal Peserta = Sekolah`.
3. Create `Nama Komunitas`, set conditional to `Asal Peserta = Komunitas`.
4. Verify only the correct target is visible and the hidden target is not required/saved.
5. Archive a field with historical data.
6. Verify it disappears from the public form without affecting old registrations.
7. Enable `Tampilkan Field Arsip` in Data Pendaftaran and verify historical values remain visible/exportable.
8. Restore the field and verify it returns as an active field.
