# V3.4.4 Patch — Editable Active Field Labels

## What changed
- Active custom fields can now be renamed from Form Builder.
- Rename changes only the display label.
- `field_key` remains immutable from the UI, so existing participant `custom_data`, conditional rules, dashboard columns and exports remain connected.
- Blank labels are rejected client-side.
- No database migration is required for this patch.

## Upgrade
Apply the changed frontend files on top of V3.4.3 and restart the dev server / redeploy.
