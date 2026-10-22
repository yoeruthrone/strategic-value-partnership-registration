-- SENA Registration Platform V3.4.1
-- Guest rows inherit the leader's custom field values.
-- Additive/data-safe migration. Existing guest rows are backfilled.

-- Backfill existing guests so historical/admin data is immediately complete.
update public.registrations g
set custom_data = coalesce(l.custom_data, '{}'::jsonb)
from public.registrations l
where g.participant_role='GUEST'
  and g.leader_registration_id=l.id;

-- Admin payload always resolves guest custom_data from the leader as the source of truth.
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

-- Preserve V3.4 registration rules, but copy leader custom_data into every guest row.
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
