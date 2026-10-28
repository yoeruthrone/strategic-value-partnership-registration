-- SENA Registration Platform V3.5.1
-- Custom field scope: GROUP_SHARED, PER_PARTICIPANT, LEADER_ONLY.
-- Existing fields preserve historical behavior by defaulting to GROUP_SHARED.

alter table public.event_fields
  add column if not exists data_scope text not null default 'GROUP_SHARED';

update public.event_fields set data_scope='GROUP_SHARED' where data_scope is null or data_scope not in ('GROUP_SHARED','PER_PARTICIPANT','LEADER_ONLY');
alter table public.event_fields drop constraint if exists event_fields_data_scope_check;
alter table public.event_fields add constraint event_fields_data_scope_check check (data_scope in ('GROUP_SHARED','PER_PARTICIPANT','LEADER_ONLY'));

create or replace function public.v3_public_event_config(p_slug text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 return jsonb_build_object(
  'event',jsonb_build_object('id',e.id,'name',e.name,'slug',e.slug,'event_date',e.event_date,'registration_open',e.registration_open,'name_label',e.name_label,'phone_label',e.phone_label,'email_label',e.email_label,'name_description',e.name_description,'phone_description',e.phone_description,'email_description',e.email_description,'registration_intro',e.registration_intro,'core_field_order',e.core_field_order,'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme,'guest_max_count',e.guest_max_count,'guest_section_label',e.guest_section_label),
  'fields',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'event_id',f.event_id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,'required',f.required,'options',f.options,'sort_order',f.sort_order,'show_if_field_key',f.show_if_field_key,'show_if_value',f.show_if_value,'description',f.description,'allowed_file_type',f.allowed_file_type,'is_archived',f.is_archived,'data_scope',f.data_scope) order by f.sort_order,f.label) from public.event_fields f where f.event_id=e.id and f.is_archived=false),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;

create or replace function public.v3_admin_form_config(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
  'event',(select jsonb_build_object('id',e.id,'name',e.name,'name_label',e.name_label,'phone_label',e.phone_label,'email_label',e.email_label,'name_description',e.name_description,'phone_description',e.phone_description,'email_description',e.email_description,'core_field_order',e.core_field_order) from public.events e where e.id=p_event_id),
  'fields',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'event_id',f.event_id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,'required',f.required,'options',f.options,'sort_order',f.sort_order,'show_if_field_key',f.show_if_field_key,'show_if_value',f.show_if_value,'description',f.description,'allowed_file_type',f.allowed_file_type,'is_archived',f.is_archived,'archived_at',f.archived_at,'data_scope',f.data_scope) order by f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=false),'[]'::jsonb),
  'archived_fields',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'event_id',f.event_id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,'required',f.required,'options',f.options,'sort_order',f.sort_order,'show_if_field_key',f.show_if_field_key,'show_if_value',f.show_if_value,'description',f.description,'allowed_file_type',f.allowed_file_type,'is_archived',f.is_archived,'archived_at',f.archived_at,'data_scope',f.data_scope) order by f.archived_at desc nulls last,f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=true),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_form_config(text,uuid) to anon;

