-- Event Registration V1
-- Jalankan di Supabase SQL Editor.
-- Setelah selesai, jalankan bagian SET DASHBOARD SECRET di paling bawah dengan secret milik Anda.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  phone text not null,
  partner_name text not null,
  attendance_type text not null check (attendance_type in ('SELF','TEAM')),
  member_count integer not null default 0 check (member_count between 0 and 10)
);

create table if not exists public.participants (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.registrations(id) on delete cascade,
  created_at timestamptz not null,
  full_name text not null,
  phone text,
  partner_name text not null,
  position text not null,
  participant_type text not null check (participant_type in ('PRIMARY','MEMBER')),
  primary_name text
);

create index if not exists idx_participants_created_at on public.participants(created_at desc);
create index if not exists idx_participants_partner on public.participants(partner_name);
create index if not exists idx_participants_name_partner on public.participants(full_name, partner_name);
create index if not exists idx_registrations_phone on public.registrations(phone);

-- Private table: tidak dibaca langsung oleh frontend.
create table if not exists public.dashboard_access (
  id integer primary key default 1 check (id = 1),
  secret_hash text not null
);

-- Hanya sinyal tanpa data pribadi. Dipakai untuk trigger auto-refresh dashboard.
create table if not exists public.dashboard_signal (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now()
);

alter table public.registrations enable row level security;
alter table public.participants enable row level security;
alter table public.dashboard_access enable row level security;
alter table public.dashboard_signal enable row level security;

-- Hanya dashboard_signal yang aman dibaca anon karena tidak mengandung PII.
drop policy if exists "anon read dashboard signal" on public.dashboard_signal;
create policy "anon read dashboard signal" on public.dashboard_signal for select to anon using (true);

grant select on public.dashboard_signal to anon;

-- Pastikan signal table masuk publication realtime.
do $$ begin
  alter publication supabase_realtime add table public.dashboard_signal;
exception when duplicate_object then null;
end $$;

create or replace function public.normalize_event_text(p_value text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(upper(regexp_replace(coalesce(p_value,''), '[^[:alnum:] ]', '', 'g')), '\s+', ' ', 'g'));
$$;

create or replace function public.normalize_event_phone(p_value text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_value,''), '[^0-9]', '', 'g');
$$;

create or replace function public.verify_dashboard_secret(p_secret text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.dashboard_access
    where id = 1 and secret_hash = extensions.crypt(coalesce(p_secret,''), secret_hash)
  );
$$;

revoke all on function public.verify_dashboard_secret(text) from public;

