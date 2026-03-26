# send-push-notification

Supabase Edge funkcija koju `public.notify_push` poziva na:
`/functions/v1/send-push-notification`.

## Šta radi

- prima `POST` payload (`tokens`, `title`, `body`, `data`, `data_only`)
- podržava `provider: fcm` i `provider: hms`
- šalje push preko FCM HTTP v1 (OAuth sa `firebase_admin_sdk` service account)
- šalje push preko HMS API (OAuth client credentials)
- vraća agregirani rezultat (`accepted`, `sent`, `failed`, `by_provider`, `errors`)
- opciono radi deduplikaciju događaja preko `public.push_events` (`event_key` unique)

## Event contract (preporučeno)

Za stabilan dedup šaljite:

- `event_id` (UUID, jedinstven po eventu)
- `type` (npr. `v3_novi_dnevni_zahtev`)
- `entity_id` (npr. `zahtev_id`)
- `recipient_id` (ID korisnika koji prima)

Ako `event_id` nije prosleđen, funkcija koristi fallback ključ:

`type|entity_id|recipient_id`

Dedup je podrazumevano uključen (`dedup=true`). Možete ga ugasiti payload poljem `dedup=false`.

## Secreti

Funkcija prvo čita iz Edge env (`Deno.env`), a ako nije dostupno, koristi `_secrets` iz payload-a koji šalje `public.notify_push`.

Ključevi:

- `firebase_admin_sdk` (JSON service account)
- `huawei_hms_client_id`
- `huawei_hms_client_secret`
- `huawei_oauth_client_id`
- `huawei_oauth_client_secret`
- `huawei_app_id` (fallback je `huawei_oauth_client_id`)

## Deploy

```bash
supabase functions deploy send-push-notification
```

## Lokalni test

```bash
supabase functions serve send-push-notification
```

Primer body:

```json
{
  "tokens": [
    { "token": "abc_fcm", "provider": "fcm" },
    { "token": "abc_hms", "provider": "hms" }
  ],
  "event_id": "5d72f3e6-1b2d-4c7c-9d9f-4f3a2c1e8d55",
  "type": "v3_novi_dnevni_zahtev",
  "entity_id": "zahtev_123",
  "recipient_id": "vozac_001",
  "title": "Test",
  "body": "Poruka",
  "data": { "type": "diagnostic_test" },
  "data_only": true
}
```

## Verifikacija iz baze

Primer SQL poziva:

```sql
SELECT public.notify_push(
  jsonb_build_array(
    jsonb_build_object('token','test-token-fcm','provider','fcm')
  ),
  'TEST',
  'Push dijagnostika',
  jsonb_build_object('type','diagnostic_test','data_only',true)
);
```

Zatim proveriti `net._http_response` i očekivati `status_code = 200` za poziv ka edge funkciji.
