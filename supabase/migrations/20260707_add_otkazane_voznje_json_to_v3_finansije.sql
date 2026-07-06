alter table public.v3_finansije
add column if not exists otkazane_voznje_json jsonb default '[]'::jsonb;

comment on column public.v3_finansije.otkazane_voznje_json is 'Arhiva svih otkazivanja putnika u mesecu sa podacima ko je otkazao, kada, datum, grad i vreme. Trajno se čuva jer se v3_operativna_nedelja briše.';
