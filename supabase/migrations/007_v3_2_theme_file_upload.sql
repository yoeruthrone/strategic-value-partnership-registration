-- SENA Registration Platform V3.2
-- Additive/data-safe: per-event public color theme, custom file upload fields,
-- reference images on custom fields, private registration file storage.
-- Existing events, registrations, QR tokens, attendance and branding are preserved.

alter table public.events
  add column if not exists theme_primary text not null default '#009FEE',
  add column if not exists theme_accent text not null default '#EE00C6',
  add column if not exists theme_secondary text not null default '#4F00EE',
  add column if not exists default_theme text not null default 'dark';

alter table public.events drop constraint if exists events_default_theme_check;
alter table public.events add constraint events_default_theme_check check (default_theme in ('dark','light'));

alter table public.event_fields
  add column if not exists allowed_file_type text not null default 'image_pdf',
  add column if not exists reference_image_data_url text;

alter table public.event_fields drop constraint if exists event_fields_field_type_check;
alter table public.event_fields add constraint event_fields_field_type_check
  check (field_type in ('text','number','dropdown','radio','checkbox','textarea','yes_no','file'));

alter table public.event_fields drop constraint if exists event_fields_allowed_file_type_check;
alter table public.event_fields add constraint event_fields_allowed_file_type_check
  check (allowed_file_type in ('image','pdf','image_pdf'));

