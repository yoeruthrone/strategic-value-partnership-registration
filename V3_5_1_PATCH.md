# V3.5.1 Patch Notes

Consolidated patch from V3.4.8.

### Performance
Heavy base64 branding/reference images are split from blocking metadata RPCs and loaded lazily.

### Admin QR fallback
Data Participants includes the leader QR token with a Copy action. Guests display `Ikut Leader`.

### Field Scope
Each custom field can be configured as:
- Group Shared / ikut leader
- Per Participant / isi masing-masing
- Leader Only

Existing fields default to Group Shared.

For historical guest rows, switching an old field from Group Shared to Per Participant does not fabricate individual values from leader data. Historical guest values remain empty unless that guest actually has individual data.
