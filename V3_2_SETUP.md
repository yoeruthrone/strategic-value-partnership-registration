# SENA Registration Platform V3.2

Upgrade additive dari V3.1.6. Jangan wipe database.

## 1. Database
Jalankan hanya:

`supabase/migrations/007_v3_2_theme_file_upload.sql`

Migration ini menambahkan:
- per-event theme colors + default dark/light
- custom field `file`
- reference image per custom field
- private Supabase Storage bucket `registration-files`
- hard limit Storage 1 MB untuk file peserta
- validation file pada registration RPC
- theme metadata untuk public/recovery/ticket/external viewer

## 2. Environment Vercel tambahan
Tambahkan **server-only** environment variable:

`SUPABASE_SERVICE_ROLE_KEY=<service role key project Supabase>`

Jangan pernah gunakan prefix `VITE_` pada service role key. Key ini hanya dipakai oleh `/api/admin-file-url` untuk membuat signed URL file private setelah admin secret diverifikasi.

Environment existing tetap:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Setelah menambah env, Redeploy Vercel.

## 3. File upload rules
- 1 file per custom file field
- JPG/JPEG, PNG, WEBP dan/atau PDF sesuai rule field
- storage hard limit: 1 MB
- image >1 MB dikompres otomatis di browser sampai <=1 MB jika memungkinkan
- PDF >1 MB langsung ditolak
- bucket private; anon hanya mendapat INSERT, tidak SELECT/UPDATE/DELETE
- admin membuka file melalui signed URL 90 detik via Vercel server function
- external viewer tidak menerima file path/custom data

## 4. Theme behavior
Admin global tetap warna SENA.
Theme event hanya berlaku pada:
- Registration
- Recovery
- Ticket
- External Viewer

Admin memilih Primary, Accent, Secondary dan Default Theme (Dark/Light). Pengunjung masih bisa toggle dan pilihan disimpan per event.

## 5. QA minimum
1. Existing event/registration/QR tetap ada setelah migration.
2. Ganti theme event, cek registration + recovery + viewer dark/light.
3. Buat custom file field: Image only, PDF only, Image + PDF.
4. Upload gambar >1 MB dan pastikan otomatis diperkecil <=1 MB.
5. PDF >1 MB harus ditolak.
6. Conditional file field harus hilang/clear saat trigger bukan YA.
7. Admin Participants dapat membuka file setelah `SUPABASE_SERVICE_ROLE_KEY` ada di Vercel.
8. External Viewer tidak menampilkan file/custom field.


## V3.2.1 follow-up
If your database is already on V3.2, run `supabase/migrations/008_v3_2_1_date_field.sql` to enable the Date / Calendar custom field type. No data wipe is required.
