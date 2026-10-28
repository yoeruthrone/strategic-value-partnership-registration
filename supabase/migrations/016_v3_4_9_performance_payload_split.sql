-- SENA Registration Platform V3.4.9
-- Performance optimization: keep heavy base64 image assets out of blocking config/data RPCs.
-- Zero data loss / no table changes. Existing images remain stored exactly as before.

-- Public registration metadata: intentionally excludes branding/reference-image data URLs.
create or replace function public.v3_public_event_config(p_slug text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug));
 if e.id is null then return null; end if;
 return jsonb_build_object(
   'event',jsonb_build_object(
      'id',e.id,'name',e.name,'slug',e.slug,'event_date',e.event_date,'registration_open',e.registration_open,
      'name_label',e.name_label,'phone_label',e.phone_label,'email_label',e.email_label,
      'name_description',e.name_description,'phone_description',e.phone_description,'email_description',e.email_description,
      'registration_intro',e.registration_intro,'core_field_order',e.core_field_order,
      'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme,
      'guest_max_count',e.guest_max_count,'guest_section_label',e.guest_section_label
   ),
   'fields',coalesce((
     select jsonb_agg(jsonb_build_object(
       'id',f.id,'event_id',f.event_id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,
       'required',f.required,'options',f.options,'sort_order',f.sort_order,
       'show_if_field_key',f.show_if_field_key,'show_if_value',f.show_if_value,
       'description',f.description,'allowed_file_type',f.allowed_file_type,'is_archived',f.is_archived
     ) order by f.sort_order,f.label)
     from public.event_fields f where f.event_id=e.id and f.is_archived=false
   ),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;

-- Heavy public assets are fetched separately so the form metadata can render immediately.
create or replace function public.v3_public_event_assets(p_slug text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug));
 if e.id is null then return null; end if;
 return jsonb_build_object(
   'event',jsonb_build_object(
     'logo_data_url',e.logo_data_url,
     'banner_data_url',e.banner_data_url,
     'background_data_url',e.background_data_url
   ),
   'field_reference_images',coalesce((
     select jsonb_object_agg(f.field_key,f.reference_image_data_url)
     from public.event_fields f
     where f.event_id=e.id and f.is_archived=false and f.reference_image_data_url is not null
   ),'{}'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_assets(text) to anon;

-- Admin Form Builder metadata: excludes all base64 assets from the first blocking response.
create or replace function public.v3_admin_form_config(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
   'event',(select jsonb_build_object(
     'id',e.id,'name',e.name,
     'name_label',e.name_label,'phone_label',e.phone_label,'email_label',e.email_label,
     'name_description',e.name_description,'phone_description',e.phone_description,'email_description',e.email_description,
     'core_field_order',e.core_field_order
   ) from public.events e where e.id=p_event_id),
   'fields',coalesce((select jsonb_agg(jsonb_build_object(
     'id',f.id,'event_id',f.event_id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,
     'required',f.required,'options',f.options,'sort_order',f.sort_order,
     'show_if_field_key',f.show_if_field_key,'show_if_value',f.show_if_value,
     'description',f.description,'allowed_file_type',f.allowed_file_type,
     'is_archived',f.is_archived,'archived_at',f.archived_at
   ) order by f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=false),'[]'::jsonb),
   'archived_fields',coalesce((select jsonb_agg(jsonb_build_object(
     'id',f.id,'event_id',f.event_id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,
     'required',f.required,'options',f.options,'sort_order',f.sort_order,
     'show_if_field_key',f.show_if_field_key,'show_if_value',f.show_if_value,
     'description',f.description,'allowed_file_type',f.allowed_file_type,
     'is_archived',f.is_archived,'archived_at',f.archived_at
   ) order by f.archived_at desc nulls last,f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=true),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_form_config(text,uuid) to anon;

create or replace function public.v3_admin_form_assets(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
   'field_reference_images',coalesce((
     select jsonb_object_agg(f.field_key,f.reference_image_data_url)
     from public.event_fields f
     where f.event_id=p_event_id and f.reference_image_data_url is not null
   ),'{}'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_form_assets(text,uuid) to anon;

-- Participants never needs event branding or field reference images.
create or replace function public.v3_admin_participants(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
   'event',(select jsonb_build_object(
     'id',e.id,'name',e.name,'slug',e.slug,
     'name_label',e.name_label,'phone_label',e.phone_label,'email_label',e.email_label
   ) from public.events e where e.id=p_event_id),
   'fields',coalesce((select jsonb_agg(jsonb_build_object(
     'id',f.id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,
     'sort_order',f.sort_order,'is_archived',f.is_archived
   ) order by f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=false),'[]'::jsonb),
   'archived_fields',coalesce((select jsonb_agg(jsonb_build_object(
     'id',f.id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,
     'sort_order',f.sort_order,'is_archived',f.is_archived,'archived_at',f.archived_at
   ) order by f.archived_at desc nulls last,f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=true),'[]'::jsonb),
   'participants',coalesce((
     select jsonb_agg(
       to_jsonb(r) || jsonb_build_object(
         'leader_name',case when r.participant_role='GUEST' then l.full_name else null end,
         'custom_data',case when r.participant_role='GUEST' then coalesce(l.custom_data,'{}'::jsonb) else coalesce(r.custom_data,'{}'::jsonb) end
       )
       order by coalesce(l.created_at,r.created_at) desc, case when r.participant_role='LEADER' then 0 else 1 end, r.created_at asc
     )
     from public.registrations r
     left join public.registrations l on l.id=r.leader_registration_id
     where r.event_id=p_event_id
   ),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_participants(text,uuid) to anon;

-- Event Overview metadata: branding assets are split into v3_admin_event_assets.
create or replace function public.v3_admin_event_snapshot(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
   'event',(select jsonb_build_object(
     'id',e.id,'name',e.name,'slug',e.slug,'event_date',e.event_date,'capacity',e.capacity,
     'registration_open',e.registration_open,'external_view_enabled',e.external_view_enabled,'external_token',e.external_token,
     'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme
   ) from public.events e where e.id=p_event_id),
   'stats',jsonb_build_object(
     'total',(select count(*) from public.registrations where event_id=p_event_id),
     'attended',(select count(*) from public.registrations where event_id=p_event_id and attendance_status='ATTENDED'),
     'not_attended',(select count(*) from public.registrations where event_id=p_event_id and attendance_status<>'ATTENDED')
   ),
   'fields',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'label',f.label,'field_key',f.field_key,'field_type',f.field_type,'sort_order',f.sort_order) order by f.sort_order,f.label) from public.event_fields f where f.event_id=p_event_id and f.is_archived=false),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_event_snapshot(text,uuid) to anon;

create or replace function public.v3_admin_event_assets(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return (select jsonb_build_object(
   'logo_data_url',e.logo_data_url,
   'banner_data_url',e.banner_data_url,
   'background_data_url',e.background_data_url
 ) from public.events e where e.id=p_event_id);
end $$;
grant execute on function public.v3_admin_event_assets(text,uuid) to anon;

-- Preserve reference images when a lightweight Form Builder row is edited before its lazy asset arrives.
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
   reference_image_data_url=case when p_field ? 'reference_image_data_url' then excluded.reference_image_data_url else public.event_fields.reference_image_data_url end,
   is_archived=false,archived_at=null
 returning * into f;
 return to_jsonb(f);
exception when unique_violation then
 raise exception 'Setiap opsi conditional hanya boleh menampilkan satu field target.';
end $$;
grant execute on function public.v3_admin_upsert_field(text,uuid,jsonb) to anon;
