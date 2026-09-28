REV.4 QUICK PATCH
- Replace files in your current repo with the files in this patch using the same paths.
- No Supabase schema migration is required.
- Run supabase/maintenance/wipe_event_data.sql in Supabase SQL Editor only when ready to clear test data.
- The wipe keeps dashboard_access / dashboard secret intact.
