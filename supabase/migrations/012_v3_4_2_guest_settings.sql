-- SENA Registration Platform V3.4.2
-- Per-event guest limit (2-10) and editable guest section label.
-- Additive/data-safe migration.

alter table public.events
  add column if not exists guest_max_count integer not null default 10,
  add column if not exists guest_section_label text not null default 'Peserta Tambahan';

update public.events
set guest_max_count = greatest(2, least(10, coalesce(guest_max_count,10))),
    guest_section_label = coalesce(nullif(trim(guest_section_label),''),'Peserta Tambahan');

alter table public.events drop constraint if exists events_guest_max_count_check;
alter table public.events add constraint events_guest_max_count_check check (guest_max_count between 2 and 10);

create or replace function public.v3_admin_event_update(p_secret text,p_event_id uuid,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype; v text; v_guest_max integer;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 foreach v in array array['theme_primary','theme_accent','theme_secondary'] loop
   if p_patch ? v and coalesce(p_patch->>v,'') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Warna % harus format HEX #RRGGBB.',v; end if;
 end loop;
 if p_patch ? 'guest_max_count' then
   begin v_guest_max := (p_patch->>'guest_max_count')::integer; exception when others then raise exception 'Maksimal peserta tambahan harus berupa angka 2-10.'; end;
   if v_guest_max < 2 or v_guest_max > 10 then raise exception 'Maksimal peserta tambahan harus antara 2 sampai 10 orang.'; end if;
 end if;
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
  default_theme=case when p_patch ? 'default_theme' then p_patch->>'default_theme' else default_theme end,
  guest_max_count=case when p_patch ? 'guest_max_count' then v_guest_max else guest_max_count end,
  guest_section_label=case when p_patch ? 'guest_section_label' then coalesce(nullif(trim(p_patch->>'guest_section_label'),''),'Peserta Tambahan') else guest_section_label end
 where id=p_event_id returning * into e;
 return to_jsonb(e);
end $$;
grant execute on function public.v3_admin_event_update(text,uuid,jsonb) to anon;

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
      'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme,
      'guest_max_count',e.guest_max_count,'guest_section_label',e.guest_section_label
   ),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id and is_archived=false),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;

-- Preserve V3.4.1 inheritance while enforcing the per-event guest limit.
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
 v_guest_count:=jsonb_array_length(v_guests);
 if v_guest_count>e.guest_max_count then raise exception 'Maksimal % peserta tambahan untuk event ini.',e.guest_max_count; end if;
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
   values(e.id,r.created_at,upper(trim(g->>'full_name')),public.v3_norm_phone(g->>'phone'),public.v3_norm_email(g->>'email'),v_data,'GUEST',r.id,null);
 end loop;
 insert into public.dashboard_signal(event_id) values(e.id);
 return jsonb_build_object(
   'id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at,
   'guest_count',v_guest_count,
   'guests',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'full_name',x.full_name,'phone',x.phone,'email',x.email) order by x.created_at) from public.registrations x where x.leader_registration_id=r.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_register(text,jsonb) to anon;
