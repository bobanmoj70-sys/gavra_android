# Startup Stability Smoke Results — 2026-05-02

Referenca: `docs/startup-stability-smoke-matrix.md`

## Automatske provere (izvršeno)

- `flutter --version` ✅
- `flutter analyze lib/main.dart lib/screens/v3_welcome_screen.dart` ✅ `No issues found`
- `flutter build apk --debug` ✅ `Built build\app\outputs\flutter-apk\app-debug.apk`
- `flutter doctor -v` ✅ (Windows + Android ok; iOS validacija ostaje ručna na Mac/Xcode)

## Status po scenariju (`S1-S10`)

| ID | Scenario | Status | Napomena |
|---|---|---|---|
| S1 | Cold Start (online) | ⚪ PENDING | Zahteva runtime verifikaciju na uređaju (posebno iOS) |
| S2 | Cold Start (spor internet) | ⚪ PENDING | Ručni mrežni uslovi |
| S3 | Cold Start (offline) | ⚪ PENDING | Ručna provera offline launch-a |
| S4 | Resume from background | ⚪ PENDING | Ručna lifecycle provera |
| S5 | Push tap launch (killed) | ⚪ PENDING | Ručan push test (killed state) |
| S6 | Push tap launch (background) | ⚪ PENDING | Ručan push test (background) |
| S7 | Token refresh flow | ⚪ PENDING | Ručni FCM token refresh scenario |
| S8 | Notification handlers init fail | ✅ PASS (code-hardening) | Startup path je fail-safe; greške se hvataju i ne ruše UI |
| S9 | App services init fail | ✅ PASS (code-hardening) | Init ide u pozadini sa retry/timeout, bez blokade UI |
| S10 | Brzi restart x5 | ⚪ PENDING | Ručni runtime ciklus |

## Zaključak

- **Automatski gate:** PASS (analyze/build/toolchain ok).
- **Pre iOS resubmita obavezno:** ručno zatvoriti `S1-S7` i `S10` na iOS uređaju/simulatoru.
- **Go/No-Go trenutno:** **NO-GO** dok ručni iOS scenariji ne budu PASS.

## Kratka ručna procedura (iOS)

1. Pokreni app 5 puta (cold start) online/offline.
2. Testiraj resume iz background-a.
3. Pošalji test push i tapni iz killed + background stanja.
4. Zabeleži PASS/FAIL po `S1-S10` u istom dokumentu.
