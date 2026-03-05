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

# 1. nav_bar_type iz app settings
settings = get('v2_app_settings?select=id,nav_bar_type')
print('=== v2_app_settings ===')
for s in settings:
    print(' ', s)

# 2. v2_kapacitet_polazaka - svi aktivni termini
kap = get('v2_kapacitet_polazaka?aktivan=eq.true&select=grad,vreme,max_mesta&order=grad.asc,vreme.asc')
print('\n=== kapacitet_polazaka (aktivni) ===')
for r in kap:
    print('  grad=%s vreme=%s max=%s' % (r['grad'], r['vreme'], r['max_mesta']))

# 3. Proveri v2_polasci za cet sa dodeljenm_vreme - sta ima u dodeljeno_vreme
rows = get('v2_polasci?dan=eq.cet&status=eq.odobreno&select=putnik_id,grad,zeljeno_vreme,dodeljeno_vreme&limit=10')
print('\n=== polasci cet/odobreno (first 10) ===')
for r in rows:
    print('  grad=%s zeljeno=%s dodeljeno=%s' % (r['grad'], r['zeljeno_vreme'], r['dodeljeno_vreme']))

# 4. Proveri v2_vozac_raspored - da li postoji raspored za cet
rasp = get('v2_vozac_raspored?select=dan,grad,vreme,vozac_id')
print('\n=== vozac_raspored (svi) ===')
for r in rasp:
    print('  dan=%s grad=%s vreme=%s vozac=%s' % (r['dan'], r['grad'], r['vreme'], r['vozac_id']))
