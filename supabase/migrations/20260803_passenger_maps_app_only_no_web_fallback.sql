-- Putnik: samo maps app deep-link iz remote config-a (nema web fallback u app-u).
-- Vozač navigacija: HERE WeGo (here-route + install URL kolone ostaju).
-- Placeholders: {lat} {lng}

COMMENT ON COLUMN public.v3_app_settings.maps_app_url_template_android IS
  'Passenger only: deep link to open Google Maps app on Android ({lat},{lng}). No web fallback in client.';
COMMENT ON COLUMN public.v3_app_settings.maps_app_url_template_ios IS
  'Passenger only: deep link to open Google Maps app on iOS ({lat},{lng}). No web fallback in client.';
COMMENT ON COLUMN public.v3_app_settings.maps_web_url_template IS
  'Deprecated — client no longer uses web maps fallback. Kept nullable for backward compatibility.';

UPDATE public.v3_app_settings
SET
  maps_app_url_template_android = 'https://www.google.com/maps/search/?api=1&query={lat},{lng}',
  maps_app_url_template_ios = 'comgooglemaps://?q={lat},{lng}',
  maps_web_url_template = NULL,
  updated_at = now()
WHERE id = 'global';
