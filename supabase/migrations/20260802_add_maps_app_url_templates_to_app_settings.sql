-- Google Maps (app) deep-link templates — remote config only (not in app binary).
-- Placeholders: {lat} {lng}
ALTER TABLE public.v3_app_settings
  ADD COLUMN IF NOT EXISTS maps_app_url_template_android text,
  ADD COLUMN IF NOT EXISTS maps_app_url_template_ios text,
  ADD COLUMN IF NOT EXISTS maps_web_url_template text;

COMMENT ON COLUMN public.v3_app_settings.maps_app_url_template_android IS
  'Deep link / intent template to open maps app on Android ({lat},{lng}).';
COMMENT ON COLUMN public.v3_app_settings.maps_app_url_template_ios IS
  'Deep link template to open maps app on iOS ({lat},{lng}).';
COMMENT ON COLUMN public.v3_app_settings.maps_web_url_template IS
  'Optional web maps URL template fallback with {lat} and {lng} placeholders.';

UPDATE public.v3_app_settings
SET
  maps_app_url_template_android = COALESCE(
    NULLIF(trim(maps_app_url_template_android), ''),
    'geo:{lat},{lng}?q={lat},{lng}'
  ),
  maps_app_url_template_ios = COALESCE(
    NULLIF(trim(maps_app_url_template_ios), ''),
    'comgooglemaps://?q={lat},{lng}'
  ),
  maps_web_url_template = COALESCE(
    NULLIF(trim(maps_web_url_template), ''),
    'https://www.google.com/maps/search/?api=1&query={lat},{lng}'
  ),
  updated_at = now()
WHERE id = 'global';
