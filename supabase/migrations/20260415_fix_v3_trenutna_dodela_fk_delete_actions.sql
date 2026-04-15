-- Align FK delete actions with NOT NULL columns in v3_trenutna_dodela

alter table public.v3_trenutna_dodela
  drop constraint if exists trenutna_dodela_putnik_auth_id_fkey,
  drop constraint if exists trenutna_dodela_vozac_auth_id_fkey,
  drop constraint if exists v3_trenutna_dodela_termin_id_fkey;

alter table public.v3_trenutna_dodela
  add constraint trenutna_dodela_putnik_auth_id_fkey
    foreign key (putnik_v3_auth_id)
    references public.v3_auth(id)
    on update cascade
    on delete restrict,
  add constraint trenutna_dodela_vozac_auth_id_fkey
    foreign key (vozac_v3_auth_id)
    references public.v3_auth(id)
    on update cascade
    on delete restrict,
  add constraint v3_trenutna_dodela_termin_id_fkey
    foreign key (termin_id)
    references public.v3_operativna_nedelja(id)
    on update cascade
    on delete cascade;