create or replace function public.check_registration_duplicates(
  p_partner text,
  p_primary_name text,
  p_phone text,
  p_members jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner text := public.normalize_event_text(p_partner);
  v_primary_name text := public.normalize_event_text(p_primary_name);
  v_phone text := public.normalize_event_phone(p_phone);
  v_names jsonb := '[]'::jsonb;
  v_member jsonb;
  v_member_name text;
  v_phone_match boolean := false;
begin
  if exists(select 1 from public.participants where full_name = v_primary_name and partner_name = v_partner) then
    v_names := v_names || jsonb_build_array(v_primary_name);
  end if;

  for v_member in select value from jsonb_array_elements(coalesce(p_members,'[]'::jsonb)) loop
    v_member_name := public.normalize_event_text(v_member->>'full_name');
    if v_member_name <> '' and exists(select 1 from public.participants where full_name = v_member_name and partner_name = v_partner) then
      if not (v_names ? v_member_name) then
        v_names := v_names || jsonb_build_array(v_member_name);
      end if;
    end if;
  end loop;

  select exists(select 1 from public.registrations where phone = v_phone) into v_phone_match;

  return jsonb_build_object(
    'has_duplicate', (jsonb_array_length(v_names) > 0 or v_phone_match),
    'name_partner_matches', v_names,
    'phone_match', v_phone_match
  );
end;
$$;

grant execute on function public.check_registration_duplicates(text,text,text,jsonb) to anon;

create or replace function public.submit_registration(
  p_primary jsonb,
  p_members jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_created_at timestamptz := now();
  v_registration_id uuid;
  v_primary_name text := public.normalize_event_text(p_primary->>'full_name');
  v_phone text := public.normalize_event_phone(p_primary->>'phone');
  v_partner text := public.normalize_event_text(p_primary->>'partner_name');
  v_position text := public.normalize_event_text(p_primary->>'position');
  v_attendance text := upper(coalesce(p_primary->>'attendance_type','SELF'));
  v_member_count integer := jsonb_array_length(coalesce(p_members,'[]'::jsonb));
  v_member jsonb;
  v_member_name text;
  v_member_position text;
  v_current_count integer;
begin
  if v_primary_name = '' or v_phone = '' or v_partner = '' or v_position = '' then
    raise exception 'Semua field utama wajib diisi.';
  end if;
  if length(v_phone) < 8 then raise exception 'Nomor telepon belum valid.'; end if;
  if v_attendance not in ('SELF','TEAM') then raise exception 'Tipe kehadiran tidak valid.'; end if;
  if v_member_count > 10 then raise exception 'Maksimal 10 anggota tambahan.'; end if;
  if v_attendance = 'SELF' and v_member_count <> 0 then raise exception 'Hadir sendiri tidak boleh memiliki anggota.'; end if;
  if v_attendance = 'TEAM' and v_member_count < 1 then raise exception 'Tambahkan minimal 1 anggota tim.'; end if;

  select count(*) into v_current_count from public.participants;
  if v_current_count + 1 + v_member_count > 200 then
    raise exception 'Kapasitas maksimal 200 peserta telah tercapai.';
  end if;

  insert into public.registrations(created_at,phone,partner_name,attendance_type,member_count)
  values(v_created_at,v_phone,v_partner,v_attendance,v_member_count)
  returning id into v_registration_id;

  insert into public.participants(registration_id,created_at,full_name,phone,partner_name,position,participant_type,primary_name)
  values(v_registration_id,v_created_at,v_primary_name,v_phone,v_partner,v_position,'PRIMARY',null);

  for v_member in select value from jsonb_array_elements(coalesce(p_members,'[]'::jsonb)) loop
    v_member_name := public.normalize_event_text(v_member->>'full_name');
    v_member_position := public.normalize_event_text(v_member->>'position');
    if v_member_name = '' or v_member_position = '' then raise exception 'Nama dan jabatan anggota wajib diisi.'; end if;
    insert into public.participants(registration_id,created_at,full_name,phone,partner_name,position,participant_type,primary_name)
    values(v_registration_id,v_created_at,v_member_name,null,v_partner,v_member_position,'MEMBER',v_primary_name);
  end loop;

  insert into public.dashboard_signal default values;

  return jsonb_build_object('registration_id',v_registration_id,'participant_count',1+v_member_count,'created_at',v_created_at);
end;
$$;

grant execute on function public.submit_registration(jsonb,jsonb) to anon;

create or replace function public.dashboard_snapshot(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.verify_dashboard_secret(p_secret) then raise exception 'Dashboard secret tidak valid.'; end if;
  select jsonb_build_object(
    'total_participants', (select count(*) from public.participants),
    'total_partners', (select count(distinct partner_name) from public.participants),
    'participants', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from public.participants p), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

grant execute on function public.dashboard_snapshot(text) to anon;

create or replace function public.participants_report(p_secret text)
returns setof public.participants
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.verify_dashboard_secret(p_secret) then raise exception 'Dashboard secret tidak valid.'; end if;
  return query select * from public.participants order by created_at desc, participant_type desc;
end;
$$;

grant execute on function public.participants_report(text) to anon;

create or replace function public.partners_report(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.verify_dashboard_secret(p_secret) then raise exception 'Dashboard secret tidak valid.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'partner_name', x.partner_name,
    'participant_count', x.participant_count,
    'participants', x.participants
  ) order by x.participant_count desc, x.partner_name asc), '[]'::jsonb)
  into v_result
  from (
    select partner_name,
           count(*)::int participant_count,
           jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'position',position,'participant_type',participant_type) order by full_name) participants
    from public.participants
    group by partner_name
  ) x;
  return v_result;
end;
$$;

grant execute on function public.partners_report(text) to anon;

-- Tidak beri grant SELECT/INSERT langsung ke registrations/participants/dashboard_access.
-- Semua akses lewat function SECURITY DEFINER di atas.
revoke all on public.registrations from anon, authenticated;
revoke all on public.participants from anon, authenticated;
revoke all on public.dashboard_access from anon, authenticated;

-- =============================================================
-- SET DASHBOARD SECRET (WAJIB)
-- GANTI string contoh di bawah dengan secret acak panjang milik Anda.
-- Jangan commit secret asli ke repository.
-- Jalankan statement ini SECARA TERPISAH setelah migration:
--
-- insert into public.dashboard_access(id, secret_hash)
-- values (1, extensions.crypt('GANTI-DENGAN-SECRET-PANJANG-ANDA', extensions.gen_salt('bf')))
-- on conflict (id) do update set secret_hash = excluded.secret_hash;
--
-- Dashboard URL nanti: https://domainanda.com/internal/GANTI-DENGAN-SECRET-PANJANG-ANDA
-- =============================================================
