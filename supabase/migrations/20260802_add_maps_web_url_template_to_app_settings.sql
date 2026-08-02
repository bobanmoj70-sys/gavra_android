-- Maps web URL template (remote config only; not hardcoded in app binary).
-- Placeholders: {lat} {lng}
ALTER TABLE public.v3_app_settings
  ADD COLUMN IF NOT EXISTS maps_web_url_template text;

COMMENT ON COLUMN public.v3_app_settings.maps_web_url_template IS
  'Optional web maps URL template with {lat} and {lng} placeholders (served at runtime).';

UPDATE public.v3_app_settings
SET
  maps_web_url_template = COALESCE(
    NULLIF(trim(maps_web_url_template), ''),
    'https://www.google.com/maps/search/?api=1&query={lat},{lng}'
  ),
  updated_at = now()
WHERE id = 'global';
