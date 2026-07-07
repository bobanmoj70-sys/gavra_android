alter table public.v3_finansije
add column if not exists uplate_json jsonb default '[]'::jsonb;

comment on column public.v3_finansije.uplate_json is 'Arhiva svih uplata za mesec sa podacima datum, iznos, ko je naplatio i vreme. Trajno se čuva za istoriju naplate i refundacije.';
