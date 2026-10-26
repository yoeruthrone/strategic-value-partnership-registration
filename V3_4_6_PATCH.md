# V3.4.6 Patch — Core Label Persistence UI Fix

Fixes Form Builder core label/helper inputs showing default values again after browser refresh even though saved values were already persisted and used by the public form.

Root cause: uncontrolled `defaultValue` inputs mounted before async event config finished loading.

Fix:
- Core label inputs are now controlled by loaded event state.
- Core helper/description textareas use the same controlled state behavior.
- Saved values remain the source of truth after refresh.
- No database migration required.
