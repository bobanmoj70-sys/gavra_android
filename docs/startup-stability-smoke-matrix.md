# Startup Stability Smoke Matrix

Cilj: potvrditi stabilan startup i fallback ponašanje pre iOS resubmita.

## Pravila prolaza

- Nijedan scenario ne sme imati crash/force close.
- App mora prikazati UI (`V3WelcomeScreen`) i kada backend servisi kasne ili nisu dostupni.
- Startup ne sme ostati zaglavljen na praznom/crnom ekranu.
- U slučaju greške servisne inicijalizacije, app mora nastaviti sa radom (degradirani režim je dozvoljen).

## Matrica scenarija

| ID | Scenario | Koraci | Očekivano | Rezultat |
|---|---|---|---|---|
| S1 | Cold Start (online) | Ugasiti app potpuno, pokrenuti normalno | UI se pojavi brzo; nema crash | ☐ PASS / ☐ FAIL |
| S2 | Cold Start (spor internet) | Simulirati slab internet, pokrenuti app | UI se pojavi; background init pokušava/retry bez blokade | ☐ PASS / ☐ FAIL |
| S3 | Cold Start (offline) | Isključiti internet, pokrenuti app | UI se pojavi; nema crash; servisi degradirani | ☐ PASS / ☐ FAIL |
| S4 | Resume from background | Otvoriti app, poslati u background, vratiti je | Bez crash; state ostaje validan | ☐ PASS / ☐ FAIL |
| S5 | Push tap launch (killed) | Ugasiti app, tapnuti notifikaciju | App se podigne bez crash i obradi payload/fallback | ☐ PASS / ☐ FAIL |
| S6 | Push tap launch (background) | App u background, tap na notifikaciju | Bez crash; navigacija/fallback radi | ☐ PASS / ☐ FAIL |
| S7 | Token refresh flow | Pokrenuti scenario gde FCM token osveži | Bez crash; token sync ide u pozadini | ☐ PASS / ☐ FAIL |
| S8 | Notification handlers init fail | Simulirati grešku notifikacija | App ostaje funkcionalna; bez rušenja | ☐ PASS / ☐ FAIL |
| S9 | App services init fail | Simulirati pad `app_settings`/update call-a | App nastavlja rad; greška samo logovana | ☐ PASS / ☐ FAIL |
| S10 | Brzi restart x5 | 5 brzih start/kill ciklusa | Nema crash ni degradacije startupa | ☐ PASS / ☐ FAIL |

## iOS fokus (obavezno)

- Testirati minimum:
  - 1 fizički iPhone (preporuka: poslednji iOS)
  - 1 stariji iOS target koji podržavate
- Za svaki FAIL sačuvati:
  - timestamp
  - scenario ID
  - poslednjih 100-200 log linija
  - screenshot/video ako je vizuelni problem

## Završni gate pre resubmita

Resubmit je dozvoljen tek kada:

1. Svi scenariji `S1-S10` su PASS.
2. Nema launch crash-a u iOS testu.
3. Bar jedan test uključuje push tap launch iz `killed` stanja.
4. Nema blokirajućih startup regresija u odnosu na prethodni build.

## Napomena

Ako bilo koji scenario padne, ne raditi resubmit dok se ne popravi i ponovi kompletan smoke za kritične scenarije (`S1`, `S3`, `S5`, `S10`).
