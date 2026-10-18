-- SENA Registration Platform V3.1
-- Additive upgrade: simple YES/NO conditional logic, per-event branding assets,
-- safer external viewer payload. Preserves existing events and registrations.

alter table public.events
  add column if not exists logo_data_url text,
  add column if not exists banner_data_url text,
  add column if not exists background_data_url text;

alter table public.event_fields
  add column if not exists show_if_field_key text;

alter table public.event_fields drop constraint if exists event_fields_field_type_check;
alter table public.event_fields
  add constraint event_fields_field_type_check
  check (field_type in ('text','number','dropdown','radio','checkbox','textarea','yes_no'));

-- One YES/NO trigger can reveal at most one target field, per the intentionally simple V3.1 logic.
create unique index if not exists idx_event_fields_one_target_per_trigger
  on public.event_fields(event_id,show_if_field_key)
  where show_if_field_key is not null;

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
  external_view_enabled=coalesce((p_patch->>'external_view_enabled')::boolean,external_view_enabled),
  logo_data_url=case when p_patch ? 'logo_data_url' then nullif(p_patch->>'logo_data_url','') else logo_data_url end,
  banner_data_url=case when p_patch ? 'banner_data_url' then nullif(p_patch->>'banner_data_url','') else banner_data_url end,
  background_data_url=case when p_patch ? 'background_data_url' then nullif(p_patch->>'background_data_url','') else background_data_url end
 where id=p_event_id returning * into e;
 return to_jsonb(e);
end $$;
grant execute on function public.v3_admin_event_update(text,uuid,jsonb) to anon;

create or replace function public.v3_admin_upsert_field(p_secret text,p_event_id uuid,p_field jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare f public.event_fields%rowtype; v_show text:=nullif(trim(coalesce(p_field->>'show_if_field_key','')),''); v_type text:=p_field->>'field_type';
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 if v_show is not null then
   if lower(trim(p_field->>'field_key'))=v_show then raise exception 'Field tidak dapat bergantung pada dirinya sendiri.'; end if;
   if not exists(select 1 from public.event_fields where event_id=p_event_id and field_key=v_show and field_type='yes_no') then
     raise exception 'Conditional logic harus menggunakan field Ya / Tidak.';
   end if;
 end if;
 insert into public.event_fields(event_id,label,field_key,field_type,required,options,sort_order,show_if_field_key)
 values(
   p_event_id,
   trim(p_field->>'label'),
   lower(trim(p_field->>'field_key')),
   v_type,
   coalesce((p_field->>'required')::boolean,false),
   case when v_type='yes_no' then '["YA","TIDAK"]'::jsonb else coalesce(p_field->'options','[]'::jsonb) end,
   coalesce((p_field->>'sort_order')::int,10),
   case when v_type='yes_no' then null else v_show end
 )
 on conflict(event_id,field_key) do update set
   label=excluded.label,
   field_type=excluded.field_type,
   required=excluded.required,
   options=excluded.options,
   sort_order=excluded.sort_order,
   show_if_field_key=excluded.show_if_field_key
 returning * into f;
 return to_jsonb(f);
exception when unique_violation then
 raise exception 'Satu field Ya / Tidak hanya boleh menampilkan satu field target.';
end $$;
grant execute on function public.v3_admin_upsert_field(text,uuid,jsonb) to anon;

create or replace function public.v3_admin_delete_field(p_secret text,p_event_id uuid,p_field_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_key text;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 select field_key into v_key from public.event_fields where id=p_field_id and event_id=p_event_id;
 if v_key is not null then update public.event_fields set show_if_field_key=null where event_id=p_event_id and show_if_field_key=v_key; end if;
 delete from public.event_fields where id=p_field_id and event_id=p_event_id;
 return true;
end $$;
grant execute on function public.v3_admin_delete_field(text,uuid,uuid) to anon;

create or replace function public.v3_public_event_config(p_slug text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 return jsonb_build_object(
   'event',jsonb_build_object(
      'id',e.id,'name',e.name,'slug',e.slug,'event_date',e.event_date,'registration_open',e.registration_open,
      'logo_data_url',e.logo_data_url,'banner_data_url',e.banner_data_url,'background_data_url',e.background_data_url
   ),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;

create or replace function public.v3_public_register(p_slug text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype; r public.registrations%rowtype; v_phone text:=public.v3_norm_phone(p_payload->>'phone'); v_email text:=public.v3_norm_email(p_payload->>'email'); v_data jsonb:=coalesce(p_payload->'custom_data','{}'::jsonb); f record;
begin
 select * into e from public.events where slug=lower(trim(p_slug)) for update; if e.id is null then raise exception 'Event tidak ditemukan.'; end if; if not e.registration_open then raise exception 'Registrasi sudah ditutup.'; end if;
 if trim(coalesce(p_payload->>'full_name',''))='' or length(v_phone)<8 or position('@' in v_email)=0 then raise exception 'Nama, No. Telepon dan Email wajib valid.'; end if;
 if (select count(*) from public.registrations where event_id=e.id)>=e.capacity then raise exception 'Kapasitas event sudah penuh.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and phone=v_phone) then raise exception 'Nomor telepon sudah terdaftar pada event ini.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and email=v_email) then raise exception 'Email sudah terdaftar pada event ini.'; end if;
 for f in select * from public.event_fields where event_id=e.id and required loop
   -- Hidden conditional fields are not required. Conditional target is active only when trigger = YA.
   if f.show_if_field_key is null or upper(coalesce(v_data->>f.show_if_field_key,''))='YA' then
     if not (v_data ? f.field_key) or trim(coalesce(v_data->>f.field_key,''))='' then raise exception 'Field % wajib diisi.',f.label; end if;
   end if;
 end loop;
 insert into public.registrations(event_id,full_name,phone,email,custom_data) values(e.id,upper(trim(p_payload->>'full_name')),v_phone,v_email,v_data) returning * into r;
 insert into public.dashboard_signal(event_id) values(e.id);
 return jsonb_build_object('id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at);
end $$;
grant execute on function public.v3_public_register(text,jsonb) to anon;

create or replace function public.v3_external_view(p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where external_token=p_token and external_view_enabled=true; if e.id is null then return null; end if;
 return jsonb_build_object(
   'event',jsonb_build_object(
     'name',e.name,'slug',e.slug,'event_date',e.event_date,
     'logo_data_url',e.logo_data_url,'banner_data_url',e.banner_data_url,'background_data_url',e.background_data_url
   ),
   'stats',jsonb_build_object(
     'total',(select count(*) from public.registrations where event_id=e.id),
     'attended',(select count(*) from public.registrations where event_id=e.id and attendance_status='ATTENDED'),
     'not_attended',(select count(*) from public.registrations where event_id=e.id and attendance_status<>'ATTENDED')
   ),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id),'[]'::jsonb),
   -- Do not expose qr_token through viewer.
   'participants',coalesce((select jsonb_agg(jsonb_build_object(
      'id',r.id,'created_at',r.created_at,'full_name',r.full_name,'phone',r.phone,'email',r.email,
      'custom_data',r.custom_data,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at
   ) order by r.created_at desc) from public.registrations r where event_id=e.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_external_view(text) to anon;
