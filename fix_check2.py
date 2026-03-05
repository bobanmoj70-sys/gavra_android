import urllib.request, json, ssl, warnings
warnings.filterwarnings('ignore')
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

with open('.env', 'r') as f:
    lines = f.readlines()
url = ''; key = ''
for line in lines:
    line = line.strip()
    if line.startswith('SUPABASE_URL='):
        url = line.split('=',1)[1].strip()
    elif 'ANON_KEY' in line:
        key = line.split('=',1)[1].strip()

headers = {'apikey': key, 'Authorization': 'Bearer ' + key}

def get(path):
    req = urllib.request.Request(url + '/rest/v1/' + path, headers=headers)
    with urllib.request.urlopen(req, context=ctx) as r:
        return json.loads(r.read())

# Simuliraj tacno sta radi getPutniciByDayIso za danas (cet)
# Filter 1: dan == 'cet'
# Filter 2: status != 'bez_polaska'
# Filter 3 (u build): status != 'obrada' i != 'bez_polaska'
# Filter 4 (u build): polazak.isNotEmpty
# Filter 5 (u build): grad.isNotEmpty
# Filter 6 (u build): isGradMatch(grad, adresa, _selectedGrad)
# Filter 7 (u build): normalizeTime(polazak) == normalizedVreme (_selectedVreme)

# Dohvati sve polasci za cet koji prolaze filter 1+2
rows = get('v2_polasci?dan=eq.cet&select=id,putnik_id,putnik_tabela,grad,zeljeno_vreme,dodeljeno_vreme,status')

print('=== Simulacija filtera ===')
print('Ukupno za cet (svi statusi):', len(rows))

# Filter po statusima koji ulaze u cache
cache_statusi = {'obrada','odobreno','otkazano','odbijeno','bez_polaska','pokupljen'}
rows_u_cache = [r for r in rows if r['status'] in cache_statusi]
print('U cache (status filter):', len(rows_u_cache))

# Filter 1 u build: izbaci obrada i bez_polaska  
rows_za_prikaz = [r for r in rows_u_cache if r['status'] not in ('obrada', 'bez_polaska')]
print('Posle build filter (bez obrada/bez_polaska):', len(rows_za_prikaz))

# Filter dodeljeno_vreme - koliko ima None/null
dodeljeno_none = [r for r in rows_za_prikaz if not r.get('dodeljeno_vreme')]
print('Sa dodeljeno_vreme=None:', len(dodeljeno_none))
if dodeljeno_none:
    for r in dodeljeno_none[:5]:
        print('  ', r)

# Distribucija dodeljeno_vreme vrednosti
from collections import Counter
vremena = Counter(r.get('dodeljeno_vreme') for r in rows_za_prikaz)
print('\nDodeljeno vreme distribucija:')
for v, cnt in sorted(vremena.items()):
    print('  %s: %d' % (v, cnt))

# Filter 7: koji statusi imaju grad
gradovi = Counter(r['grad'] for r in rows_za_prikaz)
print('\nGrad distribucija:', dict(gradovi))

# Kljucno: da li polazak (dodeljeno_vreme) moze biti prazan string ili None
# Sto bi ga izbacilo iz prikaza
empty_dodeljeno = [r for r in rows_za_prikaz if r.get('dodeljeno_vreme') in (None, '', '---')]
print('\nBez dodeljeno_vreme (None/empty/---):', len(empty_dodeljeno))
