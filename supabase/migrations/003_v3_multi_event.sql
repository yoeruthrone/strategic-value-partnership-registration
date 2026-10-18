-- SENA Registration Platform V3
-- DESTRUCTIVE EVENT-SCHEMA RESET: preserves dashboard_access/admin secret only.
-- Run AFTER reviewing maintenance/000_wipe_v2_data.sql.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- Preserve single admin secret table if it already exists.
create table if not exists public.dashboard_access (
  id integer primary key default 1 check (id=1),
  secret_hash text not null
);
alter table public.dashboard_access enable row level security;

-- Rebuild event data cleanly (user approved wipe/refactor).
drop table if exists public.dashboard_signal cascade;
drop table if exists public.participants cascade;
drop table if exists public.registrations cascade;
drop table if exists public.event_fields cascade;
drop table if exists public.events cascade;

create table public.events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  slug text not null unique,
  event_date date,
  capacity integer not null default 200 check (capacity > 0),
  registration_open boolean not null default true,
  external_view_enabled boolean not null default true,
  external_token text not null unique default replace(gen_random_uuid()::text,'-','')
);

create table public.event_fields (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  label text not null,
  field_key text not null,
  field_type text not null check (field_type in ('text','number','dropdown','radio','checkbox','textarea')),
  required boolean not null default false,
  options jsonb not null default '[]'::jsonb,
  sort_order integer not null default 10,
  created_at timestamptz not null default now(),
  unique(event_id,field_key)
);

create table public.registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  full_name text not null,
  phone text not null,
  email text not null,
  custom_data jsonb not null default '{}'::jsonb,
  qr_token text not null unique default replace(gen_random_uuid()::text,'-',''),
  attendance_status text not null default 'REGISTERED' check (attendance_status in ('REGISTERED','ATTENDED')),
  checked_in_at timestamptz,
  unique(event_id,phone),
  unique(event_id,email)
);

create index idx_reg_event_created on public.registrations(event_id,created_at desc);
create index idx_reg_event_attendance on public.registrations(event_id,attendance_status);
create index idx_fields_event_order on public.event_fields(event_id,sort_order);

create table public.dashboard_signal (
  id bigint generated always as identity primary key,
  event_id uuid references public.events(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.events enable row level security;
alter table public.event_fields enable row level security;
alter table public.registrations enable row level security;
alter table public.dashboard_signal enable row level security;

-- No direct anon reads of PII/config tables; all access through RPCs.
drop policy if exists "anon signal read" on public.dashboard_signal;
create policy "anon signal read" on public.dashboard_signal for select to anon using (true);
grant select on public.dashboard_signal to anon;

do $$ begin
  alter publication supabase_realtime add table public.dashboard_signal;
exception when duplicate_object then null;
end $$;

create or replace function public.v3_norm_phone(v text)
returns text language sql immutable as $$ select regexp_replace(coalesce(v,''),'[^0-9]','','g') $$;

create or replace function public.v3_norm_email(v text)
returns text language sql immutable as $$ select lower(trim(coalesce(v,''))) $$;

create or replace function public.v3_admin_ok(p_secret text)
returns boolean language sql security definer set search_path=public stable as $$
  select exists(select 1 from public.dashboard_access where id=1 and secret_hash=extensions.crypt(coalesce(p_secret,''),secret_hash));
$$;
revoke all on function public.v3_admin_ok(text) from public;

create or replace function public.v3_admin_verify(p_secret text)
returns boolean language sql security definer set search_path=public stable as $$ select public.v3_admin_ok(p_secret) $$;
grant execute on function public.v3_admin_verify(text) to anon;

create or replace function public.v3_admin_events(p_secret text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
   'id',e.id,'name',e.name,'slug',e.slug,'event_date',e.event_date,'capacity',e.capacity,
   'registration_open',e.registration_open,'external_view_enabled',e.external_view_enabled,
   'external_token',e.external_token,'total_participants',(select count(*) from public.registrations r where r.event_id=e.id)
 ) order by e.created_at desc) from public.events e),'[]'::jsonb);
end $$;
grant execute on function public.v3_admin_events(text) to anon;

