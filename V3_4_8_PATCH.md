# V3.4.8 Patch

- Core Fields can now be reordered among `full_name`, `phone`, and `email`.
- Core fields remain locked above Custom Fields.
- The selected order is persisted per event.
- Public leader registration and guest forms follow the same core order.
- Internal keys, required behavior, duplicate checks, recovery, exports, and QR logic are unchanged.
- Run `supabase/migrations/015_v3_4_8_core_field_order.sql`.
