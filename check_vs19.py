import urllib.request, json, ssl, warnings
warnings.filterwarnings('ignore')
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

with open('.env') as f:
    lines = f.readlines()
url = ''; key = ''
for l in lines:
    l = l.strip()
    if l.startswith('SUPABASE_URL='): url = l.split('=', 1)[1]
    elif 'ANON_KEY' in l: key = l.split('=', 1)[1]

h = {'apikey': key, 'Authorization': 'Bearer ' + key}

def get(path):
    r = urllib.request.Request(url + '/rest/v1/' + path, headers=h)
    return json.loads(urllib.request.urlopen(r, context=ctx).read())

# Uzmi putnik_id za VS 19:00 cet
rows = get('v2_polasci?dan=eq.cet&grad=eq.VS&dodeljeno_vreme=eq.19%3A00&select=putnik_id,putnik_tabela')
print('VS 19:00 cet putnici:')
for r in rows:
    pid = r['putnik_id']
    tab = r['putnik_tabela']
    res = get(tab + '?id=eq.' + pid + '&select=id,ime,aktivan')
    print(f'  {tab}: {res}')

print()

# Provjeri getPutnikById - RM kešira sve putnikе u getAllPutnici
# RM koristi v2_radnici + v2_ucenici + v2_dnevni + v2_posiljke
# Provjeri da li su sva tri putnika aktivna
print('Provjera aktivan statusa:')
for r in rows:
    pid = r['putnik_id']
    tab = r['putnik_tabela']
    res = get(tab + '?id=eq.' + pid + '&select=id,ime,aktivan,status')
    if res:
        p = res[0]
        print(f'  {p.get("ime","?")} ({tab}): aktivan={p.get("aktivan")}, status={p.get("status")}')
    else:
        print(f'  ID {pid} NOT FOUND in {tab}!')