create or replace function public.v3_admin_upsert_field(p_secret text,p_event_id uuid,p_field jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare f public.event_fields%rowtype;v_show text:=nullif(trim(coalesce(p_field->>'show_if_field_key','')),'');v_show_value text:=nullif(trim(coalesce(p_field->>'show_if_value','')),'');v_type text:=p_field->>'field_type';v_allowed text:=coalesce(nullif(p_field->>'allowed_file_type',''),'image_pdf');v_options jsonb:=coalesce(p_field->'options','[]'::jsonb);v_scope text:=coalesce(nullif(p_field->>'data_scope',''),'GROUP_SHARED');v_trigger public.event_fields%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 if v_type not in ('text','number','date','dropdown','radio','checkbox','textarea','yes_no','conditional_choice','file') then raise exception 'Tipe field tidak valid.'; end if;
 if v_allowed not in ('image','pdf','image_pdf') then raise exception 'Rule file tidak valid.'; end if;
 if v_scope not in ('GROUP_SHARED','PER_PARTICIPANT','LEADER_ONLY') then raise exception 'Scope field tidak valid.'; end if;
 if v_type='yes_no' then v_options:='["YA","TIDAK"]'::jsonb; end if;
 if v_type='conditional_choice' then if jsonb_typeof(v_options)<>'array' or jsonb_array_length(v_options)<>2 then raise exception 'Conditional Choice harus memiliki tepat 2 opsi.'; end if; if trim(coalesce(v_options->>0,''))='' or trim(coalesce(v_options->>1,''))='' or lower(trim(v_options->>0))=lower(trim(v_options->>1)) then raise exception 'Dua opsi Conditional Choice wajib diisi dan harus berbeda.'; end if; end if;
 if v_show is not null then
  if lower(trim(p_field->>'field_key'))=v_show then raise exception 'Field tidak dapat bergantung pada dirinya sendiri.'; end if;
  select * into v_trigger from public.event_fields where event_id=p_event_id and field_key=v_show and is_archived=false;
  if v_trigger.id is null or v_trigger.field_type not in ('yes_no','conditional_choice') then raise exception 'Conditional logic harus menggunakan field Conditional Choice.'; end if;
  if v_scope<>'PER_PARTICIPANT' and v_trigger.data_scope='PER_PARTICIPANT' then raise exception 'Field Group Shared/Leader Only tidak boleh bergantung pada trigger Per Participant.'; end if;
  if v_show_value is null then v_show_value:=case when v_trigger.field_type='yes_no' then 'YA' else null end; end if;
  if v_show_value is null or not exists(select 1 from jsonb_array_elements_text(v_trigger.options) o(value) where o.value=v_show_value) then raise exception 'Nilai conditional tidak sesuai dengan opsi trigger.'; end if;
 end if;
 insert into public.event_fields(event_id,label,field_key,field_type,required,options,sort_order,show_if_field_key,show_if_value,description,allowed_file_type,reference_image_data_url,is_archived,archived_at,data_scope)
 values(p_event_id,trim(p_field->>'label'),lower(trim(p_field->>'field_key')),v_type,coalesce((p_field->>'required')::boolean,false),v_options,coalesce((p_field->>'sort_order')::int,10),case when v_type in ('yes_no','conditional_choice') then null else v_show end,case when v_type in ('yes_no','conditional_choice') then null else v_show_value end,nullif(trim(coalesce(p_field->>'description','')),''),v_allowed,case when p_field ? 'reference_image_data_url' then nullif(p_field->>'reference_image_data_url','') else null end,false,null,v_scope)
 on conflict(event_id,field_key) do update set label=excluded.label,field_type=excluded.field_type,required=excluded.required,options=excluded.options,sort_order=excluded.sort_order,show_if_field_key=excluded.show_if_field_key,show_if_value=excluded.show_if_value,description=excluded.description,allowed_file_type=excluded.allowed_file_type,reference_image_data_url=case when p_field ? 'reference_image_data_url' then excluded.reference_image_data_url else public.event_fields.reference_image_data_url end,is_archived=false,archived_at=null,data_scope=excluded.data_scope
 returning * into f;return to_jsonb(f);
exception when unique_violation then raise exception 'Setiap opsi conditional hanya boleh menampilkan satu field target.';
end $$;
grant execute on function public.v3_admin_upsert_field(text,uuid,jsonb) to anon;

create or replace function public.v3_admin_participants(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
  'event',(select jsonb_build_object('id',e.id,'name',e.name,'slug',e.slug,'name_label',e.name_label,'phone_label',e.phone_label,'email_label',e.email_label) from public.events e where e.id=p_event_id),
  'fields',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,'sort_order',f.sort_order,'is_archived',f.is_archived,'data_scope',f.data_scope) order by f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=false),'[]'::jsonb),
  'archived_fields',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,'sort_order',f.sort_order,'is_archived',f.is_archived,'archived_at',f.archived_at,'data_scope',f.data_scope) order by f.archived_at desc nulls last,f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=true),'[]'::jsonb),
  'participants',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('leader_name',case when r.participant_role='GUEST' then l.full_name else null end,'custom_data',case when r.participant_role='GUEST' then
    coalesce((select jsonb_object_agg(f.field_key,l.custom_data->f.field_key) from public.event_fields f where f.event_id=p_event_id and f.data_scope='GROUP_SHARED' and l.custom_data ? f.field_key),'{}'::jsonb)
    || coalesce((select jsonb_object_agg(f.field_key,r.custom_data->f.field_key) from public.event_fields f where f.event_id=p_event_id and f.data_scope='PER_PARTICIPANT' and r.custom_data ? f.field_key),'{}'::jsonb)
   else coalesce(r.custom_data,'{}'::jsonb) end) order by coalesce(l.created_at,r.created_at) desc,case when r.participant_role='LEADER' then 0 else 1 end,r.created_at asc) from public.registrations r left join public.registrations l on l.id=r.leader_registration_id where r.event_id=p_event_id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_participants(text,uuid) to anon;

