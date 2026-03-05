"""
Brise bezvrijedne inline komentare iz Dart fajlova.
Zadrzava:
  - /// doc komentare
  - // --- / // === separatore sekcija
  - Komentare koji objasnjava ZASTO (sadrze kljucne rijeci)
Brise:
  - Komentare koji opisuju sta kod radi (ocigledni)
  - Zastarjele reference (registrovani_putnici, stari servisi)
  - ??? markere
  - Emoji komentare bez vrijednosti (??, ??, ?? itd.)
  - Inline komentare tipa '// Pozovi metodu', '// Kreira stream' itd.
"""
import os, re

# Cijele linije komentara koje treba obrisati (regex na stripped line)
DELETE_LINE_PATTERNS = [
    # Zastarjele reference
    r'//.*registrovani_putnici',
    r'//.*v2_putnik_stream_service',
    r'//.*RealtimeManager[^2]',
    r'//.*stara tabela',
    r'//.*stari servis',
    r'//.*Faza \d',
    r'//.*nova kolona',
    r'//.*nove kolone',
    r'//.*backward compat',
    # ??? markeri
    r'//\s*\?{2,}',
    # Ocigledni "stas radi" komentari
    r'//\s*(Start|Stop|Init|Kreira|Pozovi|Poziva|Ucitaj|Ucitava|Osvjezi|Osvezava|Refresh|Subscribe|Unsubscribe|Listen|Cancel|Dispose|Clear|Reset|Check|Provjeri|Proveri)\b',
    r'//\s*(GPS tracking inicijalizacija|Realtime|Stream|Cache|Fetch|Load|Save|Update|Delete|Insert)',
    r'//\s*(inicijalizacija|inicijalizuje|inicijalize)',
    # Emoji noise komentari (linija je SAMO komentar sa emojiem)
    r'//\s*[^\w\s]*[\U0001F300-\U0001FFFF\u2600-\u27BF][^\w\s]*\s*$',
    # Komentari koji su samo label bez sadrzaja
    r'//\s*(TODO|FIXME|HACK|NOTE|XXX)\s*$',
    r'//\s*$',  # prazan komentar
]

# Inline komentari (na kraju koda) koje treba obrisati
DELETE_INLINE_PATTERNS = [
    r'\s*//\s*\?{2,}.*$',
    r'\s*//\s*(stara|stari|old|legacy|deprecated|TODO|FIXME|unused).*$',
    r'\s*//\s*[^\w\s]*[\U0001F300-\U0001FFFF\u2600-\u27BF].*$',
]

compiled_line = [re.compile(p, re.IGNORECASE) for p in DELETE_LINE_PATTERNS]
compiled_inline = [re.compile(p, re.IGNORECASE) for p in DELETE_INLINE_PATTERNS]

def should_delete_line(line):
    stripped = line.strip()
    # Mora biti komentar linija (pocinje sa //)
    if not stripped.startswith('//'):
        return False
    # Sacuvaj doc komentare
    if stripped.startswith('///'):
        return False
    # Sacuvaj separatore sekcija
    if re.match(r'^//\s*[─=\-]{4,}', stripped):
        return False
    for pat in compiled_line:
        if pat.search(stripped):
            return True
    return False

def clean_inline(line):
    # Ne diraj doc komentare i linije koje su samo komentari
    stripped = line.strip()
    if stripped.startswith('//'):
        return line
    for pat in compiled_inline:
        line = pat.sub('', line)
    return line

total_removed = 0
total_files = 0

for root, dirs, files in os.walk('lib'):
    dirs[:] = [d for d in dirs if d != 'build']
    for fname in files:
        if not fname.endswith('.dart'):
            continue
        path = os.path.join(root, fname)
        original = open(path, encoding='utf-8').read()
        lines = original.split('\n')
        result = []
        removed = 0
        for line in lines:
            if should_delete_line(line):
                removed += 1
                continue
            cleaned = clean_inline(line)
            result.append(cleaned)
        # Ukloni vissestruke prazne linije
        new_content = re.sub(r'\n{3,}', '\n\n', '\n'.join(result))
        if new_content != original:
            open(path, 'w', encoding='utf-8', newline='').write(new_content)
            total_removed += removed
            total_files += 1
            if removed:
                print(f"  {removed:3d} linija  <- {fname}")

print(f"\nUKUPNO: {total_removed} komentara obrisano iz {total_files} fajlova")
