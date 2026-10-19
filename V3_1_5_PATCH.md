# V3.1.5 Patch

Minor admin security/UI patch on top of V3.1.4.

## Changes
- Admin Secret input now has an eye icon to show/hide the entered secret.
- Admin session expires exactly 1 hour after successful secret verification.
- Expired sessions are cleared and redirected back to `/admin`.
- Session expiry is rechecked when the tab regains focus or visibility.
- Manual logout clears both secret and expiry metadata.

## Database
No SQL migration required.
