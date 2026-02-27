-- ============================================================
-- V2 SCHEMA - kreiranje novih tabela u public sa v2_ prefiksom
-- Poslednje azurirano: 2025
-- ============================================================
-- ⚠️  VAŽNO: STARE TABELE SE NE DIRAJU, NE BRIŠU, NE MENJAJU!
--    App je u produkciji i koristi stare tabele sve do refaktora.
--    Ovaj fajl samo KREIRA nove v2_ tabele i kopira podatke.
--    DROP/DELETE/TRUNCATE na starim tabelama je ZABRANJEN.
-- ============================================================

-- ─────────────────────────────────────────────
-- v2_adrese
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_adrese (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  naziv      text NOT NULL,
  grad       text,
  gps_lat    numeric,
  gps_lng    numeric
);

-- ─────────────────────────────────────────────
-- v2_vozaci
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_vozaci (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ime     text NOT NULL,
  telefon text,
  email   text,
  sifra   text,
  boja    text
);

-- ─────────────────────────────────────────────
-- v2_vozila
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_vozila (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  registarski_broj      text,
  marka                 text,
  model                 text,
  godina_proizvodnje    int,
  broj_sasije           text,
  kilometraza           numeric,
  registracija_vazi_do  date,
  mali_servis_datum     date,
  mali_servis_km        numeric,
  veliki_servis_datum   date,
  veliki_servis_km      numeric,
  alternator_datum      date,
  alternator_km         numeric,
  akumulator_datum      date,
  akumulator_km         numeric,
  gume_datum            date,
  gume_opis             text,
  gume_prednje_datum    date,
  gume_prednje_opis     text,
  gume_prednje_km       numeric,
  gume_zadnje_datum     date,
  gume_zadnje_opis      text,
  gume_zadnje_km        numeric,
  plocice_datum         date,
  plocice_km            numeric,
  plocice_prednje_datum date,
  plocice_prednje_km    numeric,
  plocice_zadnje_datum  date,
  plocice_zadnje_km     numeric,
  trap_datum            date,
  trap_km               numeric,
  radio                 text,
  napomena              text
);