create or replace function public.v3_admin_create_event(p_secret text,p_event jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 insert into public.events(name,slug,event_date,capacity)
 values(trim(p_event->>'name'),lower(trim(p_event->>'slug')),nullif(p_event->>'event_date','')::date,coalesce((p_event->>'capacity')::int,200)) returning * into e;
 return to_jsonb(e);
end $$;
grant execute on function public.v3_admin_create_event(text,jsonb) to anon;

create or replace function public.v3_admin_event_get(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return (select to_jsonb(e) from public.events e where id=p_event_id);
end $$;
grant execute on function public.v3_admin_event_get(text,uuid) to anon;

create or replace function public.v3_admin_event_update(p_secret text,p_event_id uuid,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 update public.events set
  name=coalesce(nullif(trim(p_patch->>'name'),''),name),
  event_date=case when p_patch ? 'event_date' then nullif(p_patch->>'event_date','')::date else event_date end,
  capacity=coalesce((p_patch->>'capacity')::int,capacity),
  registration_open=coalesce((p_patch->>'registration_open')::boolean,registration_open),
  external_view_enabled=coalesce((p_patch->>'external_view_enabled')::boolean,external_view_enabled)
 where id=p_event_id returning * into e;
 return to_jsonb(e);
end $$;
grant execute on function public.v3_admin_event_update(text,uuid,jsonb) to anon;

create or replace function public.v3_admin_event_snapshot(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 select * into e from public.events where id=p_event_id;
 return jsonb_build_object('event',to_jsonb(e),'stats',jsonb_build_object(
  'total',(select count(*) from public.registrations where event_id=p_event_id),
  'attended',(select count(*) from public.registrations where event_id=p_event_id and attendance_status='ATTENDED'),
  'not_attended',(select count(*) from public.registrations where event_id=p_event_id and attendance_status<>'ATTENDED')
 ),'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=p_event_id),'[]'::jsonb));
end $$;
grant execute on function public.v3_admin_event_snapshot(text,uuid) to anon;

create or replace function public.v3_admin_form_config(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object('event',(select to_jsonb(e) from public.events e where id=p_event_id),'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=p_event_id),'[]'::jsonb));
end $$;
grant execute on function public.v3_admin_form_config(text,uuid) to anon;

create or replace function public.v3_admin_upsert_field(p_secret text,p_event_id uuid,p_field jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare f public.event_fields%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 insert into public.event_fields(event_id,label,field_key,field_type,required,options,sort_order)
 values(p_event_id,trim(p_field->>'label'),lower(trim(p_field->>'field_key')),p_field->>'field_type',coalesce((p_field->>'required')::boolean,false),coalesce(p_field->'options','[]'::jsonb),coalesce((p_field->>'sort_order')::int,10))
 on conflict(event_id,field_key) do update set label=excluded.label,field_type=excluded.field_type,required=excluded.required,options=excluded.options,sort_order=excluded.sort_order
 returning * into f; return to_jsonb(f);
end $$;
grant execute on function public.v3_admin_upsert_field(text,uuid,jsonb) to anon;

create or replace function public.v3_admin_delete_field(p_secret text,p_event_id uuid,p_field_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if; delete from public.event_fields where id=p_field_id and event_id=p_event_id; return true; end $$;
grant execute on function public.v3_admin_delete_field(text,uuid,uuid) to anon;

create or replace function public.v3_admin_participants(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object('event',(select to_jsonb(e) from public.events e where id=p_event_id),'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=p_event_id),'[]'::jsonb),'participants',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc) from public.registrations r where event_id=p_event_id),'[]'::jsonb));
end $$;
grant execute on function public.v3_admin_participants(text,uuid) to anon;

create or replace function public.v3_public_event_config(p_slug text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 return jsonb_build_object('event',jsonb_build_object('id',e.id,'name',e.name,'slug',e.slug,'event_date',e.event_date,'registration_open',e.registration_open),'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id),'[]'::jsonb));
end $$;
grant execute on function public.v3_public_event_config(text) to anon;

create or replace function public.v3_public_register(p_slug text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype; r public.registrations%rowtype; v_phone text:=public.v3_norm_phone(p_payload->>'phone'); v_email text:=public.v3_norm_email(p_payload->>'email'); v_data jsonb:=coalesce(p_payload->'custom_data','{}'::jsonb); f record; v text;
begin
 select * into e from public.events where slug=lower(trim(p_slug)) for update; if e.id is null then raise exception 'Event tidak ditemukan.'; end if; if not e.registration_open then raise exception 'Registrasi sudah ditutup.'; end if;
 if trim(coalesce(p_payload->>'full_name',''))='' or length(v_phone)<8 or position('@' in v_email)=0 then raise exception 'Nama, No. Telepon dan Email wajib valid.'; end if;
 if (select count(*) from public.registrations where event_id=e.id)>=e.capacity then raise exception 'Kapasitas event sudah penuh.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and phone=v_phone) then raise exception 'Nomor telepon sudah terdaftar pada event ini.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and email=v_email) then raise exception 'Email sudah terdaftar pada event ini.'; end if;
 for f in select * from public.event_fields where event_id=e.id and required loop
   if not (v_data ? f.field_key) or trim(coalesce(v_data->>f.field_key,''))='' then raise exception 'Field % wajib diisi.',f.label; end if;
 end loop;
 insert into public.registrations(event_id,full_name,phone,email,custom_data) values(e.id,upper(trim(p_payload->>'full_name')),v_phone,v_email,v_data) returning * into r;
 insert into public.dashboard_signal(event_id) values(e.id);
 return jsonb_build_object('id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at);
end $$;
grant execute on function public.v3_public_register(text,jsonb) to anon;

create or replace function public.v3_public_recover_ticket(p_slug text,p_identifier text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype; r public.registrations%rowtype; v_phone text:=public.v3_norm_phone(p_identifier); v_email text:=public.v3_norm_email(p_identifier);
begin
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 select * into r from public.registrations where event_id=e.id and (phone=v_phone or email=v_email) limit 1; if r.id is null then return null; end if;
 return jsonb_build_object('id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at);
end $$;
grant execute on function public.v3_public_recover_ticket(text,text) to anon;

create or replace function public.v3_public_ticket_by_token(p_slug text,p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype; r public.registrations%rowtype;
begin select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if; select * into r from public.registrations where event_id=e.id and qr_token=p_token; if r.id is null then return null; end if; return jsonb_build_object('event',jsonb_build_object('name',e.name,'slug',e.slug),'ticket',jsonb_build_object('id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at)); end $$;
grant execute on function public.v3_public_ticket_by_token(text,text) to anon;

create or replace function public.v3_admin_lookup_qr(p_secret text,p_event_id uuid,p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare r public.registrations%rowtype; begin if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if; select * into r from public.registrations where event_id=p_event_id and qr_token=p_token; if r.id is null then return null; end if; return to_jsonb(r); end $$;
grant execute on function public.v3_admin_lookup_qr(text,uuid,text) to anon;

create or replace function public.v3_admin_confirm_attendance(p_secret text,p_event_id uuid,p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.registrations%rowtype; begin if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if; select * into r from public.registrations where event_id=p_event_id and qr_token=p_token for update; if r.id is null then raise exception 'QR tidak valid.'; end if; if r.attendance_status<>'ATTENDED' then update public.registrations set attendance_status='ATTENDED',checked_in_at=now() where id=r.id returning * into r; insert into public.dashboard_signal(event_id) values(p_event_id); end if; return to_jsonb(r); end $$;
grant execute on function public.v3_admin_confirm_attendance(text,uuid,text) to anon;

create or replace function public.v3_external_view(p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where external_token=p_token and external_view_enabled=true; if e.id is null then return null; end if;
 return jsonb_build_object('event',jsonb_build_object('name',e.name,'slug',e.slug,'event_date',e.event_date),'stats',jsonb_build_object('total',(select count(*) from public.registrations where event_id=e.id),'attended',(select count(*) from public.registrations where event_id=e.id and attendance_status='ATTENDED'),'not_attended',(select count(*) from public.registrations where event_id=e.id and attendance_status<>'ATTENDED')),'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id),'[]'::jsonb),'participants',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc) from public.registrations r where event_id=e.id),'[]'::jsonb));
end $$;
grant execute on function public.v3_external_view(text) to anon;

-- Seed one event matching the existing project for immediate continuity.
insert into public.events(name,slug,event_date,capacity,registration_open,external_view_enabled)
values('Strategic Value Partnership','strategic-value-partnership',null,200,true,true)
on conflict(slug) do nothing;
