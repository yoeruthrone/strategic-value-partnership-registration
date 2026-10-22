-- SENA Registration Platform V3.3
-- Leader + Guests registration (max 10 guests), single QR on leader.
-- Additive/data-safe migration. Existing registrations become LEADER rows automatically.

alter table public.registrations
  add column if not exists participant_role text not null default 'LEADER',
  add column if not exists leader_registration_id uuid;

alter table public.registrations alter column qr_token drop not null;

alter table public.registrations drop constraint if exists registrations_participant_role_check;
alter table public.registrations add constraint registrations_participant_role_check
  check (participant_role in ('LEADER','GUEST'));

alter table public.registrations drop constraint if exists registrations_leader_registration_id_fkey;
alter table public.registrations add constraint registrations_leader_registration_id_fkey
  foreign key (leader_registration_id) references public.registrations(id) on delete cascade;

alter table public.registrations drop constraint if exists registrations_group_shape_check;
alter table public.registrations add constraint registrations_group_shape_check check (
  (participant_role='LEADER' and leader_registration_id is null and qr_token is not null)
  or
  (participant_role='GUEST' and leader_registration_id is not null and qr_token is null)
);

create index if not exists idx_reg_leader_registration on public.registrations(leader_registration_id);
create index if not exists idx_reg_event_role on public.registrations(event_id,participant_role);