-- ─────────────────────────────────────────────
-- v2_radnici
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_radnici (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ime             text NOT NULL,
  status          text,
  telefon         text,
  telefon_2       text,
  adresa_bc_id    uuid REFERENCES public.v2_adrese(id),
  adresa_vs_id    uuid REFERENCES public.v2_adrese(id),
  pin             text,
  email           text,
  cena_po_danu    numeric,
  broj_mesta      int DEFAULT 1,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_ucenici
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_ucenici (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ime             text NOT NULL,
  status          text,
  telefon         text,
  telefon_oca     text,
  telefon_majke   text,
  adresa_bc_id    uuid REFERENCES public.v2_adrese(id),
  adresa_vs_id    uuid REFERENCES public.v2_adrese(id),
  pin             text,
  email           text,
  cena_po_danu    numeric,
  broj_mesta      int DEFAULT 1,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_dnevni
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_dnevni (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ime          text NOT NULL,
  status       text,
  telefon      text,
  telefon_2    text,
  adresa_bc_id uuid REFERENCES public.v2_adrese(id),
  adresa_vs_id uuid REFERENCES public.v2_adrese(id),
  cena         numeric,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_posiljke
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_posiljke (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ime          text,
  status       text,
  telefon      text,
  adresa_bc_id uuid REFERENCES public.v2_adrese(id),
  adresa_vs_id uuid REFERENCES public.v2_adrese(id),
  cena         numeric,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_polasci
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_polasci (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  putnik_id       uuid NOT NULL,
  putnik_tabela   text,
  dan             text,
  grad            text,
  zeljeno_vreme   time,
  dodeljeno_vreme time,
  status          text,
  broj_mesta      int DEFAULT 1,
  adresa_id       uuid REFERENCES public.v2_adrese(id),
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_voznje_log  (samo INSERT, nikad UPDATE/DELETE)
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_voznje_log (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  putnik_id      uuid,
  putnik_ime     text,
  putnik_tabela  text,
  datum          date,
  dan            text,
  grad           text,
  vreme          time,
  tip            text,
  iznos          numeric,
  vozac_id       uuid REFERENCES public.v2_vozaci(id),
  vozac_ime      text,
  detalji        text,
  created_at     timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_vozac_raspored
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_vozac_raspored (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vozac_id   uuid REFERENCES public.v2_vozaci(id),
  dan        text,
  grad       text,
  vreme      time,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_vozac_putnik
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_vozac_putnik (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vozac_id      uuid REFERENCES public.v2_vozaci(id),
  putnik_id     uuid,
  putnik_tabela text,
  dan           text,
  grad          text,
  vreme         time,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_kapacitet_polazaka
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_kapacitet_polazaka (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grad       text,
  vreme      time,
  max_mesta  int,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_push_tokens
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_push_tokens (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token          text UNIQUE NOT NULL,
  provider       text,
  vozac_id       uuid REFERENCES public.v2_vozaci(id),
  putnik_id      uuid,
  putnik_tabela  text,
  updated_at     timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_vozila_servis  (samo INSERT)
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_vozila_servis (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vozilo_id  uuid REFERENCES public.v2_vozila(id),
  tip        text,
  datum      date,
  km         int,
  opis       text,
  cena       numeric,
  pozicija   text,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_pumpa_punjenja
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_pumpa_punjenja (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  datum         date NOT NULL,
  litri         numeric NOT NULL,
  cena_po_litru numeric,
  ukupno_cena   numeric,
  napomena      text,
  created_at    timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_pumpa_tocenja
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_pumpa_tocenja (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  datum      date NOT NULL,
  vozilo_id  uuid REFERENCES public.v2_vozila(id),
  litri      numeric NOT NULL,
  km_vozila  int,
  napomena   text,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_pumpa_config
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_pumpa_config (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kapacitet_litri  numeric NOT NULL,
  alarm_nivo       numeric NOT NULL,
  pocetno_stanje   numeric NOT NULL,
  updated_at       timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_finansije_troskovi
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_finansije_troskovi (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  naziv      text NOT NULL,
  tip        text,
  iznos      numeric,
  mesecno    boolean,
  aktivan    boolean,
  vozac_id   uuid REFERENCES public.v2_vozaci(id),
  mesec      int,
  godina     int,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_app_settings
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_app_settings (
  id                text PRIMARY KEY,
  min_version       text,
  latest_version    text,
  store_url_android text,
  store_url_huawei  text,
  store_url_ios     text,
  nav_bar_type      text,
  updated_at        timestamptz DEFAULT now(),
  updated_by        text
);

-- ─────────────────────────────────────────────
-- v2_pin_zahtevi
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_pin_zahtevi (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  putnik_id     uuid NOT NULL,
  putnik_tabela text,
  email         text,
  telefon       text,
  status        text NOT NULL,
  created_at    timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_pumpa_stanje  (VIEW - izvedeno iz config+punjenja+tocenja)
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v2_pumpa_stanje AS
SELECT
  c.kapacitet_litri,
  c.alarm_nivo,
  c.pocetno_stanje,
  COALESCE((SELECT SUM(litri) FROM public.v2_pumpa_punjenja), 0)                           AS ukupno_punjeno,
  COALESCE((SELECT SUM(litri) FROM public.v2_pumpa_tocenja), 0)                            AS ukupno_utroseno,
  c.pocetno_stanje
    + COALESCE((SELECT SUM(litri) FROM public.v2_pumpa_punjenja), 0)
    - COALESCE((SELECT SUM(litri) FROM public.v2_pumpa_tocenja), 0)                        AS trenutno_stanje,
  ROUND(
    (c.pocetno_stanje
      + COALESCE((SELECT SUM(litri) FROM public.v2_pumpa_punjenja), 0)
      - COALESCE((SELECT SUM(litri) FROM public.v2_pumpa_tocenja), 0)
    ) / NULLIF(c.kapacitet_litri, 0) * 100, 1
  )                                                                                         AS procenat_pune
FROM public.v2_pumpa_config c
LIMIT 1;

-- ─────────────────────────────────────────────
-- v2_racun_sequence
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_racun_sequence (
  godina         integer NOT NULL,
  poslednji_broj integer DEFAULT 0,
  updated_at     timestamptz DEFAULT now(),
  PRIMARY KEY (godina)
);

-- ─────────────────────────────────────────────
-- v2_vozac_lokacije
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_vozac_lokacije (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vozac_id       uuid REFERENCES public.v2_vozaci(id),
  lat            numeric,
  lng            numeric,
  grad           text,
  vreme_polaska  text,
  smer           text,
  putnici_eta    jsonb,
  aktivan        boolean,
  updated_at     timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- v2_weather_alerts_log  (samo INSERT, nikad UPDATE/DELETE)
-- ─────────────────────────────────────────────
CREATE TABLE public.v2_weather_alerts_log (
  id         bigserial PRIMARY KEY,
  alert_date date NOT NULL UNIQUE,
  alert_types text,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────
-- RLS - anon_all policy za sve v2_ tabele
-- ─────────────────────────────────────────────
DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'v2_adrese','v2_vozaci','v2_vozila','v2_radnici','v2_ucenici','v2_dnevni','v2_posiljke',
    'v2_polasci','v2_voznje_log','v2_vozac_raspored','v2_vozac_putnik','v2_kapacitet_polazaka',
    'v2_push_tokens','v2_vozila_servis','v2_pumpa_punjenja','v2_pumpa_tocenja','v2_pumpa_config',
    'v2_finansije_troskovi','v2_app_settings','v2_pin_zahtevi','v2_vozac_lokacije',
    'v2_racun_sequence','v2_weather_alerts_log'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY "anon_all" ON public.%I FOR ALL TO anon USING (true) WITH CHECK (true)',
      t
    );
  END LOOP;
END $$;