create or replace function public.v3_public_register(p_slug text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype;r public.registrations%rowtype;v_phone text:=public.v3_norm_phone(p_payload->>'phone');v_email text:=public.v3_norm_email(p_payload->>'email');v_data jsonb:=coalesce(p_payload->'custom_data','{}'::jsonb);v_guests jsonb:=coalesce(p_payload->'guests','[]'::jsonb);v_guest_count int:=0;v_phones text[];v_emails text[];f record;g jsonb;v_gdata jsonb;v_gfiltered jsonb;v_gname text;v_gphone text;v_gemail text;v_trigger_scope text;v_cond_value text;v_file jsonb;v_path text;v_type text;v_size bigint;
begin
 select * into e from public.events where slug=lower(trim(p_slug)) for update;if e.id is null then raise exception 'Event tidak ditemukan.';end if;if not e.registration_open then raise exception 'Registrasi sudah ditutup.';end if;
 if trim(coalesce(p_payload->>'full_name',''))='' or length(v_phone)<8 or position('@' in v_email)=0 then raise exception 'Nama, No. Telepon dan Email leader wajib valid.';end if;if jsonb_typeof(v_guests)<>'array' then raise exception 'Data peserta tambahan tidak valid.';end if;v_guest_count:=jsonb_array_length(v_guests);if v_guest_count>e.guest_max_count then raise exception 'Maksimal % peserta tambahan untuk event ini.',e.guest_max_count;end if;
 v_phones:=array[v_phone];v_emails:=array[v_email];for g in select value from jsonb_array_elements(v_guests) loop v_gname:=trim(coalesce(g->>'full_name',''));v_gphone:=public.v3_norm_phone(g->>'phone');v_gemail:=public.v3_norm_email(g->>'email');if v_gname='' or length(v_gphone)<8 or position('@' in v_gemail)=0 then raise exception 'Nama, No. Telepon dan Email setiap peserta tambahan wajib valid.';end if;if v_gphone=any(v_phones) then raise exception 'Nomor telepon % dipakai lebih dari sekali dalam rombongan.',v_gphone;end if;if v_gemail=any(v_emails) then raise exception 'Email % dipakai lebih dari sekali dalam rombongan.',v_gemail;end if;v_phones:=array_append(v_phones,v_gphone);v_emails:=array_append(v_emails,v_gemail);end loop;
 if (select count(*) from public.registrations where event_id=e.id)+1+v_guest_count>e.capacity then raise exception 'Sisa kapasitas event tidak cukup untuk seluruh rombongan.';end if;if exists(select 1 from public.registrations where event_id=e.id and phone=any(v_phones)) then raise exception 'Ada nomor telepon leader/peserta tambahan yang sudah terdaftar pada event ini.';end if;if exists(select 1 from public.registrations where event_id=e.id and email=any(v_emails)) then raise exception 'Ada email leader/peserta tambahan yang sudah terdaftar pada event ini.';end if;
 -- leader validates every visible custom field, regardless of scope
 for f in select * from public.event_fields where event_id=e.id and is_archived=false order by sort_order loop
  if f.show_if_field_key is not null and coalesce(v_data->>f.show_if_field_key,'')<>coalesce(f.show_if_value,'YA') then continue;end if;
  if f.required and (not(v_data?f.field_key) or v_data->f.field_key is null or trim(coalesce(v_data->>f.field_key,''))='') then raise exception 'Field % wajib diisi.',f.label;end if;
  if f.field_type='file' and v_data?f.field_key then v_file:=v_data->f.field_key;if jsonb_typeof(v_file)<>'object' then raise exception 'File % tidak valid.',f.label;end if;v_path:=coalesce(v_file->>'path','');v_type:=coalesce(v_file->>'type','');begin v_size:=coalesce((v_file->>'size')::bigint,0);exception when others then v_size:=0;end;if position(e.id::text||'/' in v_path)<>1 or position('/'||f.field_key||'/' in v_path)=0 then raise exception 'Path file % tidak valid.',f.label;end if;if v_size<=0 or v_size>1048576 then raise exception 'File % maksimal 1 MB.',f.label;end if;if v_type not in ('image/jpeg','image/png','image/webp','application/pdf') then raise exception 'Format file % tidak didukung.',f.label;end if;if f.allowed_file_type='image' and v_type='application/pdf' then raise exception 'Field % hanya menerima gambar.',f.label;end if;if f.allowed_file_type='pdf' and v_type<>'application/pdf' then raise exception 'Field % hanya menerima PDF.',f.label;end if;if not exists(select 1 from storage.objects o where o.bucket_id='registration-files' and o.name=v_path) then raise exception 'Upload file % belum selesai.',f.label;end if;end if;
 end loop;
 insert into public.registrations(event_id,full_name,phone,email,custom_data,participant_role,leader_registration_id) values(e.id,upper(trim(p_payload->>'full_name')),v_phone,v_email,v_data,'LEADER',null) returning * into r;
 for g in select value from jsonb_array_elements(v_guests) loop
  v_gdata:=coalesce(g->'custom_data','{}'::jsonb);v_gfiltered:='{}'::jsonb;
  for f in select * from public.event_fields where event_id=e.id and is_archived=false and data_scope='PER_PARTICIPANT' order by sort_order loop
   if f.show_if_field_key is not null then select data_scope into v_trigger_scope from public.event_fields where event_id=e.id and field_key=f.show_if_field_key;v_cond_value:=case when v_trigger_scope='PER_PARTICIPANT' then v_gdata->>f.show_if_field_key else v_data->>f.show_if_field_key end;if coalesce(v_cond_value,'')<>coalesce(f.show_if_value,'YA') then continue;end if;end if;
   if f.required and (not(v_gdata?f.field_key) or v_gdata->f.field_key is null or trim(coalesce(v_gdata->>f.field_key,''))='') then raise exception '%: field % wajib diisi.',coalesce(g->>'full_name','Peserta tambahan'),f.label;end if;
   if v_gdata?f.field_key then v_gfiltered:=v_gfiltered||jsonb_build_object(f.field_key,v_gdata->f.field_key);end if;
   if f.field_type='file' and v_gdata?f.field_key then v_file:=v_gdata->f.field_key;if jsonb_typeof(v_file)<>'object' then raise exception 'File % tidak valid.',f.label;end if;v_path:=coalesce(v_file->>'path','');v_type:=coalesce(v_file->>'type','');begin v_size:=coalesce((v_file->>'size')::bigint,0);exception when others then v_size:=0;end;if position(e.id::text||'/' in v_path)<>1 or position('/'||f.field_key||'/' in v_path)=0 then raise exception 'Path file % tidak valid.',f.label;end if;if v_size<=0 or v_size>1048576 then raise exception 'File % maksimal 1 MB.',f.label;end if;if v_type not in ('image/jpeg','image/png','image/webp','application/pdf') then raise exception 'Format file % tidak didukung.',f.label;end if;if f.allowed_file_type='image' and v_type='application/pdf' then raise exception 'Field % hanya menerima gambar.',f.label;end if;if f.allowed_file_type='pdf' and v_type<>'application/pdf' then raise exception 'Field % hanya menerima PDF.',f.label;end if;if not exists(select 1 from storage.objects o where o.bucket_id='registration-files' and o.name=v_path) then raise exception 'Upload file % belum selesai.',f.label;end if;end if;
  end loop;
  insert into public.registrations(event_id,created_at,full_name,phone,email,custom_data,participant_role,leader_registration_id,qr_token) values(e.id,r.created_at,upper(trim(g->>'full_name')),public.v3_norm_phone(g->>'phone'),public.v3_norm_email(g->>'email'),v_gfiltered,'GUEST',r.id,null);
 end loop;
 insert into public.dashboard_signal(event_id) values(e.id);
 return jsonb_build_object('id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at,'guest_count',v_guest_count,'guests',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'full_name',x.full_name,'phone',x.phone,'email',x.email) order by x.created_at) from public.registrations x where x.leader_registration_id=r.id),'[]'::jsonb));
end $$;
grant execute on function public.v3_public_register(text,jsonb) to anon;
