-- SENA Registration Platform V3.1.2
-- Additive migration: per-field helper/description text, including locked core fields.
-- Preserves all events, registrations, QR tokens, attendance, branding and form logic.

alter table public.events
  add column if not exists name_description text,
  add column if not exists phone_description text,
  add column if not exists email_description text;

alter table public.event_fields
  add column if not exists description text;

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
  background_data_url=case when p_patch ? 'background_data_url' then nullif(p_patch->>'background_data_url','') else background_data_url end,
  name_description=case when p_patch ? 'name_description' then nullif(trim(p_patch->>'name_description'),'') else name_description end,
  phone_description=case when p_patch ? 'phone_description' then nullif(trim(p_patch->>'phone_description'),'') else phone_description end,
  email_description=case when p_patch ? 'email_description' then nullif(trim(p_patch->>'email_description'),'') else email_description end
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
 insert into public.event_fields(event_id,label,field_key,field_type,required,options,sort_order,show_if_field_key,description)
 values(
   p_event_id,
   trim(p_field->>'label'),
   lower(trim(p_field->>'field_key')),
   v_type,
   coalesce((p_field->>'required')::boolean,false),
   case when v_type='yes_no' then '["YA","TIDAK"]'::jsonb else coalesce(p_field->'options','[]'::jsonb) end,
   coalesce((p_field->>'sort_order')::int,10),
   case when v_type='yes_no' then null else v_show end,
   nullif(trim(coalesce(p_field->>'description','')),'')
 )
 on conflict(event_id,field_key) do update set
   label=excluded.label,
   field_type=excluded.field_type,
   required=excluded.required,
   options=excluded.options,
   sort_order=excluded.sort_order,
   show_if_field_key=excluded.show_if_field_key,
   description=excluded.description
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
      'name_description',e.name_description,'phone_description',e.phone_description,'email_description',e.email_description
   ),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;
