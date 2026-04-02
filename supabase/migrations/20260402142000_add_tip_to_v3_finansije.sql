BEGIN;

ALTER TABLE public.v3_finansije
ADD COLUMN IF NOT EXISTS tip text;

UPDATE public.v3_finansije
SET tip = CASE
  WHEN naziv ILIKE 'Uplata:%' THEN 'prihod'
  WHEN lower(coalesce(kategorija, '')) IN ('voznja', 'uplata') THEN 'prihod'
  ELSE 'rashod'
END
WHERE tip IS NULL;

ALTER TABLE public.v3_finansije
ALTER COLUMN tip SET DEFAULT 'rashod';

ALTER TABLE public.v3_finansije
ALTER COLUMN tip SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'v3_finansije_tip_check'
  ) THEN
    ALTER TABLE public.v3_finansije
    ADD CONSTRAINT v3_finansije_tip_check CHECK (tip IN ('prihod','rashod'));
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS ix_v3_finansije_tip ON public.v3_finansije (tip);
CREATE INDEX IF NOT EXISTS ix_v3_finansije_tip_created_at ON public.v3_finansije (tip, created_at DESC);

COMMIT;
