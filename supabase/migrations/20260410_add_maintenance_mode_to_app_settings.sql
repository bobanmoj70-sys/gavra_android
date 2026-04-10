begin;

alter table if exists public.v3_app_settings
  add column if not exists maintenance_mode_android boolean not null default false,
  add column if not exists maintenance_title_android text,
  add column if not exists maintenance_message_android text,
  add column if not exists maintenance_mode_ios boolean not null default false,
  add column if not exists maintenance_title_ios text,
  add column if not exists maintenance_message_ios text;

commit;
