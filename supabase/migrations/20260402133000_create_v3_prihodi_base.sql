BEGIN;

CREATE TABLE IF NOT EXISTS public.v3_prihodi (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  datum date NOT NULL DEFAULT CURRENT_DATE,
  iznos numeric(12,2) NOT NULL CHECK (iznos >= 0),
  kategorija text NOT NULL DEFAULT 'ostalo',
  opis text,
  nacin_naplate text,
  izvor text,
  putnik_id uuid,
  putnik_ime_prezime text,
  vozac_id uuid,
  za_mesec integer,
  za_godinu integer,
  aktivno boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by text,
  updated_by text,
  source_table text,
  source_id uuid
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_v3_prihodi_source
  ON public.v3_prihodi (source_table, source_id)
  WHERE source_table IS NOT NULL AND source_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_v3_prihodi_datum ON public.v3_prihodi (datum DESC);
CREATE INDEX IF NOT EXISTS ix_v3_prihodi_kategorija ON public.v3_prihodi (kategorija);
CREATE INDEX IF NOT EXISTS ix_v3_prihodi_vozac_id ON public.v3_prihodi (vozac_id);
CREATE INDEX IF NOT EXISTS ix_v3_prihodi_putnik_id ON public.v3_prihodi (putnik_id);
CREATE INDEX IF NOT EXISTS ix_v3_prihodi_aktivno ON public.v3_prihodi (aktivno);

COMMIT;
