alter table if exists public.v3_auth
add column if not exists locale_code text;

comment on column public.v3_auth.locale_code is 'Preferred app locale for localized push notifications (sr, en, ru, de).';