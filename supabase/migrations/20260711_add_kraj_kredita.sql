-- Dodaje opciono polje za datum kraja/zadnje rate kredita.

alter table public.v3_krediti
  add column if not exists kraj_kredita date;

comment on column public.v3_krediti.kraj_kredita is 'Opcioni datum kraja kredita ili zadnje rate.';
