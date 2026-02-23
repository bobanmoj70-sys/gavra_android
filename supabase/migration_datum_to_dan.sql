-- ============================================================
-- MIGRACIJA: datum → dan
-- Datum migracije: 2026-02-23
-- Commits: fd5548b8 (seat_requests), 52f440db (vreme_vozac),
--          5e68c1a2 (get_putnoci_sa_statusom RPC fix)
-- ============================================================
--
-- RAZLOG: Umesto čuvanja konkretnog datuma (npr. 2026-01-06),
-- putnici i vozači su vezani za DAN U NEDELJI (pon, uto, sre, cet, pet, sub, ned).
-- Kolona `datum DATE` je zamenjena kolonom `dan TEXT` u svim relevantnim tabelama.
--
-- TABELE KOJE SU MIGRIRANE:
--   ✅ seat_requests   (datum → dan)
--   ✅ vreme_vozac     (datum → dan)
--
-- TABELE KOJE SU OSTALE SA datum:
--   ✅ voznje_log      (istorijski log, kalendarski datum je neophodan za izveštaje)
--   ✅ daily_reports   (kalendarski datum)
--   ✅ pumpa_punjenja  (kalendarski datum)
--   ✅ pumpa_tocenja   (kalendarski datum)
--   ✅ vozila_istorija (kalendarski datum)
-- ============================================================


-- ============================================================
-- 1. MIGRACIJA: seat_requests
-- ============================================================

-- Dodaj kolonu dan (ako ne postoji)
ALTER TABLE seat_requests
  ADD COLUMN IF NOT EXISTS dan TEXT;

-- Popuni dan iz datum (DOW: 0=ned, 1=pon, ..., 6=sub)
UPDATE seat_requests
SET dan = CASE EXTRACT(DOW FROM datum)
  WHEN 1 THEN 'pon'
  WHEN 2 THEN 'uto'
  WHEN 3 THEN 'sre'
  WHEN 4 THEN 'cet'
  WHEN 5 THEN 'pet'
  WHEN 6 THEN 'sub'
  WHEN 0 THEN 'ned'
END
WHERE datum IS NOT NULL;

-- Ukloni staru kolonu datum
ALTER TABLE seat_requests
  DROP COLUMN IF EXISTS datum;

-- Dodaj CHECK constraint za validne vrednosti
ALTER TABLE seat_requests
  ADD CONSTRAINT seat_requests_dan_check
  CHECK (dan IN ('pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'));

-- Indeks za brže filtriranje po danu
CREATE INDEX IF NOT EXISTS idx_seat_requests_dan
  ON seat_requests (dan);


-- ============================================================
-- 2. MIGRACIJA: vreme_vozac
-- ============================================================

-- Dodaj kolonu dan (ako ne postoji)
ALTER TABLE vreme_vozac
  ADD COLUMN IF NOT EXISTS dan TEXT;

-- Popuni dan iz datum
UPDATE vreme_vozac
SET dan = CASE EXTRACT(DOW FROM datum)
  WHEN 1 THEN 'pon'
  WHEN 2 THEN 'uto'
  WHEN 3 THEN 'sre'
  WHEN 4 THEN 'cet'
  WHEN 5 THEN 'pet'
  WHEN 6 THEN 'sub'
  WHEN 0 THEN 'ned'
END
WHERE datum IS NOT NULL;

-- Ukloni staru kolonu datum
ALTER TABLE vreme_vozac
  DROP COLUMN IF EXISTS datum;

-- Dodaj CHECK constraint za validne vrednosti
ALTER TABLE vreme_vozac
  ADD CONSTRAINT vreme_vozac_dan_check
  CHECK (dan IN ('pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'));

-- Indeks za brže filtriranje po danu
CREATE INDEX IF NOT EXISTS idx_vreme_vozac_dan
  ON vreme_vozac (dan);


-- ============================================================
-- 3. FIX: RPC get_putnoci_sa_statusom
-- ============================================================
-- Funkcija je rewriteovana da koristi sr.dan = v_dan_kratica
-- umesto sr.datum = p_datum (koje više ne postoji).
-- Parametar p_datum DATE je zadržan radi kompatibilnosti sa Flutter klijentom.
-- voznje_log subqueriji koriste vl.datum = p_datum (voznje_log zadržava datum).
-- Puna definicija funkcije se nalazi u supabase/dispecer.sql (sekcija 0).
