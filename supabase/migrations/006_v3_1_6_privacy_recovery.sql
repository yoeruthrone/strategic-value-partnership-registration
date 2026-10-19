-- V3.1.6: safer QR recovery + privacy-limited external viewer
-- Additive/data-safe migration. Existing events and registrations are preserved.

-- Recovery now requires BOTH phone and email to match the same registration.
drop function if exists public.v3_public_recover_ticket(text,text);

create or replace function public.v3_public_recover_ticket(p_slug text,p_phone text,p_email text)
returns jsonb
language plpgsql
security definer
set search_path=public
stable
as $$
declare
  e public.events%rowtype;
  r public.registrations%rowtype;
  v_phone text := public.v3_norm_phone(p_phone);
  v_email text := public.v3_norm_email(p_email);
begin
  if coalesce(v_phone,'')='' or coalesce(v_email,'')='' then return null; end if;
  select * into e from public.events where slug=lower(trim(p_slug));
  if e.id is null then return null; end if;

  select * into r
  from public.registrations
  where event_id=e.id
    and phone=v_phone
    and email=v_email
  limit 1;

  if r.id is null then return null; end if;
  return jsonb_build_object(
    'id',r.id,
    'full_name',r.full_name,
    'phone',r.phone,
    'email',r.email,
    'qr_token',r.qr_token,
    'attendance_status',r.attendance_status,
    'checked_in_at',r.checked_in_at
  );
end $$;

grant execute on function public.v3_public_recover_ticket(text,text,text) to anon;

-- External viewer only exposes operational attendance fields.
-- Phone is masked server-side so raw phone/email/custom_data never enter the viewer payload.
create or replace function public.v3_external_view(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=public
stable
as $$
declare
  e public.events%rowtype;
begin
  select * into e
  from public.events
  where external_token=p_token and external_view_enabled=true;

  if e.id is null then return null; end if;

  return jsonb_build_object(
    'event',jsonb_build_object(
      'name',e.name,
      'slug',e.slug,
      'event_date',e.event_date,
      'logo_data_url',e.logo_data_url,
      'banner_data_url',e.banner_data_url,
      'background_data_url',e.background_data_url
    ),
    'stats',jsonb_build_object(
      'total',(select count(*) from public.registrations where event_id=e.id),
      'attended',(select count(*) from public.registrations where event_id=e.id and attendance_status='ATTENDED'),
      'not_attended',(select count(*) from public.registrations where event_id=e.id and attendance_status<>'ATTENDED')
    ),
    'participants',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'created_at',r.created_at,
        'full_name',r.full_name,
        'phone',repeat('•',greatest(char_length(coalesce(r.phone,''))-4,0)) || right(coalesce(r.phone,''),4),
        'attendance_status',r.attendance_status,
        'checked_in_at',r.checked_in_at
      ) order by r.created_at desc)
      from public.registrations r
      where event_id=e.id
    ),'[]'::jsonb)
  );
end $$;

grant execute on function public.v3_external_view(text) to anon;
