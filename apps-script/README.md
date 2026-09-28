# Google Spreadsheet Live Sync

Integrasi ini mempertahankan **1 Google Spreadsheet / 1 link tetap**. Supabase tetap source of truth. Setiap registrasi sukses menulis `dashboard_signal`; Supabase Database Webhook memanggil Apps Script; Apps Script lalu mengambil snapshot terbaru dari Supabase dan memperbarui spreadsheet yang sama.

## 1. Buat spreadsheet

Buat satu Google Spreadsheet, misalnya:

`Strategic Value Partnership - Registration Report`

Buka **Extensions > Apps Script**. Salin isi `Code.gs` ke editor Apps Script. Jika ingin, manifest `appsscript.json` juga dapat disalin lewat Project Settings > Show `appsscript.json` manifest file.

## 2. Script Properties

Di Apps Script buka **Project Settings > Script Properties** dan buat:

- `SUPABASE_URL` = Project URL Supabase, contoh `https://xxxxx.supabase.co`
- `SUPABASE_ANON_KEY` = anon/public key Supabase
- `DASHBOARD_SECRET` = secret dashboard yang sama dengan aplikasi
- `SYNC_TOKEN` = random token baru khusus webhook (disarankan 32+ karakter)
- `EVENT_NAME` = `Strategic Value Partnership`

`SPREADSHEET_ID` tidak perlu diisi manual. Nilai ini dibuat saat menjalankan `setupSpreadsheet()`.

## 3. Initial setup

Dari Apps Script editor jalankan fungsi:

`setupSpreadsheet`

Pada eksekusi pertama Google akan meminta permission. Setelah sukses, spreadsheet akan memiliki tiga tab:

- Dashboard
- Total Peserta
- Total Mitra

`setupSpreadsheet()` juga langsung melakukan full sync pertama.

## 4. Deploy sebagai Web App

Di Apps Script:

**Deploy > New deployment > Web app**

Gunakan:

- Execute as: **Me**
- Who has access: **Anyone**

Deploy, lalu simpan Web App URL. Contoh:

`https://script.google.com/macros/s/XXXXXXXX/exec`

Endpoint tidak membocorkan data. `POST` hanya menjalankan sync jika `SYNC_TOKEN` cocok.

## 5. Buat Supabase Database Webhook

Di Supabase Dashboard buka menu **Database > Webhooks** (atau Integrations/Database Webhooks sesuai tampilan dashboard).

Buat webhook:

- Name: `registration_spreadsheet_sync`
- Table: `dashboard_signal`
- Event: `INSERT`
- Method: `POST`
- URL:

`WEB_APP_URL?token=SYNC_TOKEN`

Contoh:

`https://script.google.com/macros/s/XXXXXXXX/exec?token=TOKEN_RANDOM_ANDA`

Payload webhook boleh default; Apps Script tidak bergantung pada payload karena setiap trigger melakukan full-sync snapshot dari Supabase.

## 6. Hubungkan link spreadsheet ke frontend

Di `.env` frontend:

`VITE_SPREADSHEET_URL=https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit`

Restart Vite setelah mengubah `.env`:

`npm run dev`

Menu **Export > Spreadsheet** akan membuka spreadsheet live yang sama.

## 7. Test

1. Jalankan `setupSpreadsheet()` dan pastikan ketiga tab terbuat.
2. Daftarkan satu peserta baru lewat `/register`.
3. Tunggu beberapa detik.
4. Pastikan `Total Peserta`, `Total Mitra`, dan `Last Update` berubah otomatis.

Jika webhook gagal, jalankan `syncAllData()` secara manual dari Apps Script. Data tidak hilang karena Supabase tetap source of truth.

## Optional fallback

Jalankan `installFallbackTrigger()` sekali untuk membuat full sync setiap 5 menit sebagai backup webhook. Untuk menghapusnya jalankan `removeFallbackTriggers()`.
