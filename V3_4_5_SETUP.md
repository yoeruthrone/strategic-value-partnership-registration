# V3.4.5 Setup

Tambahan: deskripsi/intro form registrasi per event yang editable dan opsional.

1. Jalankan migration:
   `supabase/migrations/014_v3_4_5_registration_intro.sql`
2. Buka Admin > Event > Settings.
3. Isi `Deskripsi / Intro Form (Opsional)` bila diperlukan.
4. Simpan Settings.
5. Buka public registration dan pastikan intro tampil setelah hero, sebelum field pertama.

Jika intro dikosongkan, section tidak dirender.
