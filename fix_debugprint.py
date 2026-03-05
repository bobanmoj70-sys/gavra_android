"""
Uklanja sve debugPrint pozive iz Dart fajlova, uključujući višelinijske pozive.
Zadržava SAMO debugPrint('❌ ...) i debugPrint("❌ ...).
"""
import re
import os

TARGET_FILES = [
    'lib/main.dart',
    'lib/services/realtime/v2_master_realtime_manager.dart',
    'lib/services/v2_polasci_service.dart',
    'lib/services/v2_huawei_push_service.dart',
    'lib/services/v2_local_notification_service.dart',
    'lib/services/v2_push_token_service.dart',
    'lib/services/v2_statistika_istorija_service.dart',
    'lib/services/v2_firebase_service.dart',
    'lib/services/v2_auth_manager.dart',
    'lib/services/v2_finansije_service.dart',
    'lib/services/v2_pumpa_service.dart',
    'lib/services/v2_driver_location_service.dart',
    'lib/services/v2_putnici_service.dart',
    'lib/services/v2_realtime_notification_service.dart',
    'lib/services/v2_weather_alert_service.dart',
    'lib/services/v2_battery_optimization_service.dart',
    'lib/screens/v2_putnik_profil_screen.dart',
    'lib/screens/v2_welcome_screen.dart',
]

def remove_debug_prints(content):
    lines = content.split('\n')
    result = []
    i = 0
    removed = 0
    
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # Provjeri je li ovo početak debugPrint poziva
        if re.match(r'^\s*debugPrint\(', line):
            # Provjeri je li error print (zadržati)
            if re.match(r'''\s*debugPrint\(['"]❌''', line):
                result.append(line)
                i += 1
                continue
            
            # Nije error — treba ukloniti
            # Broji zagrade da nađemo kraj poziva
            depth = 0
            j = i
            while j < len(lines):
                for ch in lines[j]:
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                        if depth == 0:
                            break
                if depth == 0:
                    break
                j += 1
            
            removed += (j - i + 1)
            i = j + 1  # preskoči cijeli poziv
            continue
        
        # Provjeri je li ovo "visiseća" linija ostatak prethodno parcijalno uklonjenog debugPrint
        # Pattern: linija počinje sa string literalom ili ); bez prethodnog koda
        # Ove linije su nastale jer je prethodni pass uklonio samo prvu liniju
        if re.match(r"""^\s+['"][^'"]*['"],?\s*$""", line) or re.match(r'^\s+\);\s*$', line):
            # Provjeri je li prethodna ne-prazna linija bila zatvorena (nije ostala od koda)
            # Heuristika: ako prethodna linija u result-u završava sa '{' ili '=>' ili ';' ili ')' 
            # onda ovo NIJE visiseća linija od debugPrint
            prev_meaningful = next((r for r in reversed(result) if r.strip()), '')
            prev_stripped = prev_meaningful.strip()
            
            # Visiseća linija od debugPrint tipično dolazi iza:
            # - zatvorene viticast zagrade IF bloka: } 
            # - linije koja završava sa ); (prethodni statement)
            # ali NIJE iza linije koja završava sa '(' (početak novog poziva koji NIJE debugPrint)
            if (prev_stripped.endswith('{') or prev_stripped.endswith('}') or 
                prev_stripped.endswith(';') or prev_stripped == ''):
                # Dodatna provjera — string literal bez konteksta, sigurno visiseća
                if re.match(r"""^\s+['"].*['"],\s*$""", line) and not prev_stripped.endswith('('):
                    removed += 1
                    i += 1
                    continue
                # ); bez prethodnog otvorenog poziva
                if re.match(r'^\s+\);\s*$', line) and not prev_stripped.endswith('(') and not prev_stripped.endswith(','):
                    removed += 1
                    i += 1
                    continue
        
        result.append(line)
        i += 1
    
    return '\n'.join(result), removed

total_removed = 0
# Skeniraj cijeli lib/ direktorij
all_files = []
for root, dirs, files in os.walk('lib'):
    dirs[:] = [d for d in dirs if d != 'build']
    for fname in files:
        if fname.endswith('.dart'):
            all_files.append(os.path.join(root, fname).replace('\\', '/'))

for filepath in all_files:
    if not os.path.exists(filepath):
        continue
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    new_content, removed = remove_debug_prints(content)
    
    # Ukloni višestruke prazne linije (max 2 uzastopne)
    new_content = re.sub(r'\n{3,}', '\n\n', new_content)
    
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8', newline='') as f:
            f.write(new_content)
        print(f"{removed:3d} uklonjeno  <- {filepath}")
        total_removed += removed

print(f"\nUKUPNO: {total_removed} debugPrint uklonjeno")
