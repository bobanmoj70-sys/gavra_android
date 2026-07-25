-- Dodaje kolonu "uloga" u v3_auth radi role-based pristupa (admin/dispecer/vozac),
-- odvojeno od kolone "tip" koja i dalje razdvaja vozac/putnik naloge za login.
-- Ovo omogucava da se admin/dispecer privilegije dodeljuju kroz bazu (bez rebuild-a app-a).

alter table public.v3_auth
  add column if not exists uloga text not null default 'vozac';

alter table public.v3_auth
  drop constraint if exists v3_auth_uloga_check;

alter table public.v3_auth
  add constraint v3_auth_uloga_check check (uloga in ('vozac', 'admin', 'dispecer'));

-- Backfill: postojeci hardkodovan admin (Bojan) dobija ulogu 'admin' u bazi.
update public.v3_auth
set uloga = 'admin'
where id = '824f7bd7-e19c-4471-b7a2-d6031d810242' and tip = 'vozac';

comment on column public.v3_auth.uloga is
  'Rola naloga za vozac-tip naloge: vozac (podrazumevano), admin (pun admin panel + vozacke funkcije), dispecer (Home tabla bez admin panela). Nema uticaja na putnik naloge.';
