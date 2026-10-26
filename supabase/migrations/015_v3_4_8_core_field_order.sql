-- SENA Registration Platform V3.4.8
-- Reorder locked core fields within the core section only.
-- Internal keys and required behavior remain unchanged.

alter table public.events
  add column if not exists core_field_order jsonb not null default '["full_name","phone","email"]'::jsonb;

create or replace function public.v3_admin_event_update(p_secret text,p_event_id uuid,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.events%rowtype; v text; v_guest_max integer; v_core_order jsonb;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 foreach v in array array['theme_primary','theme_accent','theme_secondary'] loop
   if p_patch ? v and coalesce(p_patch->>v,'') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Warna % harus format HEX #RRGGBB.',v; end if;
 end loop;
 if p_patch ? 'guest_max_count' then
   begin v_guest_max := (p_patch->>'guest_max_count')::integer; exception when others then raise exception 'Maksimal peserta tambahan harus berupa angka 2-10.'; end;
   if v_guest_max < 2 or v_guest_max > 10 then raise exception 'Maksimal peserta tambahan harus antara 2 sampai 10 orang.'; end if;
 end if;
 if p_patch ? 'core_field_order' then
   v_core_order:=p_patch->'core_field_order';
   if jsonb_typeof(v_core_order)<>'array' or jsonb_array_length(v_core_order)<>3
      or not (v_core_order @> '["full_name","phone","email"]'::jsonb and '["full_name","phone","email"]'::jsonb @> v_core_order) then
     raise exception 'Urutan core field tidak valid.';
   end if;
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
  name_label=case when p_patch ? 'name_label' then coalesce(nullif(trim(p_patch->>'name_label'),''),'Nama Lengkap') else name_label end,
  phone_label=case when p_patch ? 'phone_label' then coalesce(nullif(trim(p_patch->>'phone_label'),''),'No. Telepon') else phone_label end,
  email_label=case when p_patch ? 'email_label' then coalesce(nullif(trim(p_patch->>'email_label'),''),'Email') else email_label end,
  name_description=case when p_patch ? 'name_description' then nullif(trim(p_patch->>'name_description'),'') else name_description end,
  phone_description=case when p_patch ? 'phone_description' then nullif(trim(p_patch->>'phone_description'),'') else phone_description end,
  email_description=case when p_patch ? 'email_description' then nullif(trim(p_patch->>'email_description'),'') else email_description end,
  registration_intro=case when p_patch ? 'registration_intro' then nullif(trim(p_patch->>'registration_intro'),'') else registration_intro end,
  theme_primary=case when p_patch ? 'theme_primary' then upper(p_patch->>'theme_primary') else theme_primary end,
  theme_accent=case when p_patch ? 'theme_accent' then upper(p_patch->>'theme_accent') else theme_accent end,
  theme_secondary=case when p_patch ? 'theme_secondary' then upper(p_patch->>'theme_secondary') else theme_secondary end,
  default_theme=case when p_patch ? 'default_theme' then p_patch->>'default_theme' else default_theme end,
  guest_max_count=case when p_patch ? 'guest_max_count' then v_guest_max else guest_max_count end,
  guest_section_label=case when p_patch ? 'guest_section_label' then coalesce(nullif(trim(p_patch->>'guest_section_label'),''),'Peserta Tambahan') else guest_section_label end,
  core_field_order=case when p_patch ? 'core_field_order' then v_core_order else core_field_order end
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
      'name_label',e.name_label,'phone_label',e.phone_label,'email_label',e.email_label,
      'name_description',e.name_description,'phone_description',e.phone_description,'email_description',e.email_description,
      'registration_intro',e.registration_intro,'core_field_order',e.core_field_order,
      'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme,
      'guest_max_count',e.guest_max_count,'guest_section_label',e.guest_section_label
   ),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=e.id and is_archived=false),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_event_config(text) to anon;
