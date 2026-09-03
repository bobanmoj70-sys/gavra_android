-- Pazar policy start date (remote config): non-retroactive activation date.
ALTER TABLE public.v3_app_settings
  ADD COLUMN IF NOT EXISTS pazar_policy_start_date date;

COMMENT ON COLUMN public.v3_app_settings.pazar_policy_start_date IS
  'Activation date for mandatory daily pazar input policy (calendar date, Belgrade business logic).';

UPDATE public.v3_app_settings
SET
  pazar_policy_start_date = COALESCE(pazar_policy_start_date, DATE '2026-09-04'),
  updated_at = now()
WHERE id = 'global';
