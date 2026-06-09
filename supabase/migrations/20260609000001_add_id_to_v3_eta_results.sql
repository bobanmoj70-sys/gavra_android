-- Add generated id column to v3_eta_results (id = putnik_id)
-- v3_eta_results has no natural id column; putnik_id is used as the cache key
-- in etaResultsCache (one active ETA per passenger at a time).
ALTER TABLE v3_eta_results ADD COLUMN IF NOT EXISTS id TEXT GENERATED ALWAYS AS (putnik_id) STORED;