-- Admin participant payload adds leader_name for clear grouping in tables/exports.
create or replace function public.v3_admin_participants(p_secret text,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 return jsonb_build_object(
   'event',(select to_jsonb(e) from public.events e where id=p_event_id),
   'fields',coalesce((select jsonb_agg(to_jsonb(f) order by sort_order,label) from public.event_fields f where event_id=p_event_id),'[]'::jsonb),
   'participants',coalesce((
     select jsonb_agg(
       to_jsonb(r) || jsonb_build_object(
         'leader_name',case when r.participant_role='GUEST' then l.full_name else null end
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

create or replace function public.v3_public_register(p_slug text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 e public.events%rowtype; r public.registrations%rowtype;
 v_phone text:=public.v3_norm_phone(p_payload->>'phone');
 v_email text:=public.v3_norm_email(p_payload->>'email');
 v_data jsonb:=coalesce(p_payload->'custom_data','{}'::jsonb);
 v_guests jsonb:=coalesce(p_payload->'guests','[]'::jsonb);
 v_guest_count integer:=0;
 v_phones text[];
 v_emails text[];
 f record; g jsonb;
 v_file jsonb; v_path text; v_type text; v_size bigint;
 v_gname text; v_gphone text; v_gemail text;
begin
 select * into e from public.events where slug=lower(trim(p_slug)) for update;
 if e.id is null then raise exception 'Event tidak ditemukan.'; end if;
 if not e.registration_open then raise exception 'Registrasi sudah ditutup.'; end if;
 if trim(coalesce(p_payload->>'full_name',''))='' or length(v_phone)<8 or position('@' in v_email)=0 then raise exception 'Nama, No. Telepon dan Email leader wajib valid.'; end if;
 if jsonb_typeof(v_guests)<>'array' then raise exception 'Data peserta tambahan tidak valid.'; end if;
 v_guest_count:=jsonb_array_length(v_guests);
 if v_guest_count>10 then raise exception 'Maksimal 10 peserta tambahan.'; end if;

 v_phones:=array[v_phone];
 v_emails:=array[v_email];

 -- Validate every guest core field and duplicates inside the same submission.
 for g in select value from jsonb_array_elements(v_guests) loop
   v_gname:=trim(coalesce(g->>'full_name',''));
   v_gphone:=public.v3_norm_phone(g->>'phone');
   v_gemail:=public.v3_norm_email(g->>'email');
   if v_gname='' or length(v_gphone)<8 or position('@' in v_gemail)=0 then
     raise exception 'Nama, No. Telepon dan Email setiap peserta tambahan wajib valid.';
   end if;
   if v_gphone=any(v_phones) then raise exception 'Nomor telepon % dipakai lebih dari sekali dalam rombongan.',v_gphone; end if;
   if v_gemail=any(v_emails) then raise exception 'Email % dipakai lebih dari sekali dalam rombongan.',v_gemail; end if;
   v_phones:=array_append(v_phones,v_gphone);
   v_emails:=array_append(v_emails,v_gemail);
 end loop;

 if (select count(*) from public.registrations where event_id=e.id) + 1 + v_guest_count > e.capacity then
   raise exception 'Sisa kapasitas event tidak cukup untuk seluruh rombongan.';
 end if;
 if exists(select 1 from public.registrations where event_id=e.id and phone=any(v_phones)) then
   raise exception 'Ada nomor telepon leader/peserta tambahan yang sudah terdaftar pada event ini.';
 end if;
 if exists(select 1 from public.registrations where event_id=e.id and email=any(v_emails)) then
   raise exception 'Ada email leader/peserta tambahan yang sudah terdaftar pada event ini.';
 end if;

 -- Custom fields apply only to the leader.
 for f in select * from public.event_fields where event_id=e.id order by sort_order loop
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

 insert into public.registrations(event_id,full_name,phone,email,custom_data,participant_role,leader_registration_id)
 values(e.id,upper(trim(p_payload->>'full_name')),v_phone,v_email,v_data,'LEADER',null)
 returning * into r;

 for g in select value from jsonb_array_elements(v_guests) loop
   insert into public.registrations(event_id,created_at,full_name,phone,email,custom_data,participant_role,leader_registration_id,qr_token)
   values(
     e.id,
     r.created_at,
     upper(trim(g->>'full_name')),
     public.v3_norm_phone(g->>'phone'),
     public.v3_norm_email(g->>'email'),
     '{}'::jsonb,
     'GUEST',
     r.id,
     null
   );
 end loop;

 insert into public.dashboard_signal(event_id) values(e.id);
 return jsonb_build_object(
   'id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,
   'qr_token',r.qr_token,'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at,
   'guest_count',v_guest_count,
   'guests',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'full_name',x.full_name,'phone',x.phone,'email',x.email) order by x.created_at) from public.registrations x where x.leader_registration_id=r.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_public_register(text,jsonb) to anon;

-- Recovery only returns the leader ticket because guests intentionally have no QR.
create or replace function public.v3_public_recover_ticket(p_slug text,p_phone text,p_email text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype; r public.registrations%rowtype;
 v_phone text:=public.v3_norm_phone(p_phone); v_email text:=public.v3_norm_email(p_email);
begin
 if coalesce(v_phone,'')='' or coalesce(v_email,'')='' then return null; end if;
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 select * into r from public.registrations
 where event_id=e.id and participant_role='LEADER' and phone=v_phone and email=v_email limit 1;
 if r.id is null then return null; end if;
 return jsonb_build_object(
   'id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,
   'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at,
   'guest_count',(select count(*) from public.registrations g where g.leader_registration_id=r.id)
 );
end $$;
grant execute on function public.v3_public_recover_ticket(text,text,text) to anon;

create or replace function public.v3_public_ticket_by_token(p_slug text,p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare e public.events%rowtype; r public.registrations%rowtype;
begin
 select * into e from public.events where slug=lower(trim(p_slug)); if e.id is null then return null; end if;
 select * into r from public.registrations where event_id=e.id and participant_role='LEADER' and qr_token=p_token;
 if r.id is null then return null; end if;
 return jsonb_build_object(
  'event',jsonb_build_object('name',e.name,'slug',e.slug,'event_date',e.event_date,'logo_data_url',e.logo_data_url,'banner_data_url',e.banner_data_url,'background_data_url',e.background_data_url,'theme_primary',e.theme_primary,'theme_accent',e.theme_accent,'theme_secondary',e.theme_secondary,'default_theme',e.default_theme),
  'ticket',jsonb_build_object(
    'id',r.id,'full_name',r.full_name,'phone',r.phone,'email',r.email,'qr_token',r.qr_token,
    'attendance_status',r.attendance_status,'checked_in_at',r.checked_in_at,
    'guest_count',(select count(*) from public.registrations g where g.leader_registration_id=r.id),
    'guests',coalesce((select jsonb_agg(jsonb_build_object('full_name',g.full_name,'phone',g.phone,'email',g.email) order by g.created_at) from public.registrations g where g.leader_registration_id=r.id),'[]'::jsonb)
  )
 );
end $$;
grant execute on function public.v3_public_ticket_by_token(text,text) to anon;

create or replace function public.v3_admin_lookup_qr(p_secret text,p_event_id uuid,p_token text)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare r public.registrations%rowtype;
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 select * into r from public.registrations where event_id=p_event_id and participant_role='LEADER' and qr_token=p_token;
 if r.id is null then return null; end if;
 return to_jsonb(r) || jsonb_build_object(
   'guest_count',(select count(*) from public.registrations g where g.leader_registration_id=r.id),
   'guests',coalesce((select jsonb_agg(jsonb_build_object('full_name',g.full_name,'phone',g.phone,'email',g.email,'attendance_status',g.attendance_status) order by g.created_at) from public.registrations g where g.leader_registration_id=r.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_lookup_qr(text,uuid,text) to anon;

-- One leader QR checks in the entire group.
create or replace function public.v3_admin_confirm_attendance(p_secret text,p_event_id uuid,p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.registrations%rowtype; v_now timestamptz:=now();
begin
 if not public.v3_admin_ok(p_secret) then raise exception 'Admin secret tidak valid.'; end if;
 select * into r from public.registrations where event_id=p_event_id and participant_role='LEADER' and qr_token=p_token for update;
 if r.id is null then raise exception 'QR tidak valid.'; end if;
 update public.registrations
 set attendance_status='ATTENDED', checked_in_at=coalesce(checked_in_at,v_now)
 where event_id=p_event_id and (id=r.id or leader_registration_id=r.id) and attendance_status<>'ATTENDED';
 select * into r from public.registrations where id=r.id;
 insert into public.dashboard_signal(event_id) values(p_event_id);
 return to_jsonb(r) || jsonb_build_object(
   'guest_count',(select count(*) from public.registrations g where g.leader_registration_id=r.id),
   'guests',coalesce((select jsonb_agg(jsonb_build_object('full_name',g.full_name,'phone',g.phone,'email',g.email,'attendance_status',g.attendance_status,'checked_in_at',g.checked_in_at) order by g.created_at) from public.registrations g where g.leader_registration_id=r.id),'[]'::jsonb)
 );
end $$;
grant execute on function public.v3_admin_confirm_attendance(text,uuid,text) to anon;
