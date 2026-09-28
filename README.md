# Event Registration V1

Web registrasi satu-hari untuk maksimum 200 peserta, sesuai scope yang sudah dikunci.

## Fitur yang sudah disiapkan

- Public registration `/register`
- 1 pendaftar utama + maksimal 10 anggota tim
- Normalisasi uppercase, hapus special character, angka tetap dipertahankan
- Normalisasi nomor telepon
- Advisory duplicate warning: nama + asal mitra dan nomor telepon
- Atomic registration lewat Supabase RPC
- Maksimum 200 peserta ditegakkan di database
- Success / welcome screen
- Internal dashboard tanpa login via secret URL
- Counter Total Peserta dan Total Mitra
- Dashboard table flattened: semua anggota langsung muncul sebagai peserta
- Timestamp penuh disimpan di DB, dashboard menampilkan jam WITA
- Default newest first
- Global search, sortable table, 20/50/100 pagination
- Auto refresh via Supabase Realtime signal + fallback polling 15 detik
- Manual Refresh
- Menu Total Peserta dengan relasi UTAMA/ANGGOTA
- Menu Total Mitra dengan participant count dan detail
- Export Excel + PDF
- Live Google Spreadsheet (1 fixed link) via Apps Script + Supabase Database Webhook
- Futuristic dark UI, Poppins, Tailwind 4, mobile-first

## 1. Buat Supabase project

Gunakan Supabase Free. Buka SQL Editor dan jalankan:

`supabase/migrations/001_initial.sql`

Setelah migration selesai, buat dashboard secret dengan menjalankan statement yang ada di bagian paling bawah file SQL. Gunakan string random yang panjang dan jangan commit secret itu ke GitHub.

## 2. Environment

Salin:

```bash
cp .env.example .env
```

Isi:

```env
VITE_SUPABASE_URL=https://PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=...
VITE_EVENT_NAME=Strategic Value Partnership Anda
VITE_EVENT_DATE=2026-10-01
```

`anon key` aman berada di frontend karena tabel peserta tidak diberi akses langsung. Public registration dan internal dashboard menggunakan RPC yang dibatasi di database.

## 3. Jalankan lokal

```bash
npm install
npm run dev
```

## 4. URL

Public registration:

```text
https://domainanda.com/register
```

Internal dashboard:

```text
https://domainanda.com/internal/YOUR_SECRET
```

Submenu otomatis:

```text
/internal/YOUR_SECRET/participants
/internal/YOUR_SECRET/partners
```

## 5. QR umum

QR cukup mengarah ke URL `/register`. QR tidak perlu disimpan di database dan tidak ada QR individual.

## Catatan security

Dashboard memang tidak memakai login sesuai requirement, tetapi data peserta tidak dibuka melalui public SELECT. Dashboard memakai secret URL yang divalidasi server-side lewat RPC. Tetap perlakukan URL tersebut sebagai rahasia internal.

## Google Spreadsheet live sync

Integrasi sudah disiapkan di folder `apps-script/`. Polanya adalah 1 spreadsheet dengan link tetap. Supabase tetap menjadi source of truth dan Database Webhook memicu Apps Script setiap ada registrasi baru.

Ikuti panduan lengkap:

`apps-script/README.md`

Setelah spreadsheet dibuat, isi `VITE_SPREADSHEET_URL` di `.env` dengan link Google Sheet tersebut. Menu **Export > Spreadsheet** akan membuka link live yang sama.
