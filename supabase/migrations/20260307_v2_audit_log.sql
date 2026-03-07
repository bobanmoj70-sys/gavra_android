-- ============================================================================
-- v2_audit_log — Audit trail za sve akcije vozača i putnika
-- Ko je uradio šta, kada, nad kojim putnikom, i koji je kontekst
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.v2_audit_log (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,

  -- Tip akcije (enum-like string)
  -- VOZAČ:  pokupljen | otkazano_vozac | naplata | odobren_zahtev | odbijen_zahtev |
  --         dodat_putnik | dodat_termin | uklonjen_termin | dodeljen_vozac |
  --         uklonjen_vozac | bez_polaska_globalni | promena_sifre
  -- PUTNIK: zahtev_poslan | zahtev_otkazan | alternativa_prihvacena |
  --         odsustvo_postavljeno | odsustvo_uklonjen | putnik_logout
  -- UPLATA: uplata_dodana
  tip          TEXT NOT NULL,

  -- Ko je uradio akciju
  aktor_id     TEXT,          -- UUID vozača ili putnik_id
  aktor_ime    TEXT,          -- snapshot imena (npr. 'Bojan', 'Petar Petrić')
  aktor_tip    TEXT,          -- 'vozac' | 'putnik' | 'admin'

  -- Na koga se odnosi (nullable za globalne akcije poput bez_polaska_globalni)
  putnik_id    TEXT,
  putnik_ime   TEXT,          -- snapshot (ne FK — putnik se može obrisati)
  putnik_tabela TEXT,         -- 'v2_radnici' | 'v2_ucenici' | 'v2_dnevni' | 'v2_posiljke'

  -- Kontekst polaska
  dan          TEXT,          -- 'pon' | 'uto' | 'sre' | 'cet' | 'pet' | 'sub' | 'ned'
  grad         TEXT,          -- 'BC' | 'VS'
  vreme        TEXT,          -- '07:00'
  polazak_id   TEXT,          -- UUID reda iz v2_polasci (za precizno praćenje)

  -- Detalji promjene
  staro        JSONB,         -- stanje PRIJE (npr. {'status': 'obrada'})
  novo         JSONB,         -- stanje POSLIJE (npr. {'status': 'pokupljen'})
  detalji      TEXT,          -- human-readable opis akcije

  -- Metapodaci
  created_at   TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indeksi za brzo pretraživanje po najčešćim osovinama
CREATE INDEX IF NOT EXISTS idx_v2_audit_log_putnik     ON public.v2_audit_log (putnik_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_v2_audit_log_aktor      ON public.v2_audit_log (aktor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_v2_audit_log_tip        ON public.v2_audit_log (tip, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_v2_audit_log_created_at ON public.v2_audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_v2_audit_log_polazak_id ON public.v2_audit_log (polazak_id) WHERE polazak_id IS NOT NULL;

-- ============================================================================
-- RLS POLITIKE
-- ============================================================================

ALTER TABLE public.v2_audit_log ENABLE ROW LEVEL SECURITY;

-- INSERT: dozvoljeno svima (anon + authenticated) — app piše bez auth-a
CREATE POLICY "v2_audit_log_insert"
  ON public.v2_audit_log
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- SELECT: dozvoljeno svima — app čita za prikaz historije
CREATE POLICY "v2_audit_log_select"
  ON public.v2_audit_log
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- UPDATE / DELETE: zabranjeno — audit log je nepromjenljiv
-- (nema CREATE POLICY za UPDATE/DELETE → defaultno denied)

-- ============================================================================
-- REALTIME: uključiti za tabelu (run u Supabase dashboard ili API)
-- ALTER TABLE public.v2_audit_log REPLICA IDENTITY FULL;
-- Realtime se uključuje iz Supabase Dashboard → Database → Replication
-- ============================================================================
