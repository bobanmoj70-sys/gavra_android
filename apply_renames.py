"""Ponovo primijeni sve v2-prefix rename-ove na cijeli lib/ direktorij."""
import os
import re

RENAMES = {
    'patchCache':            'v2PatchCache',
    'upsertToCache':         'v2UpsertToCache',
    'removeFromCache':       'v2RemoveFromCache',
    'updatePutnik':          'v2UpdatePutnik',
    'createPutnik':          'v2CreatePutnik',
    'deletePutnik':          'v2DeletePutnik',
    'findPutnikById':        'v2FindPutnikById',
    'findByTelefon':         'v2FindByTelefon',
    'getAllPutnici':          'v2GetAllPutnici',
    'refreshPolasciCache':   'v2RefreshPolasciCache',
    'refreshForNewDay':      'v2RefreshForNewDay',
    'loadStatistikaCache':   'v2LoadStatistikaCache',
    'getPutnikById':         'v2GetPutnikById',
    'getByPin':              'v2GetByPin',
    'getFirma':              'v2GetFirma',
    'upsertFirma':           'v2UpsertFirma',
    'updatePin':             'v2UpdatePin',
    'streamFromCache':       'v2StreamFromCache',
    'nowToString':           'v2NowString',
    'refreshAllActiveStreams': 'v2RefreshStreams',
    'streamPutnici':         'v2StreamPutnici',
}

# startTracking / stopTracking samo za V2DriverLocationService (ne V2RealtimeGpsService)
DRIVER_RENAMES = {
    'startTracking':     'v2StartTracking',
    'stopTracking':      'v2StopTracking',
    'updatePutniciEta':  'v2UpdatePutniciEta',
}

def is_driver_location_file(path):
    return 'v2_driver_location_service' in path or 'v2_vozac_screen' in path

def apply_renames(content, renames):
    for old, new in renames.items():
        # Word-boundary: ne smije biti alfanumerički znak ispred, mora biti ( { < iza
        content = re.sub(
            r'(?<![a-zA-Z0-9_])' + re.escape(old) + r'(?=\s*[\(\{<])',
            new,
            content
        )
    return content

total_files = 0
for root, dirs, files in os.walk('lib'):
    dirs[:] = [d for d in dirs if d != 'build']
    for fname in files:
        if not fname.endswith('.dart'):
            continue
        path = os.path.join(root, fname)
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        new_content = apply_renames(content, RENAMES)
        
        # startTracking/stopTracking samo u driver location fajlovima
        # Ali u v2_vozac_screen, samo V2DriverLocationService pozivi (ne V2RealtimeGpsService)
        if 'v2_driver_location_service' in path:
            new_content = apply_renames(new_content, DRIVER_RENAMES)
        elif 'v2_vozac_screen' in path:
            # Samo linije sa V2DriverLocationService
            lines = new_content.split('\n')
            result = []
            for line in lines:
                if 'V2DriverLocationService' in line:
                    line = apply_renames(line, DRIVER_RENAMES)
                result.append(line)
            new_content = '\n'.join(result)
        
        if new_content != content:
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(new_content)
            total_files += 1
            print(f"  updated: {path}")

print(f"\nUKUPNO: {total_files} fajlova ažurirano")
