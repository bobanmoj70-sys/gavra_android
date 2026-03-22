# UTF-8 guard (čćšđž)

Ovaj projekat koristi UTF-8 bez BOM.

## Brza provera

```powershell
python tools/utf8_guard.py --path .
```

## Bezbedan auto-fix

```powershell
python tools/utf8_guard.py --path . --fix
```

## Preporučeni workflow

1. Pokreni `--path .` i vidi šta je problem.
2. Pokreni `--fix`.
3. Ponovo pokreni check i potvrdi da je čisto.
4. Tek onda commit.

## Šta alat proverava

- BOM (`EF BB BF`) u tekstualnim fajlovima
- neispravan UTF-8
- česte mojibake obrasce (`Ã`, `â€`, `ðŸ`, `�`, itd.)

## Šta alat ispravlja (`--fix`)

- uklanja BOM
- radi Unicode normalizaciju (NFC)
- radi osnovne zamene za česte pokvarene srpske znakove i tipografske simbole

Napomena: ako nešto ostane prijavljeno posle `--fix`, to je signal za ručnu proveru konkretnog fajla.
