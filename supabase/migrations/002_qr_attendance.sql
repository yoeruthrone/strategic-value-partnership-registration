-- V2 QR Attendance upgrade
-- Run AFTER 001_initial.sql. Additive migration; existing registration data remains valid.

alter table public.participants
  add column if not exists registration_code text,
  add column if not exists qr_token text,
  add column if not exists attendance_status text not null default 'REGISTERED',
  add column if not exists checked_in_at timestamptz;

do $$ begin
  alter table public.participants
    add constraint participants_attendance_status_check
    check (attendance_status in ('REGISTERED','ATTENDED'));
exception when duplicate_object then null;
end $$;

create unique index if not exists idx_participants_registration_code_unique
  on public.participants(registration_code)
  where registration_code is not null;

create unique index if not exists idx_participants_qr_token_unique
  on public.participants(qr_token)
  where qr_token is not null;

create index if not exists idx_participants_attendance_status
  on public.participants(attendance_status);

create or replace function public.generate_registration_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := 'SVP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.participants where registration_code = v_code);
  end loop;
  return v_code;
end;
$$;

-- Replace submit_registration so every NEW registration receives QR credentials.
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
  v_participant_id uuid;
  v_primary_name text := public.normalize_event_text(p_primary->>'full_name');
  v_phone text := public.normalize_event_phone(p_primary->>'phone');
  v_partner text := public.normalize_event_text(p_primary->>'partner_name');
  v_position text := public.normalize_event_text(p_primary->>'position');
  v_current_count integer;
  v_registration_code text := public.generate_registration_code();
  v_qr_token text := replace(gen_random_uuid()::text, '-', '');
begin
  if v_primary_name = '' or v_phone = '' or v_partner = '' or v_position = '' then
    raise exception 'Semua field wajib diisi.';
  end if;
  if length(v_phone) < 8 then raise exception 'Nomor telepon belum valid.'; end if;

  select count(*) into v_current_count from public.participants;
  if v_current_count + 1 > 200 then
    raise exception 'Kapasitas maksimal 200 peserta telah tercapai.';
  end if;

  insert into public.registrations(created_at, phone, partner_name, attendance_type, member_count)
  values(v_created_at, v_phone, v_partner, 'SELF', 0)
  returning id into v_registration_id;

  insert into public.participants(
    registration_id, created_at, full_name, phone, partner_name, position,
    participant_type, primary_name, registration_code, qr_token, attendance_status
  ) values (
    v_registration_id, v_created_at, v_primary_name, v_phone, v_partner, v_position,
    'PRIMARY', null, v_registration_code, v_qr_token, 'REGISTERED'
  ) returning id into v_participant_id;

  insert into public.dashboard_signal default values;

  return jsonb_build_object(
    'registration_id', v_registration_id,
    'participant_id', v_participant_id,
    'participant_count', 1,
    'created_at', v_created_at,
    'registration_code', v_registration_code,
    'qr_token', v_qr_token,
    'full_name', v_primary_name,
    'phone', v_phone,
    'partner_name', v_partner,
    'position', v_position
  );
end;
$$;

grant execute on function public.submit_registration(jsonb,jsonb) to anon;

-- Public ticket lookup by possession of the QR token.
create or replace function public.ticket_by_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_row public.participants%rowtype;
begin
  select * into v_row from public.participants where qr_token = coalesce(p_token,'') limit 1;
  if v_row.id is null then return null; end if;
  return jsonb_build_object(
    'id', v_row.id,
    'full_name', v_row.full_name,
    'partner_name', v_row.partner_name,
    'position', v_row.position,
    'registration_code', v_row.registration_code,
    'qr_token', v_row.qr_token,
    'attendance_status', v_row.attendance_status,
    'checked_in_at', v_row.checked_in_at
  );
end;
$$;

grant execute on function public.ticket_by_token(text) to anon;

-- Ticket recovery: requires normalized phone + registration code.
create or replace function public.recover_ticket(p_phone text, p_registration_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_phone text := public.normalize_event_phone(p_phone);
  v_code text := upper(trim(coalesce(p_registration_code,'')));
  v_row public.participants%rowtype;
begin
  select * into v_row
  from public.participants
  where phone = v_phone and registration_code = v_code
  limit 1;

  if v_row.id is null then return null; end if;

  return jsonb_build_object(
    'id', v_row.id,
    'full_name', v_row.full_name,
    'partner_name', v_row.partner_name,
    'position', v_row.position,
    'registration_code', v_row.registration_code,
    'qr_token', v_row.qr_token,
    'attendance_status', v_row.attendance_status,
    'checked_in_at', v_row.checked_in_at
  );
end;
$$;

grant execute on function public.recover_ticket(text,text) to anon;

-- Dashboard-only QR lookup.
create or replace function public.lookup_attendance_qr(p_secret text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_row public.participants%rowtype;
begin
  if not public.verify_dashboard_secret(p_secret) then raise exception 'Dashboard secret tidak valid.'; end if;
  select * into v_row from public.participants where qr_token = coalesce(p_token,'') limit 1;
  if v_row.id is null then return null; end if;
  return jsonb_build_object(
    'id', v_row.id,
    'full_name', v_row.full_name,
    'phone', v_row.phone,
    'partner_name', v_row.partner_name,
    'position', v_row.position,
    'registration_code', v_row.registration_code,
    'attendance_status', v_row.attendance_status,
    'checked_in_at', v_row.checked_in_at
  );
end;
$$;

grant execute on function public.lookup_attendance_qr(text,text) to anon;

create or replace function public.confirm_attendance(p_secret text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.participants%rowtype;
  v_now timestamptz := now();
begin
  if not public.verify_dashboard_secret(p_secret) then raise exception 'Dashboard secret tidak valid.'; end if;

  select * into v_row from public.participants where qr_token = coalesce(p_token,'') for update;
  if v_row.id is null then raise exception 'QR tidak valid.'; end if;

  if v_row.attendance_status = 'ATTENDED' then
    return jsonb_build_object(
      'already_attended', true,
      'full_name', v_row.full_name,
      'partner_name', v_row.partner_name,
      'position', v_row.position,
      'checked_in_at', v_row.checked_in_at
    );
  end if;

  update public.participants
  set attendance_status = 'ATTENDED', checked_in_at = v_now
  where id = v_row.id;

  insert into public.dashboard_signal default values;

  return jsonb_build_object(
    'already_attended', false,
    'full_name', v_row.full_name,
    'partner_name', v_row.partner_name,
    'position', v_row.position,
    'checked_in_at', v_now
  );
end;
$$;

grant execute on function public.confirm_attendance(text,text) to anon;

-- Dashboard snapshot now includes attendance counters.
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
    'total_attended', (select count(*) from public.participants where attendance_status = 'ATTENDED'),
    'total_not_attended', (select count(*) from public.participants where attendance_status <> 'ATTENDED'),
    'participants', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from public.participants p), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

grant execute on function public.dashboard_snapshot(text) to anon;

-- Existing rows from before V2 intentionally keep NULL QR fields.
-- If needed, use maintenance/backfill_qr_for_existing.sql to issue QR credentials.
