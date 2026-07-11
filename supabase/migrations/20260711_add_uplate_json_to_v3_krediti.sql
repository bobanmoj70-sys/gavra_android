alter table public.v3_krediti
add column if not exists uplate_json jsonb default '[]'::jsonb;

comment on column public.v3_krediti.uplate_json is
  'Istorija svih uplata na kredit sa datumom, iznosom i opcionom napomenom.';
