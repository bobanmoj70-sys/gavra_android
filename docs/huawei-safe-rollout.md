# Huawei Safe Rollout (Android)

Ovaj projekat koristi **opt-in** pristup za Huawei kako postojeći GMS/iOS tokovi ne bi bili pogođeni.

## Podrazumevano stanje (bezbedno)

U `android/gradle.properties`:

- `app.enableHuawei=false`
- `app.enableHuaweiFlavorSplit=false`

Sa ovim podešavanjima build ponašanje ostaje isto kao pre Huawei pripreme.

## Uključivanje Huawei podrške (postepeno)

1. Postavi `android/app/agconnect-services.json` (lokalno ili preko CI secret-a).
2. Uključi Huawei:
   - `app.enableHuawei=true`
3. Po potrebi uključi i flavor split:
   - `app.enableHuaweiFlavorSplit=true`

## Komande

### Standardni (postojeći) build

```powershell
Set-Location 'C:\Users\Bojan\gavra_android\android'
.\gradlew.bat :app:compileDebugKotlin --no-daemon --console=plain
```

### Huawei ON, bez flavor split-a

```powershell
Set-Location 'C:\Users\Bojan\gavra_android\android'
.\gradlew.bat :app:compileDebugKotlin -Papp.enableHuawei=true -Papp.enableHuaweiFlavorSplit=false --no-daemon --console=plain
```

### Huawei ON + gms/hms flavor split

```powershell
Set-Location 'C:\Users\Bojan\gavra_android\android'
.\gradlew.bat :app:assembleGmsDebug -Papp.enableHuawei=true -Papp.enableHuaweiFlavorSplit=true --no-daemon --console=plain
.\gradlew.bat :app:assembleHmsDebug -Papp.enableHuawei=true -Papp.enableHuaweiFlavorSplit=true --no-daemon --console=plain
```

## Napomene o sigurnosti

- `android/app/agconnect-services.json` mora ostati van Git-a.
- iOS konfiguracija ostaje netaknuta ovim podešavanjima.
- Ako je `app.enableHuawei=true` a `agconnect-services.json` nedostaje, build namerno pada sa jasnom porukom.
