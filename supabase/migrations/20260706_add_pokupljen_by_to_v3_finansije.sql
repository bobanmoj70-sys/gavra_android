alter table public.v3_finansije
add column if not exists pokupljen_by uuid references public.v3_auth(id);

comment on column public.v3_finansije.pokupljen_by is 'Vozač koji je fizički pokupio putnika. Čuva se trajno jer se podaci iz v3_operativna_nedelja brišu.';
