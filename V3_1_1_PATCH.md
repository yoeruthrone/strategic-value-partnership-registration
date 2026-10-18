# V3.1.1 UI Fix

No database migration is required.

Changes:
- Light mode event background now uses the same dark image overlay treatment as dark mode (no white wash overlay).
- Custom Fields in Form Builder are now draggable.
- Dropping a field persists its `sort_order` through the existing `v3_admin_upsert_field` RPC.
- Public registration order follows the saved sort order automatically.

Run:
```bash
npm install
npm run dev
```
