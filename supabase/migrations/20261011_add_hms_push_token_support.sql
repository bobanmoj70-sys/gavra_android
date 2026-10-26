-- Dodavanje HMS push token podrške za Huawei uređaje
-- HMS se koristi kao alternativa FCM-u na Android uređajima bez Google Play Services

ALTER TABLE public.v3_auth
  ADD COLUMN IF NOT EXISTS push_token_hms text;

ALTER TABLE public.v3_auth
  ADD COLUMN IF NOT EXISTS push_token_hms_2 text;

ALTER TABLE public.v3_auth
  ADD COLUMN IF NOT EXISTS push_token_provider text DEFAULT 'fcm';

COMMENT ON COLUMN public.v3_auth.push_token_hms IS
  'HMS (Huawei Mobile Services) push token za Huawei uređaje bez GMS';

COMMENT ON COLUMN public.v3_auth.push_token_hms_2 IS
  'Sekundarni HMS push token (drugi uređaj istog korisnika)';

COMMENT ON COLUMN public.v3_auth.push_token_provider IS
  'Aktivni push provider: fcm ili hms';

-- Index za brzu pretragu HMS tokena
CREATE INDEX IF NOT EXISTS idx_v3_auth_push_token_hms ON public.v3_auth(push_token_hms) WHERE push_token_hms IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_v3_auth_push_token_hms_2 ON public.v3_auth(push_token_hms_2) WHERE push_token_hms_2 IS NOT NULL;
