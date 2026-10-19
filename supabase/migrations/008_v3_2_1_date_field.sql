-- SENA Registration Platform V3.2.1
-- Additive/data-safe: allow Date / Calendar custom fields.

alter table public.event_fields drop constraint if exists event_fields_field_type_check;
alter table public.event_fields add constraint event_fields_field_type_check
  check (field_type in ('text','number','date','dropdown','radio','checkbox','textarea','yes_no','file'));

create or replace function public.v3_admin_upsert_field(p_secret text,p_event_id uuid,p_field jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 f public.event_fields%rowtype;
 v_show text:=nullif(trim(coalesce(p_field->>'show_if_field_key','')),'');
 v_type text:=p_field->>'field_type';
 v_allowed text:=coalesce(nullif(p_field->>'allowed_file_type',''),'image_pdf');
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 if v_type not in ('text','number','date','dropdown','radio','checkbox','textarea','yes_no','file') then raise exception 'Tipe field tidak valid.'; end if;
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
