-- Dopunjuje "uloga" kolonu u v3_auth: dodaje 'putnik' kao validnu vrednost
-- i backfilluje sve naloge gde tip != 'vozac' (putnici) na uloga = 'putnik',
-- umesto pogresnog defaulta 'vozac' koji je greskom upisan svima u prethodnoj migraciji.

alter table public.v3_auth
  drop constraint if exists v3_auth_uloga_check;

alter table public.v3_auth
  add constraint v3_auth_uloga_check check (uloga in ('vozac', 'admin', 'dispecer', 'putnik'));

-- Backfill: svi ne-vozac (putnik) nalozi dobijaju uloga = 'putnik'.
update public.v3_auth
set uloga = 'putnik'
where tip != 'vozac';

comment on column public.v3_auth.uloga is
  'Rola naloga: za vozac-tip naloge je vozac (podrazumevano)/admin/dispecer; za putnik-tip naloge je uvek putnik. Ne utice na login/rutiranje, koje i dalje zavisi od kolone tip.';
