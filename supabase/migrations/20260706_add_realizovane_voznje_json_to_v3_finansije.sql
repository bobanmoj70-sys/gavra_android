alter table public.v3_finansije
add column if not exists realizovane_voznje_json jsonb not null default '[]'::jsonb;

comment on column public.v3_finansije.realizovane_voznje_json is 'Arhiva svih vožnji putnika u mesecu sa podacima ko je pokupio, ko je dodao/ažurirao, datum, grad i vreme. Trajno se čuva jer se v3_operativna_nedelja briše.';