-- Private bucket. Upload size is hard-limited by Storage itself to 1 MB.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('registration-files','registration-files',false,1048576,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set
  public=false,
  file_size_limit=1048576,
  allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

-- Helper for Storage insert policy. First folder must be an open event UUID.
create or replace function public.v3_storage_event_open(p_object_name text)
returns boolean
language plpgsql
security definer
set search_path=public
stable
as $$
declare v_event uuid;
begin
  begin
    v_event := split_part(coalesce(p_object_name,''),'/',1)::uuid;
  exception when others then
    return false;
  end;
  return exists(select 1 from public.events where id=v_event and registration_open=true);
end $$;
grant execute on function public.v3_storage_event_open(text) to anon;

drop policy if exists "v3 public registration file insert" on storage.objects;
create policy "v3 public registration file insert"
on storage.objects for insert to anon
with check (
  bucket_id='registration-files'
  and public.v3_storage_event_open(name)
);
-- Intentionally no anon SELECT/UPDATE/DELETE policy. Files remain private.

create or replace function public.v3_admin_event_update(p_secret text,p_event_id uuid,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype; v text;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 foreach v in array array['theme_primary','theme_accent','theme_secondary'] loop
   if p_patch ? v and coalesce(p_patch->>v,'') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Warna % harus format HEX #RRGGBB.',v; end if;
 end loop;
 update public.events set
  name=coalesce(nullif(trim(p_patch->>'name'),''),name),
  event_date=case when p_patch ? 'event_date' then nullif(p_patch->>'event_date','')::date else event_date end,
  capacity=coalesce((p_patch->>'capacity')::int,capacity),
  registration_open=coalesce((p_patch->>'registration_open')::boolean,registration_open),
  external_view_enabled=coalesce((p_patch->>'external_view_enabled')::boolean,external_view_enabled),
  logo_data_url=case when p_patch ? 'logo_data_url' then nullif(p_patch->>'logo_data_url','') else logo_data_url end,
  banner_data_url=case when p_patch ? 'banner_data_url' then nullif(p_patch->>'banner_data_url','') else banner_data_url end,
  background_data_url=case when p_patch ? 'background_data_url' then nullif(p_patch->>'background_data_url','') else background_data_url end,
  name_description=case when p_patch ? 'name_description' then nullif(trim(p_patch->>'name_description'),'') else name_description end,
  phone_description=case when p_patch ? 'phone_description' then nullif(trim(p_patch->>'phone_description'),'') else phone_description end,
  email_description=case when p_patch ? 'email_description' then nullif(trim(p_patch->>'email_description'),'') else email_description end,
  theme_primary=case when p_patch ? 'theme_primary' then upper(p_patch->>'theme_primary') else theme_primary end,
  theme_accent=case when p_patch ? 'theme_accent' then upper(p_patch->>'theme_accent') else theme_accent end,
  theme_secondary=case when p_patch ? 'theme_secondary' then upper(p_patch->>'theme_secondary') else theme_secondary end,
  default_theme=case when p_patch ? 'default_theme' then p_patch->>'default_theme' else default_theme end
 where id=p_event_id returning * into e;
 return to_jsonb(e);
end $$;
grant execute on function public.v3_admin_event_update(text,uuid,jsonb) to anon;

create or replace function public.v3_admin_upsert_field(p_secret text,p_event_id uuid,p_field jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 f public.event_fields%rowtype;
 v_show text:=nullif(trim(coalesce(p_field->>'show_if_field_key','')),'');
 v_type text:=p_field->>'field_type';
 v_allowed text:=coalesce(nullif(p_field->>'allowed_file_type',''),'image_pdf');
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 if v_type not in ('text','number','dropdown','radio','checkbox','textarea','yes_no','file') then raise exception 'Tipe field tidak valid.'; end if;
 if v_allowed not in ('image','pdf','image_pdf') then raise exception 'Rule file tidak valid.'; end if;
 if v_show is not null then
   if lower(trim(p_field->>'field_key'))=v_show then raise exception 'Field tidak dapat bergantung pada dirinya sendiri.'; end if;
   if not exists(select 1 from public.event_fields where event_id=p_event_id and field_key=v_show and field_type='yes_no') then raise exception 'Conditional logic harus menggunakan field Ya / Tidak.'; end if;
 end if;
 insert into public.event_fields(event_id,label,field_key,field_type,required,options,sort_order,show_if_field_key,description,allowed_file_type,reference_image_data_url)
 values(
   p_event_id,trim(p_field->>'label'),lower(trim(p_field->>'field_key')),v_type,
   coalesce((p_field->>'required')::boolean,false),
   case when v_type='yes_no' then '["YA","TIDAK"]'::jsonb else coalesce(p_field->'options','[]'::jsonb) end,
   coalesce((p_field->>'sort_order')::int,10),
   case when v_type='yes_no' then null else v_show end,
   nullif(trim(coalesce(p_field->>'description','')),''),
   v_allowed,
   case when p_field ? 'reference_image_data_url' then nullif(p_field->>'reference_image_data_url','') else null end
 )
 on conflict(event_id,field_key) do update set
   label=excluded.label,field_type=excluded.field_type,required=excluded.required,options=excluded.options,
   sort_order=excluded.sort_order,show_if_field_key=excluded.show_if_field_key,description=excluded.description,
   allowed_file_type=excluded.allowed_file_type,reference_image_data_url=excluded.reference_image_data_url
 returning * into f;
 return to_jsonb(f);
exception when unique_violation then
 raise exception 'Satu field Ya / Tidak hanya boleh menampilkan satu field target.';
end $$;
grant execute on function public.v3_admin_upsert_field(text,uuid,jsonb) to anon;

create or replace function public.v3_public_event_config(p_slug text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 return jsonb_build_object(
   'event',jsonb_build_object(
      'id',e.id,'name',e.name,'slug',e.slug,'event_date',e.event_date,'registration_open',e.registration_open,
      'logo_data_url',e.logo_data_url,'banner_data_url',e.banner_data_url,'background_data_url',e.background_data_url,
      'name_description',e.name_description,'phone_description',e.phone_description,'email_description',e.email_description,
      'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme
   ),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;

create or replace function public.v3_public_register(p_slug text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 e public.events%rowtype; r public.registrations%rowtype;
 v_phone text:=public.v3_norm_phone(p_payload->>'phone'); v_email text:=public.v3_norm_email(p_payload->>'email');
 v_data jsonb:=coalesce(p_payload->'custom_data','{}'::jsonb); f record; v_file jsonb; v_path text; v_type text; v_size bigint;
begin
 select * into e from public.events where slug=lower(trim(p_slug)) for update;
 if e.id is null then raise exception 'Event tidak ditemukan.'; end if;
 if not e.registration_open then raise exception 'Registrasi sudah ditutup.'; end if;
 if trim(coalesce(p_payload->>'full_name',''))='' or length(v_phone)<8 or position('@' in v_email)=0 then raise exception 'Nama, No. Telepon dan Email wajib valid.'; end if;
 if (select count(*) from public.registrations where event_id=e.id)>=e.capacity then raise exception 'Kapasitas event sudah penuh.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and phone=v_phone) then raise exception 'Nomor telepon sudah terdaftar pada event ini.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and email=v_email) then raise exception 'Email sudah terdaftar pada event ini.'; end if;

 for f in select * from public.event_fields where event_id=e.id order by sort_order loop
   -- Ignore validation for hidden conditional targets.
   if f.show_if_field_key is not null and upper(coalesce(v_data->>f.show_if_field_key,''))<>'YA' then continue; end if;
   if f.required and (not (v_data ? f.field_key) or v_data->f.field_key is null or trim(coalesce(v_data->>f.field_key,''))='') then raise exception 'Field % wajib diisi.',f.label; end if;
   if f.field_type='file' and v_data ? f.field_key then
     v_file:=v_data->f.field_key;
     if jsonb_typeof(v_file)<>'object' then raise exception 'File % tidak valid.',f.label; end if;
     v_path:=coalesce(v_file->>'path',''); v_type:=coalesce(v_file->>'type','');
     begin v_size:=coalesce((v_file->>'size')::bigint,0); exception when others then v_size:=0; end;
     if position(e.id::text||'/' in v_path)<>1 or position('/'||f.field_key||'/' in v_path)=0 then raise exception 'Path file % tidak valid.',f.label; end if;
     if v_size<=0 or v_size>1048576 then raise exception 'File % maksimal 1 MB.',f.label; end if;
     if v_type not in ('image/jpeg','image/png','image/webp','application/pdf') then raise exception 'Format file % tidak didukung.',f.label; end if;
     if f.allowed_file_type='image' and v_type='application/pdf' then raise exception 'Field % hanya menerima gambar.',f.label; end if;
     if f.allowed_file_type='pdf' and v_type<>'application/pdf' then raise exception 'Field % hanya menerima PDF.',f.label; end if;
     if not exists(select 1 from storage.objects o where o.bucket_id='registration-files' and o.name=v_path) then raise exception 'Upload file % belum selesai.',f.label; end if;
   end if;
 end loop;

 insert into public.registrations(event_id,full_name,phone,email,custom_data)
 values(e.id,upper(trim(p_payload->>'full_name')),v_phone,v_email,v_data) returning * into r;
 insert into public.dashboard_signal(event_id) values(e.id);
 return jsonb_build_object('id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at);
end $$;
grant execute on function public.v3_public_register(text,jsonb) to anon;

create or replace function public.v3_public_ticket_by_token(p_slug text,p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype; r public.registrations%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 select * into r from public.registrations where event_id=e.id and qr_token=p_token; if r.id is null then return null; end if;
 return jsonb_build_object(
  'event',jsonb_build_object('name',e.name,'slug',e.slug,'event_date',e.event_date,'logo_data_url',e.logo_data_url,'banner_data_url',e.banner_data_url,'background_data_url',e.background_data_url,'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme),
  'ticket',jsonb_build_object('id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at)
 );
end $$;
grant execute on function public.v3_public_ticket_by_token(text,text) to anon;

-- External viewer remains privacy-limited. Theme values are safe branding metadata only.
create or replace function public.v3_external_view(p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
  select * into e from public.events where external_token=p_token and external_view_enabled=true;
  if e.id is null then return null; end if;
  return jsonb_build_object(
    'event',jsonb_build_object(
      'name',e.name,'slug',e.slug,'event_date',e.event_date,'logo_data_url',e.logo_data_url,'banner_data_url',e.banner_data_url,'background_data_url',e.background_data_url,
      'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme
    ),
    'stats',jsonb_build_object(
      'total',(select count(*) from public.registrations where event_id=e.id),
      'attended',(select count(*) from public.registrations where event_id=e.id and attendance_status='ATTENDED'),
      'not_attended',(select count(*) from public.registrations where event_id=e.id and attendance_status<>'ATTENDED')
    ),
    'participants',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'created_at',r.created_at,'full_name',r.full_name,
        'phone',repeat('•',greatest(char_length(coalesce(r.phone,''))-4,0)) || right(coalesce(r.phone,''),4),
        'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at
      ) order by r.created_at desc) from public.registrations r where event_id=e.id
    ),'[]'::jsonb)
  );
end $$;
grant execute on function public.v3_external_view(text) to anon;
