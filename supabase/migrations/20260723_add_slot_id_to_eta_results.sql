-- Add slot_id column to v3_eta_results for proper upsert conflict resolution
-- PROBLEM: Multiple slots with same passengers cause UNIQUE(termin_id, putnik_id) conflicts
-- SOLUTION: Add slot_id column and change unique constraint to UNIQUE(slot_id, putnik_id)

-- Step 1: Add slot_id column
ALTER TABLE public.v3_eta_results
ADD COLUMN slot_id UUID REFERENCES public.v3_trenutna_dodela_slot(id) ON DELETE CASCADE;

-- Step 2: Drop old UNIQUE constraint on (termin_id, putnik_id)
ALTER TABLE public.v3_eta_results
DROP CONSTRAINT IF EXISTS "v3_eta_results_termin_id_putnik_id_key";

-- Step 3: Create new UNIQUE constraint on (slot_id, putnik_id)
-- This ensures each passenger has only ONE ETA per slot
ALTER TABLE public.v3_eta_results
ADD CONSTRAINT unique_slot_putnik UNIQUE(slot_id, putnik_id);

-- Step 4: Create index on slot_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_v3_eta_results_slot_id ON public.v3_eta_results(slot_id);

-- Step 5: Update RLS policies if needed
COMMENT ON COLUMN public.v3_eta_results.slot_id IS 'Reference to the slot this ETA result belongs to. Ensures proper isolation between multiple slots.';
