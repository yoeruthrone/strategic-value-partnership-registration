-- Change the value below, then run once.
insert into public.dashboard_access(id,secret_hash)
values(1,extensions.crypt('GANTI-DENGAN-ADMIN-SECRET',extensions.gen_salt('bf')))
on conflict(id) do update set secret_hash=excluded.secret_hash;
