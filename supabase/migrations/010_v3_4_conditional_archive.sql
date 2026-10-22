-- SENA Registration Platform V3.4
-- Custom 2-option conditional choice + safe field archive/restore.
-- Additive/data-safe migration.

alter table public.event_fields
  add column if not exists show_if_value text,
  add column if not exists is_archived boolean not null default false,
  add column if not exists archived_at timestamptz;

-- Preserve old YA/TIDAK behavior.
update public.event_fields
set show_if_value='YA'
where show_if_field_key is not null and coalesce(show_if_value,'')='';

alter table public.event_fields drop constraint if exists event_fields_field_type_check;
alter table public.event_fields add constraint event_fields_field_type_check
  check (field_type in ('text','number','date','dropdown','radio','checkbox','textarea','yes_no','conditional_choice','file'));

-- Old index allowed only one target total per trigger. V3.4 allows one target per option.
drop index if exists public.idx_event_fields_one_target_per_trigger;
create unique index if not exists idx_event_fields_one_target_per_option
  on public.event_fields(event_id,show_if_field_key,show_if_value)
  where show_if_field_key is not null and show_if_value is not null and is_archived=false;

create or replace function public.v3_admin_form_config(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
   'event',(select to_jsonb(e) from public.events e where id=p_event_id),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=p_event_id and is_archived=false),'[]'::jsonb),
   'archived_fields',coalesce((select jsonb_agg(to_jsonb(f) order by archived_at desc nulls last,sort_order,label) from public.event_fields f where event_id=p_event_id and is_archived=true),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_form_config(text,uuid) to anon;

create or replace function public.v3_admin_upsert_field(p_secret text,p_event_id uuid,p_field jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 f public.event_fields%rowtype;
 v_show text:=nullif(trim(coalesce(p_field->>'show_if_field_key','')),'');
 v_show_value text:=nullif(trim(coalesce(p_field->>'show_if_value','')),'');
 v_type text:=p_field->>'field_type';
 v_allowed text:=coalesce(nullif(p_field->>'allowed_file_type',''),'image_pdf');
 v_options jsonb:=coalesce(p_field->'options','[]'::jsonb);
 v_trigger public.event_fields%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 if v_type not in ('text','number','date','dropdown','radio','checkbox','textarea','yes_no','conditional_choice','file') then raise exception 'Tipe field tidak valid.'; end if;
 if v_allowed not in ('image','pdf','image_pdf') then raise exception 'Rule file tidak valid.'; end if;

 if v_type='yes_no' then v_options:='["YA","TIDAK"]'::jsonb; end if;
 if v_type='conditional_choice' then
   if jsonb_typeof(v_options)<>'array' or jsonb_array_length(v_options)<>2 then raise exception 'Conditional Choice harus memiliki tepat 2 opsi.'; end if;
   if trim(coalesce(v_options->>0,''))='' or trim(coalesce(v_options->>1,''))='' then raise exception 'Kedua opsi Conditional Choice wajib diisi.'; end if;
   if lower(trim(v_options->>0))=lower(trim(v_options->>1)) then raise exception 'Dua opsi Conditional Choice harus berbeda.'; end if;
 end if;

 if v_show is not null then
   if lower(trim(p_field->>'field_key'))=v_show then raise exception 'Field tidak dapat bergantung pada dirinya sendiri.'; end if;
   select * into v_trigger from public.event_fields where event_id=p_event_id and field_key=v_show and is_archived=false;
   if v_trigger.id is null or v_trigger.field_type not in ('yes_no','conditional_choice') then raise exception 'Conditional logic harus menggunakan field Conditional Choice.'; end if;
   if v_show_value is null then v_show_value:=case when v_trigger.field_type='yes_no' then 'YA' else null end; end if;
   if v_show_value is null or not exists(select 1 from jsonb_array_elements_text(v_trigger.options) o(value) where o.value=v_show_value) then
     raise exception 'Nilai conditional tidak sesuai dengan opsi trigger.';
   end if;
 end if;

 insert into public.event_fields(event_id,label,field_key,field_type,required,options,sort_order,show_if_field_key,show_if_value,description,allowed_file_type,reference_image_data_url,is_archived,archived_at)
 values(
   p_event_id,trim(p_field->>'label'),lower(trim(p_field->>'field_key')),v_type,
   coalesce((p_field->>'required')::boolean,false),v_options,
   coalesce((p_field->>'sort_order')::int,10),
   case when v_type in ('yes_no','conditional_choice') then null else v_show end,
   case when v_type in ('yes_no','conditional_choice') then null else v_show_value end,
   nullif(trim(coalesce(p_field->>'description','')),''),v_allowed,
   case when p_field ? 'reference_image_data_url' then nullif(p_field->>'reference_image_data_url','') else null end,
   false,null
 )
 on conflict(event_id,field_key) do update set
   label=excluded.label,field_type=excluded.field_type,required=excluded.required,options=excluded.options,
   sort_order=excluded.sort_order,show_if_field_key=excluded.show_if_field_key,show_if_value=excluded.show_if_value,
   description=excluded.description,allowed_file_type=excluded.allowed_file_type,
   reference_image_data_url=excluded.reference_image_data_url,is_archived=false,archived_at=null
 returning * into f;
 return to_jsonb(f);
exception when unique_violation then
 raise exception 'Setiap opsi conditional hanya boleh menampilkan satu field target.';
end $$;
grant execute on function public.v3_admin_upsert_field(text,uuid,jsonb) to anon;

-- Keep old RPC name for frontend compatibility, but archive instead of destructive delete.
create or replace function public.v3_admin_delete_field(p_secret text,p_event_id uuid,p_field_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_key text;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 select field_key into v_key from public.event_fields where id=p_field_id and event_id=p_event_id and is_archived=false;
 if v_key is null then return false; end if;
 -- Detach active targets if their trigger is archived.
 update public.event_fields
 set show_if_field_key=null,show_if_value=null
 where event_id=p_event_id and is_archived=false and show_if_field_key=v_key;
 update public.event_fields
 set is_archived=true,archived_at=now(),show_if_field_key=null,show_if_value=null
 where id=p_field_id and event_id=p_event_id;
 return true;
end $$;
grant execute on function public.v3_admin_delete_field(text,uuid,uuid) to anon;

create or replace function public.v3_admin_restore_field(p_secret text,p_event_id uuid,p_field_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare f public.event_fields%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 update public.event_fields set is_archived=false,archived_at=null
 where id=p_field_id and event_id=p_event_id and is_archived=true returning * into f;
 if f.id is null then raise exception 'Field arsip tidak ditemukan.'; end if;
 return to_jsonb(f);
end $$;
grant execute on function public.v3_admin_restore_field(text,uuid,uuid) to anon;

create or replace function public.v3_admin_participants(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
   'event',(select to_jsonb(e) from public.events e where id=p_event_id),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=p_event_id and is_archived=false),'[]'::jsonb),
   'archived_fields',coalesce((select jsonb_agg(to_jsonb(f) order by archived_at desc nulls last,sort_order,label) from public.event_fields f where event_id=p_event_id and is_archived=true),'[]'::jsonb),
   'participants',coalesce((
     select jsonb_agg(
       to_jsonb(r) || jsonb_build_object('leader_name',case when r.participant_role='GUEST' then l.full_name else null end)
       order by coalesce(l.created_at,r.created_at) desc, case when r.participant_role='LEADER' then 0 else 1 end, r.created_at asc
     )
     from public.registrations r
     left join public.registrations l on l.id=r.leader_registration_id
     where r.event_id=p_event_id
   ),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_participants(text,uuid) to anon;

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
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id and is_archived=false),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;

-- Preserve V3.3 group registration while honoring V3.4 conditional values and archived fields.
create or replace function public.v3_public_register(p_slug text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 e public.events%rowtype; r public.registrations%rowtype;
 v_phone text:=public.v3_norm_phone(p_payload->>'phone');
 v_email text:=public.v3_norm_email(p_payload->>'email');
 v_data jsonb:=coalesce(p_payload->'custom_data','{}'::jsonb);
 v_guests jsonb:=coalesce(p_payload->'guests','[]'::jsonb);
 v_guest_count integer:=0; v_phones text[]; v_emails text[];
 f record; g jsonb; v_file jsonb; v_path text; v_type text; v_size bigint;
 v_gname text; v_gphone text; v_gemail text;
begin
 select * into e from public.events where slug=lower(trim(p_slug)) for update;
 if e.id is null then raise exception 'Event tidak ditemukan.'; end if;
 if not e.registration_open then raise exception 'Registrasi sudah ditutup.'; end if;
 if trim(coalesce(p_payload->>'full_name',''))='' or length(v_phone)<8 or position('@' in v_email)=0 then raise exception 'Nama, No. Telepon dan Email leader wajib valid.'; end if;
 if jsonb_typeof(v_guests)<>'array' then raise exception 'Data peserta tambahan tidak valid.'; end if;
 v_guest_count:=jsonb_array_length(v_guests); if v_guest_count>10 then raise exception 'Maksimal 10 peserta tambahan.'; end if;
 v_phones:=array[v_phone]; v_emails:=array[v_email];
 for g in select value from jsonb_array_elements(v_guests) loop
   v_gname:=trim(coalesce(g->>'full_name','')); v_gphone:=public.v3_norm_phone(g->>'phone'); v_gemail:=public.v3_norm_email(g->>'email');
   if v_gname='' or length(v_gphone)<8 or position('@' in v_gemail)=0 then raise exception 'Nama, No. Telepon dan Email setiap peserta tambahan wajib valid.'; end if;
   if v_gphone=any(v_phones) then raise exception 'Nomor telepon % dipakai lebih dari sekali dalam rombongan.',v_gphone; end if;
   if v_gemail=any(v_emails) then raise exception 'Email % dipakai lebih dari sekali dalam rombongan.',v_gemail; end if;
   v_phones:=array_append(v_phones,v_gphone); v_emails:=array_append(v_emails,v_gemail);
 end loop;
 if (select count(*) from public.registrations where event_id=e.id)+1+v_guest_count>e.capacity then raise exception 'Sisa kapasitas event tidak cukup untuk seluruh rombongan.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and phone=any(v_phones)) then raise exception 'Ada nomor telepon leader/peserta tambahan yang sudah terdaftar pada event ini.'; end if;
 if exists(select 1 from public.registrations where event_id=e.id and email=any(v_emails)) then raise exception 'Ada email leader/peserta tambahan yang sudah terdaftar pada event ini.'; end if;

 for f in select * from public.event_fields where event_id=e.id and is_archived=false order by sort_order loop
   if f.show_if_field_key is not null and coalesce(v_data->>f.show_if_field_key,'')<>coalesce(f.show_if_value,'YA') then continue; end if;
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

 insert into public.registrations(event_id,full_name,phone,email,custom_data,participant_role,leader_registration_id)
 values(e.id,upper(trim(p_payload->>'full_name')),v_phone,v_email,v_data,'LEADER',null) returning * into r;
 for g in select value from jsonb_array_elements(v_guests) loop
   insert into public.registrations(event_id,created_at,full_name,phone,email,custom_data,participant_role,leader_registration_id,qr_token)
   values(e.id,r.created_at,upper(trim(g->>'full_name')),public.v3_norm_phone(g->>'phone'),public.v3_norm_email(g->>'email'),'{}'::jsonb,'GUEST',r.id,null);
 end loop;
 insert into public.dashboard_signal(event_id) values(e.id);
 return jsonb_build_object(
   'id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at,
   'guest_count',v_guest_count,
   'guests',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'full_name',x.full_name,'phone',x.phone,'email',x.email) order by x.created_at) from public.registrations x where x.leader_registration_id=r.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_register(text,jsonb) to anon;
