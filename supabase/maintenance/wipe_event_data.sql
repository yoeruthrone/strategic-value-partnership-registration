-- WIPE DATA EVENT ONLY
-- Menghapus seluruh data registrasi/peserta dan signal realtime,
-- tanpa menghapus struktur tabel, function, RLS, atau dashboard secret.
-- Jalankan hanya jika memang ingin mengosongkan data event.

begin;

truncate table
  public.dashboard_signal,
  public.participants,
  public.registrations
restart identity cascade;

commit;

-- Verifikasi setelah wipe:
select
  (select count(*) from public.registrations) as registrations,
  (select count(*) from public.participants) as participants,
  (select count(*) from public.dashboard_signal) as dashboard_signals;
