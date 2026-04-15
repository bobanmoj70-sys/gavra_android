alter table public.v3_auth
  add column if not exists os_device_id text,
  add column if not exists os_device_id_2 text;

comment on column public.v3_auth.os_device_id is 'OS-level device identifier for primary slot (androidId/IDFV when available).';
comment on column public.v3_auth.os_device_id_2 is 'OS-level device identifier for secondary slot (androidId/IDFV when available).';
