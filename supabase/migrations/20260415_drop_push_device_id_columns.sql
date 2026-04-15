alter table public.v3_auth
  drop column if exists push_device_id,
  drop column if exists push_device_id_2;
