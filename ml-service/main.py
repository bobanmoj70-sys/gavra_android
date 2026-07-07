from fastapi import FastAPI, HTTPException, Depends, Request, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel
import ollama
from supabase._async.client import create_client as create_async_client, AsyncClient
import os
import sys
import sqlite3
import json
import asyncio
from datetime import datetime
import numpy as np
from dotenv import load_dotenv
from collections import deque

# Učitavanje .env pre bilo kakve druge inicijalizacije
load_dotenv()

# Rekonfigurisanje standardnog izlaza za UTF-8 podršku na Windows-u radi sprečavanja UnicodeEncodeError rušenja
if sys.platform.startswith('win'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except AttributeError:
        pass  # Starije verzije Pythona

# --- KONFIGURACIJA IZ ENVIRONMENTA ---
SUPABASE_URL = os.environ.get('SUPABASE_URL')
SUPABASE_SERVICE_ROLE_KEY = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
SUPABASE_ANON_KEY = os.environ.get('SUPABASE_ANON_KEY')
ML_API_KEY = os.environ.get('ML_API_KEY')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL', 'llama3.2')
PORT = int(os.environ.get('PORT', '8000'))

# Backend mora čitati sve tabele, pa preferiramo SERVICE_ROLE_KEY (zaobilazi RLS).
# Ako nije definisan, fallback na ANON_KEY (može biti ograničen RLS pravilima).
SUPABASE_KEY = SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError('SUPABASE_URL i SUPABASE_SERVICE_ROLE_KEY (ili SUPABASE_ANON_KEY) moraju biti definisani u .env fajlu')

if not ML_API_KEY:
    raise RuntimeError('ML_API_KEY mora biti definisan u .env fajlu radi zaštite endpointa')

# Lokalne SQLite baze
DB_FILE = os.path.join(os.path.dirname(__file__), "gavra_ai.db")

app = FastAPI(title="Gavra Realtime AI Backend")

# CORS podrška za komunikaciju sa mobilnim i drugim klijentima
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,  # '*' origins nije dozvoljen sa credentials=True; koristimo X-API-Key header
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- PYDANTIC MODELI ZA API ENDPOINTE ---
class LogResponse(BaseModel):
    logs: list[str]


class InsightResponse(BaseModel):
    insights: list[dict]


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    response: str
    sources: list[str]


# Globalni objekti
supabase: AsyncClient = None
embedder = None
live_logs = deque(maxlen=200)  # Thread-safe zahvaljujući GIL-u, ograničeno na poslednjih 200 logova
realtime_task = None
analysis_lock = asyncio.Lock()
# Izolovana istorija razgovora po sesiji (ključ: session_id)
conversation_history: dict[str, deque] = {}
# Debounce za realtime analizu — sprečava preopterećenje pri velikom broju izmena
last_analysis_time = 0.0
ANALYSIS_DEBOUNCE_SECONDS = 60
# Rate limiter za /chat: maksimalno 10 poziva po minuti po sesiji
chat_rate_limits: dict[str, deque] = {}
CHAT_RATE_LIMIT_MAX = 10
CHAT_RATE_LIMIT_WINDOW_SECONDS = 60
# Praćenje poslednje aktivnosti sesije za čišćenje starih sesija
session_last_activity: dict[str, float] = {}
SESSION_INACTIVITY_TIMEOUT_SECONDS = 3600  # 1 sat

api_key_header = APIKeyHeader(name='X-API-Key', auto_error=False)
session_id_header = APIKeyHeader(name='X-Session-ID', auto_error=False)


def _normalize_session_id(session_id: str | None) -> str:
    return session_id or 'default'


def _cleanup_inactive_sessions():
    """Briše sesije koje nisu aktivne duže od SESSION_INACTIVITY_TIMEOUT_SECONDS."""
    now = datetime.now().timestamp()
    cutoff = now - SESSION_INACTIVITY_TIMEOUT_SECONDS
    stale_sessions = [sid for sid, last in session_last_activity.items() if last < cutoff]
    for sid in stale_sessions:
        conversation_history.pop(sid, None)
        chat_rate_limits.pop(sid, None)
        session_last_activity.pop(sid, None)


def _get_or_create_session_history(session_id: str | None) -> deque:
    """Vraća konverzacijsku memoriju za datu sesiju."""
    sid = _normalize_session_id(session_id)
    _cleanup_inactive_sessions()
    session_last_activity[sid] = datetime.now().timestamp()
    if sid not in conversation_history:
        conversation_history[sid] = deque(maxlen=20)
    return conversation_history[sid]


def _check_chat_rate_limit(session_id: str | None) -> bool:
    """Proverava da li sesija premašuje dozvoljen broj chat poziva u vremenskom prozoru."""
    sid = _normalize_session_id(session_id)
    now = datetime.now().timestamp()
    window_start = now - CHAT_RATE_LIMIT_WINDOW_SECONDS
    
    _cleanup_inactive_sessions()
    session_last_activity[sid] = now
    
    if sid not in chat_rate_limits:
        chat_rate_limits[sid] = deque()
    
    history = chat_rate_limits[sid]
    # Ukloni stare zapise izvan prozora
    while history and history[0] < window_start:
        history.popleft()
    
    if len(history) >= CHAT_RATE_LIMIT_MAX:
        return False
    
    history.append(now)
    return True


# --- AUTENTIKACIJA ---
async def verify_api_key(request: Request, api_key: str = Depends(api_key_header)):
    # Dozvoljavamo root health check bez ključa
    if request.url.path == '/':
        return True
    if api_key != ML_API_KEY:
        raise HTTPException(status_code=401, detail='Nevažeći API ključ')
    return True

# Primena auth zavisnosti na sve endpointe osim root-a
app.router.dependencies.append(Depends(verify_api_key))

# --- INICIJALIZACIJA LOKALNE SQLite BAZE ---
def init_local_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # WAL režim omogućava istovremen pristup više worker-a bez čestih 'database is locked' grešaka
    cursor.execute('PRAGMA journal_mode=WAL;')
    cursor.execute('PRAGMA synchronous=NORMAL;')
    
    # Brana baza znanja
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS ai_knowledge_base (
            id TEXT PRIMARY KEY,
            source_table TEXT,
            source_id TEXT,
            content TEXT,
            embedding TEXT,  -- JSON niz brojeva
            updated_at TEXT
        )
    ''')
    
    # Samostalni zaključci (automatski generisane anomalije i korelacije)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS ai_insights (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            description TEXT,
            source_table TEXT,
            source_id TEXT,
            severity TEXT, -- 'nominal', 'significant', 'critical'
            created_at TEXT
        )
    ''')
    
    # Tabela koja prati status sinhronizacije
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sync_status (
            key TEXT PRIMARY KEY,
            val TEXT
        )
    ''')
    
    # Indeksi za bržu pretragu
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_kb_table ON ai_knowledge_base(source_table)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_kb_content ON ai_knowledge_base(content)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_insights_severity ON ai_insights(severity)')
    
    conn.commit()
    conn.close()

def log_event(message: str):
    """Zapisuje događaj u memorijski log i konzolu"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    log_line = f"[{timestamp}] {message}"
    try:
        print(log_line)
    except Exception:
        try:
            cleaned_line = log_line.encode(sys.stdout.encoding or 'utf-8', errors='replace').decode(sys.stdout.encoding or 'utf-8')
            print(cleaned_line)
        except Exception:
            try:
                print(log_line.encode('ascii', errors='ignore').decode('ascii'))
            except Exception:
                pass
    live_logs.append(log_line)

# --- DETALJNE FAZNE PREVODILAČKE FUNKCIJE ZA SVAKU TABELU ---
def parse_row_to_text(table_name: str, row: dict) -> str:
    """Konvertuje sirovi red iz bilo koje Supabase tabele u jasan strukturni opis za LLM"""
    if not row:
        return ""
    
    try:
        # 1. Finansije
        if table_name == "v3_finansije":
            tip = row.get("tip", "rashod").upper()
            naziv = row.get("naziv", "Bez naziva")
            iznos = row.get("iznos", 0)
            kategorija = row.get("kategorija", "Opšte")
            isplata_iz = row.get("isplata_iz", "pazar")
            mesec = row.get("mesec", "")
            godina = row.get("godina", "")
            return f"Finansije ({tip}): Transakcija '{naziv}' iznosi {iznos} RSD. Kategorija: {kategorija}. Isplata izvršena iz: '{isplata_iz}'. Period: obuhvata mesec {mesec}/{godina}."

        # 2. Zahtevi vožnji
        elif table_name == "v3_zahtevi":
            putnik_id = row.get("created_by") or row.get("putnik_id", "nepoznato")
            grad = row.get("grad", "nepoznato")
            datum = row.get("datum", "")
            vreme = row.get("trazeni_polazak_at", "")
            status = row.get("status", "obrada").upper()
            polazak_at = row.get("polazak_at") or "nije dodeljen"
            return f"Zahtev za vožnju: Putnik sa ID {putnik_id} je podneo zahtev za datum {datum}. Relacija/Grad: {grad}. Traženo vreme polaska: u {vreme}. Trenutni status zahteva: {status}. Konačno dodeljeno vreme polaska: {polazak_at}."

        # 3. Gorivo
        elif table_name == "v3_gorivo":
            vozilo_id = row.get("vozilo_id", "nepoznato")
            iznos = row.get("iznos", 0)
            litara = row.get("litara", 0)
            km_sat = row.get("km_sat", 0)
            kartica = "da" if row.get("kartica") else "ne"
            by = row.get("kreirano_by", "uneto od strane vozača")
            return f"Sipanje goriva: U vozilo ID {vozilo_id} je sipano {litara} litara goriva u vrednosti od {iznos} RSD. Stanje kilometar sata pri sipanju: {km_sat} km. Plaćeno karticom: {kartica}. Evidentirao: {by}."

        # 4. Adrese
        elif table_name == "v3_adrese":
            naziv = row.get("naziv", "Bez naziva")
            ulica = row.get("ulica", "")
            broj = row.get("broj", "")
            grad = row.get("grad", "")
            lat = row.get("lat", "")
            lng = row.get("lng", "")
            return f"Adresa u sistemu: Naziv '{naziv}', ulica i broj: {ulica} {broj}, grad: {grad}. Geografske koordinate su Latitudu {lat} i Longitudu {lng}."

        # 5. Korisnici (Auth)
        elif table_name == "v3_auth":
            ime = row.get("ime", "Neznano ime")
            telefon = row.get("telefon", "")
            tip = row.get("tip", "korisnik").upper()
            cena_dan = row.get("cena_po_danu", 0)
            telefon2 = row.get("telefon_2", "")
            return f"Korisnički profil/Nalog ({tip}): Ime: {ime}, Primarni telefon: {telefon}, Rezervni telefon: {telefon2}. Cena po danu ugovorena: {cena_dan} RSD."

        # 6. Vozila
        elif table_name == "v3_vozila":
            naziv = row.get("naziv", "Neznato vozilo")
            tablica = row.get("registracija", "Bez tablica")
            opis = row.get("opis", "Nema opisa")
            return f"Vozilo u voznom parku: Naziv modela '{naziv}', registarska oznaka: {tablica}. Opisne beleške o vozilu: {opis}."

        # 7. Računi
        elif table_name == "v3_racuni":
            naziv = row.get("naziv", "Bez naziva")
            stanje = row.get("stanje", 0)
            tip = row.get("tip", "neoznačeno")
            return f"Bankovni/Zvanični račun: Naziv računa '{naziv}', trenutno zabeleženo stanje na računu: {stanje} RSD. Tip računa: {tip}."

        # 8. Operativna nedelja (Plan vožnji)
        elif table_name == "v3_operativna_nedelja":
            dan = row.get("dan", "Neznatni dan")
            vreme = row.get("vreme") or row.get("polazak_at", "")
            putnik_id = row.get("putnik_id") or "nepoznat"
            vozac_id = row.get("vozac_id") or "nedodeljen"
            vozilo_id = row.get("vozilo_id") or "nedodeljeno"
            pravac = row.get("pravac", "polazak")
            return f"Operativni plan i raspored: Dan u nedelji: {dan}, Smer/Pravac: {pravac}, Vreme rasporeda: {vreme}. Putnik ID: {putnik_id}, Vozač ID: {vozac_id}, Korišćeno vozilo ID: {vozilo_id}."

        # 9. Trenutna dodela (aktivna dodela putnika na termin)
        elif table_name == "v3_trenutna_dodela":
            putnik_id = row.get("putnik_id") or "nepoznat"
            termin_id = row.get("termin_id") or "nepoznat"
            vozac_id = row.get("vozac_id") or "nedodeljen"
            vozilo_id = row.get("vozilo_id") or "nedodeljeno"
            adresa_id = row.get("adresa_id") or "nema"
            redosled = row.get("redosled", "nedefinisan")
            return f"Trenutna dodela putnika: Putnik ID {putnik_id} dodeljen terminu {termin_id}. Vozač ID: {vozac_id}, Vozilo ID: {vozilo_id}, Adresa ID: {adresa_id}, Redosled: {redosled}."

        # 10. Slotovi trenutne dodele (kapaciteti po terminima)
        elif table_name == "v3_trenutna_dodela_slot":
            termin_id = row.get("termin_id") or "nepoznat"
            vozac_id = row.get("vozac_id") or "nedodeljen"
            vozilo_id = row.get("vozilo_id") or "nedodeljeno"
            kapacitet = row.get("kapacitet", 0)
            zauzeto = row.get("zauzeto", 0)
            slobodno = max(0, kapacitet - zauzeto)
            return f"Slot trenutne dodele: Termin ID {termin_id}, Vozač ID: {vozac_id}, Vozilo ID: {vozilo_id}. Ukupan kapacitet: {kapacitet}, zauzeto mesta: {zauzeto}, slobodno: {slobodno}."

        # Opšta pretraga za ostale tabele
        else:
            clean_fields = {k: v for k, v in row.items() if v is not None and k not in ['id', 'created_at', 'updated_at']}
            return f"Podatak iz tabele '{table_name}': {json.dumps(clean_fields, ensure_ascii=False)}."
            
    except Exception as e:
        return f"Greška pri parsiranju reda iz tabele {table_name}: {e}"

# --- FUNKCIJA ZA ANALIZU I DETEKCIJU ANOMALIJA (SAM ZAKLJUČUJE ŠTA JE BITNO) ---
def _upsert_insight(cursor, title: str, description: str, source_table: str, source_id: str, severity: str):
    """Ažurira postojeći zaključak po (title, source_table, source_id) ili ubacuje novi."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cursor.execute("""
        SELECT id FROM ai_insights
        WHERE title=? AND source_table=? AND source_id=?
    """, (title, source_table, source_id))
    row = cursor.fetchone()
    if row:
        cursor.execute("""
            UPDATE ai_insights
            SET description=?, severity=?, created_at=?
            WHERE id=?
        """, (description, severity, now, row[0]))
    else:
        cursor.execute("""
            INSERT INTO ai_insights (title, description, source_table, source_id, severity, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (title, description, source_table, source_id, severity, now))


def _analyze_and_detect_insights_sync():
    """Sinhrona verzija analize — poziva se unutar executor-a"""
    try:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        # Brišemo zastarele nominal/significant zaključke čiji izvor više ne postoji u bazi znanja,
        # ali zadržavamo kritične (koje korisnik možda želi ručno da pregleda).
        cursor.execute("""
            DELETE FROM ai_insights
            WHERE severity != 'critical'
              AND source_id != ''
              AND NOT EXISTS (
                  SELECT 1 FROM ai_knowledge_base kb
                  WHERE kb.source_table = ai_insights.source_table
                    AND kb.source_id = ai_insights.source_id
              )
        """)
        
        # 1. ANALIZA TROŠKOVA GORIVA (v3_gorivo)
        cursor.execute("SELECT id, content FROM ai_knowledge_base WHERE source_table='v3_gorivo'")
        fuel_rows = cursor.fetchall()
        
        amounts = []
        for _, content in fuel_rows:
            try:
                parts = content.split("vrednosti od ")
                if len(parts) > 1:
                    iznos = float(parts[1].split(" RSD")[0])
                    amounts.append(iznos)
            except:
                continue
        
        if amounts:
            avg_fuel = sum(amounts) / len(amounts)
            
            for source_id, content in fuel_rows:
                try:
                    parts = content.split("vrednosti od ")
                    iznos = float(parts[1].split(" RSD")[0])
                    if iznos > avg_fuel * 1.5:
                        _upsert_insight(
                            cursor,
                            "Uočena anomalija u trošku za gorivo",
                            f"Registrovan je izuzetno visok trošak goriva u iznosu od {iznos} RSD, što drastično odudara od prosečnog sipanja koje iznosi {avg_fuel:.1f} RSD.",
                            "v3_gorivo",
                            source_id,
                            "significant"
                        )
                except:
                    continue

        # 2. ANALIZA SVEUKUPNIH RAČUNA I FINANSIJA (Rashodi naspram prihoda)
        cursor.execute("SELECT content FROM ai_knowledge_base WHERE source_table='v3_finansije'")
        fin_rows = cursor.fetchall()
        
        rashodi = 0.0
        prihodi = 0.0
        n_rashod = 0
        n_prihod = 0
        
        for (content,) in fin_rows:
            try:
                iznos_part = content.split("iznosi ")
                if len(iznos_part) > 1:
                    iznos = float(iznos_part[1].split(" RSD")[0])
                    if "PRIHOD" in content:
                        prihodi += iznos
                        n_prihod += 1
                    else:
                        rashodi += iznos
                        n_rashod += 1
            except:
                continue
                
        if rashodi > prihodi and rashodi > 0:
            _upsert_insight(
                cursor,
                "Rashodi premašili prihode",
                f"Ukupni zabeleženi rashodi u bazi iznose {rashodi:.1f} RSD kroz {n_rashod} transakcija, dok su prihodi {prihodi:.1f} RSD. Kompanija posluje sa deficitom u ovom posmatranom periodu.",
                "v3_finansije",
                "",
                "significant"
            )
        elif prihodi > 0:
            _upsert_insight(
                cursor,
                "Stabilan finansijski bilans",
                f"Prihodi iznose ukupno {prihodi:.1f} RSD, dok su rashodi uspešno zadržani na {rashodi:.1f} RSD. Neto profit iznosi {(prihodi-rashodi):.1f} RSD.",
                "v3_finansije",
                "",
                "nominal"
            )

        # 3. ANALIZA ZAHTEVA PO GRADOVIMA
        cursor.execute("SELECT content FROM ai_knowledge_base WHERE source_table='v3_zahtevi'")
        req_rows = cursor.fetchall()
        
        gradovi = {}
        for (content,) in req_rows:
            try:
                if "Relacija/Grad: " in content:
                    grad = content.split("Relacija/Grad: ")[1].split(".")[0].strip()
                    gradovi[grad] = gradovi.get(grad, 0) + 1
            except:
                continue
                
        if gradovi:
            omiljeni_grad = max(gradovi, key=gradovi.get)
            ukupno_zahteva = sum(gradovi.values())
            procenat = (gradovi[omiljeni_grad] / ukupno_zahteva) * 100
            
            _upsert_insight(
                cursor,
                f"Dominantno gradsko tržište: {omiljeni_grad}",
                f"Grad sa ubedljivo najvećim brojem zahteva za transport je {omiljeni_grad} sa ukupno {gradovi[omiljeni_grad]} vožnji, što predstavlja {procenat:.1f}% od ukupnih zahteva u aplikaciji.",
                "v3_zahtevi",
                "",
                "nominal"
            )

        conn.commit()
        conn.close()
        log_event("Analiza baze uspešno izvršena. Generisani/ažurirani samostalni zaključci.")
    except Exception as e:
        log_event(f"Greška tokom izvršavanja analize zaključaka: {e}")

async def analyze_and_detect_insights():
    """Async wrapper koji sprečava race condition, ne blokira event loop i primenjuje debounce"""
    global last_analysis_time
    now = asyncio.get_event_loop().time()
    if now - last_analysis_time < ANALYSIS_DEBOUNCE_SECONDS:
        log_event("Analiza preskočena zbog debounce-a (prečesto okidanje).")
        return
    if analysis_lock.locked():
        log_event("Analiza već u toku, preskačem dupli poziv.")
        return
    async with analysis_lock:
        last_analysis_time = asyncio.get_event_loop().time()
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _analyze_and_detect_insights_sync)

# --- UČENJE PROŠLOSTI (ISTORIJSKA SINHRONIZACIJA) ---
async def _learn_past_data_async():
    """Asinhrona verzija istorijskog učenja — direktno koristi Supabase klijent"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    cursor.execute("SELECT val FROM sync_status WHERE key='history_synced'")
    synced = cursor.fetchone()
    
    if synced and synced[0] == "true":
        log_event("Istorijski podaci su već sinhronizovani. Preskačem istorijsko učenje.")
        conn.close()
        return
    
    log_event("Pokrećem učenje prošlosti (Istorijska sinhronizacija svih tabela)...")
    
    tables_to_sync = [
        "v3_adrese", "v3_auth", "v3_vozila", "v3_zahtevi", 
        "v3_gorivo", "v3_finansije", "v3_racuni", 
        "v3_trenutna_dodela", "v3_trenutna_dodela_slot", 
        "v3_operativna_nedelja", "v3_kapacitet_slots", "v3_app_settings"
    ]
    
    total_rows = 0
    
    for table_name in tables_to_sync:
        try:
            log_event(f"Preuzimam podatke za tabelu: {table_name}...")
            # Povlačimo do 500 najsvežijih slogova po tabeli za offline analizu
            response = await supabase.table(table_name).select("*").limit(500).execute()
            
            if response.data:
                rows_synced = 0
                for row_data in response.data:
                    rid = str(row_data.get("id", ""))
                    if not rid:
                        continue
                        
                    content_text = parse_row_to_text(table_name, row_data)
                    embedding_str = ""
                    
                    if embedder:
                        emb = embedder.encode(content_text).tolist()
                        embedding_str = json.dumps(emb)
                    
                    unique_id = f"{table_name}:{rid}"
                    
                    cursor.execute("""
                        INSERT OR REPLACE INTO ai_knowledge_base (id, source_table, source_id, content, embedding, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                    """, (
                        unique_id,
                        table_name,
                        rid,
                        content_text,
                        embedding_str,
                        datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    ))
                    rows_synced += 1
                
                total_rows += rows_synced
                log_event(f"Sinhronizovano {rows_synced} slogova iz tabele {table_name}.")
        except Exception as e:
            log_event(f"Upozorenje: Sinhronizacija tabele {table_name} nije uspela: {e}")
            
    cursor.execute("INSERT OR REPLACE INTO sync_status (key, val) VALUES ('history_synced', 'true')")
    conn.commit()
    conn.close()
    
    log_event(f"Istorijsko učenje završeno! Ukupno naučeno {total_rows} poslovnih događaja.")

async def learn_past_data():
    """Async wrapper za istorijsko učenje"""
    await _learn_past_data_async()
    await analyze_and_detect_insights()

# --- REALTIME ASINHRONI LISTENERS (UČENJE U REALNOM VREMENU) ---
async def start_realtime_sync():
    """Pokreće beskonačnu petlju sa reconnect logikom"""
    backoff_seconds = 5
    max_backoff = 300
    
    while True:
        try:
            log_event("Uspostavljam vezu sa Supabase Realtime WebSocket klijentom...")
            
            def handle_db_change(payload):
                asyncio.create_task(process_realtime_event(payload))
            
            channel = supabase.channel("realtime-ai-learning")
            channel.on_postgres_changes(
                event="*",
                schema="public",
                callback=handle_db_change
            )
            await channel.subscribe()
            log_event("🟢 Realtime mrežni kanal je uspešno otvoren i sada aktivno sluša sve tabele u sistemu!")
            
            # Držimo kanal otvorenim dok se ne desi greška
            while True:
                await asyncio.sleep(30)
                # Health check: pokušavamo da pročitamo stanje kanala na bezbedan način.
                # Različite verzije supabase-py realtime klijenta izlažu različita svojstva,
                # pa koristimo try/except umesto direktnog pristupa is_joined.
                try:
                    is_joined = getattr(channel, 'is_joined', None)
                    if is_joined is False:
                        log_event("🟡 Realtime kanal više nije aktivan. Pokušavam reconnect...")
                        break
                    # Alternativna provera: pokušaj slanja heartbeat-a ako postoji metoda
                    heartbeat = getattr(channel, 'send_heartbeat', None)
                    if callable(heartbeat):
                        await heartbeat()
                except Exception as e:
                    log_event(f"🟡 Realtime kanal health check nije uspeo: {e}. Pokušavam reconnect...")
                    break
                    
        except Exception as e:
            log_event(f"🔴 Neuspešno otvaranje Realtime kanala: {e}")
        
        log_event(f"⏳ Ponovni pokušaj konekcije za {backoff_seconds}s...")
        await asyncio.sleep(backoff_seconds)
        backoff_seconds = min(backoff_seconds * 2, max_backoff)

def _process_realtime_event_sync(payload: dict):
    """Sinhrona obrada realtime događaja"""
    try:
        event_type = payload.get("eventType")
        table_name = payload.get("table")
        
        new_record = payload.get("new") or {}
        old_record = payload.get("old") or {}
        
        rid = str(new_record.get("id") or old_record.get("id") or "")
        if not rid or not table_name:
            return
            
        unique_id = f"{table_name}:{rid}"
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        if event_type == "DELETE":
            cursor.execute("DELETE FROM ai_knowledge_base WHERE id=?", (unique_id,))
            conn.commit()
            log_event(f"🗑️ Podatak uklonjen iz baze (DELETE iz {table_name}). Automatski zaboravljam događaj.")
        else:
            content_text = parse_row_to_text(table_name, new_record)
            embedding_str = ""
            
            if embedder:
                emb = embedder.encode(content_text).tolist()
                embedding_str = json.dumps(emb)
                
            cursor.execute("""
                INSERT OR REPLACE INTO ai_knowledge_base (id, source_table, source_id, content, embedding, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                unique_id,
                table_name,
                rid,
                content_text,
                embedding_str,
                datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            ))
            conn.commit()
            log_event(f"🧠 Učenje u realnom vremenu (Realtime {event_type} u {table_name}): {content_text}")
            
        conn.close()
    except Exception as e:
        log_event(f"Greška pri obradi Realtime događaja učenja: {e}")

async def process_realtime_event(payload: dict):
    """Async wrapper za obradu realtime događaja"""
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _process_realtime_event_sync, payload)
    # Nakon svake izmene, asinhrono okidamo re-kalkulaciju anomalija
    await analyze_and_detect_insights()


def _load_embedder_sync():
    """Sinhrono učitavanje SentenceTransformer modela za semantičku pretragu."""
    try:
        from sentence_transformers import SentenceTransformer
        return SentenceTransformer('all-MiniLM-L6-v2')
    except Exception as e:
        log_event(f"SentenceTransformer nije mogao biti učitan: {e}")
        return None


# --- FASTAPI ENDPOINTI ---

@app.on_event("startup")
async def startup_event():
    global supabase, embedder, realtime_task
    
    init_local_db()
    log_event("Lokalna SQLite baza podataka je inicijalizovana.")
    
    supabase = await create_async_client(SUPABASE_URL, SUPABASE_KEY)
    log_event("Supabase asinhrona konekcija uspešno otvorena.")
    
    # 3. Učitavanje SentenceTransformer-a za semantiku (lazy, u pozadinskom thread-u)
    try:
        log_event("Učitavam SentenceTransformer model ('all-MiniLM-L6-v2') za semantičko razumevanje...")
        loop = asyncio.get_event_loop()
        embedder = await loop.run_in_executor(None, _load_embedder_sync)
        if embedder:
            log_event("Semantički model uspešno pokrenut i uskladišten.")
        else:
            log_event("SentenceTransformer nije dostupan. Koristićemo klasične SQLite LIKE pretrage.")
    except Exception as e:
        log_event(f"Upozorenje: Nije moguće podići SentenceTransformer: {e}. Koristićemo klasične SQLite LIKE pretrage.")

    asyncio.create_task(learn_past_data())
    realtime_task = asyncio.create_task(start_realtime_sync())

@app.on_event("shutdown")
async def shutdown_event():
    if realtime_task:
        realtime_task.cancel()
    log_event("Gavra AI Backend je uspešno zaustavljen.")

@app.get("/")
def read_root():
    return {
        "status": "active",
        "service": "Gavra Realtime AI Brain",
        "sqlite_db_location": DB_FILE,
        "logs_cached": len(live_logs)
    }

@app.get("/logs", response_model=LogResponse)
def get_logs():
    """Vraća najnovije logove učenja u realnom vremenu"""
    return LogResponse(logs=list(live_logs))

@app.get("/insights", response_model=InsightResponse)
def get_insights():
    """Vraća samostalne zaključke, preporuke i anomalije koje je AI otkrio"""
    try:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("SELECT id, title, description, source_table, source_id, severity, created_at FROM ai_insights ORDER BY id DESC")
        rows = cursor.fetchall()
        conn.close()
        
        insights_lst = []
        for r in rows:
            insights_lst.append({
                "id": r[0],
                "title": r[1],
                "description": r[2],
                "source_table": r[3],
                "source_id": r[4],
                "severity": r[5],
                "created_at": r[6]
            })
        return InsightResponse(insights=insights_lst)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def _search_knowledge_base_sync(usr_msg: str):
    """Sinhrona pretraga lokalne baze znanja. Vraća listu (content, source_id) tuple-a."""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # Prvo pokušavamo semantičku pretragu ako imamo embedder
    matched_content = []
    matched_sources = []
    semantic_scores = {}
    
    if embedder:
        q_emb = embedder.encode(usr_msg)
        cursor.execute("SELECT id, content, embedding FROM ai_knowledge_base WHERE embedding IS NOT NULL AND embedding != '' LIMIT 2000")
        kb_rows = cursor.fetchall()
        
        scores = []
        for kid, content, emb_json in kb_rows:
            try:
                emb = np.array(json.loads(emb_json))
                dot_product = np.dot(q_emb, emb)
                norm_q = np.linalg.norm(q_emb)
                norm_emb = np.linalg.norm(emb)
                score = dot_product / (norm_q * norm_emb) if norm_q > 0 and norm_emb > 0 else 0
                if score > 0.30:
                    scores.append((score, content, kid))
            except Exception:
                continue
        
        scores.sort(key=lambda x: x[0], reverse=True)
        top_matches = scores[:15]
        for score, content, kid in top_matches:
            matched_content.append(content)
            matched_sources.append(kid)
            semantic_scores[content] = score
    
    # Hibridna tekstualna pretraga po ključnim rečima
    words = usr_msg.lower().split()
    keywords = [w for w in words if len(w) > 2 and w not in ["ili", "sam", "kod", "bilo", "sve", "kako", "šta", "gde", "kad"]]
    
    if keywords:
        # Koristimo LIKE za svaku ključnu reč umesto učitavanja cele tabele
        placeholders = ' OR '.join(["LOWER(content) LIKE ?" for _ in keywords])
        params = [f'%{kw}%' for kw in keywords]
        cursor.execute(f"SELECT id, content FROM ai_knowledge_base WHERE {placeholders} LIMIT 200", params)
        text_rows = cursor.fetchall()
        
        text_matches = []
        for kid, content in text_rows:
            content_lower = content.lower()
            match_count = sum(1 for kw in keywords if kw in content_lower)
            if match_count > 0:
                text_matches.append((match_count, content, kid))
        
        text_matches.sort(key=lambda x: x[0], reverse=True)
        for _, content, kid in text_matches[:10]:
            if content not in matched_content:
                matched_content.append(content)
                matched_sources.append(kid)
    
    conn.close()
    return list(zip(matched_content, matched_sources))[:15]


@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest, session_id: str = Header(None)):
    """Glavni pretraživač i generator pametnih odgovora koristeći Ollama i lokalnu pretragu"""
    try:
        if not _check_chat_rate_limit(session_id):
            log_event(f"Rate limit premašen za sesiju: {session_id or 'default'}")
            raise HTTPException(
                status_code=429,
                detail=f"Previše zahteva. Dozvoljeno je {CHAT_RATE_LIMIT_MAX} chat poruka u {CHAT_RATE_LIMIT_WINDOW_SECONDS} sekundi."
            )
        
        usr_msg = request.message
        log_event(f"Korisnički upit (sesija: {session_id or 'default'}): '{usr_msg}'")
        
        # Direktna sinhrona pretraga (FastAPI sync endpoint već radi u thread pool-u)
        matched = _search_knowledge_base_sync(usr_msg)
        matched_content = [content for content, _ in matched]
        matched_sources = [source_id for _, source_id in matched]
        
        context_str = "\n".join([f"[{source_id}] {content}" for content, source_id in matched])
        
        # Konverzacijska memorija izolovana po sesiji
        history = _get_or_create_session_history(session_id)
        conversation_context = ""
        if history:
            conversation_context = "\n".join([
                f"{'Korisnik' if msg['role'] == 'user' else 'Asistent'}: {msg['content']}"
                for msg in history
            ])
        
        system_prompt = (
            "Ti si Gavra AI, visoko stručni i pouzdani analitički sistem za logistiku i transport, razvijen isključivo za vlasnika aplikacije.\n"
            "Tvoj zadatak je da odgovaraš na pitanja isključivo na osnovu sledećih sirovih podataka dobijenih iz tabela u realnom vremenu.\n"
            "Svaki podatak je označen identifikatorom oblika [tabela:id] koji predstavlja njegov izvor u bazi.\n"
            "-------------------\n"
            f"{context_str if context_str else 'U bazi trenutno nema zabeleženih relevantnih podataka za ovo pitanje.'}\n"
            "-------------------\n"
            "STROGA PRAVILA ZA ODGOVARANJE:\n"
            "1. Odgovaraj ISKLJUČIVO na osnovu gore navedenih podataka o finansijama, vožnjama, putnicima, vozačima i gorivu.\n"
            "2. Ukoliko odgovor na pitanje ne može da se izvuče iz dostavljenih sirovih podataka, tvoj jedini odgovor MORA biti: \n"
            "   'Oprostite, nemam te podatke u svojoj bazi podataka.'\n"
            "3. Nemoj izmišljati, pretpostavljati niti dopunjavati podatke opštim znanjem sa interneta! Ako ne vidiš tačne brojeve ili imena u kontekstu, za tebe oni ne postoje.\n"
            "4. Nakon svake tvrdnje koja se oslanja na konkretan podatak, obavezno navedi izvor u formatu [tabela:id]. Na primer: 'Ukupni rashodi su 150.000 RSD [v3_finansije:abc-123].'\n"
            "5. Piši odgovore tečnim, prijatnim i profesionalnim srpskim jezikom, sa uvažavanjem i bez suvišnog filozofiranja.\n"
            "6. Ako korisnik nastavlja prethodni razgovor, koristi prethodne poruke kao kontekst, ali se i dalje oslanjaj isključivo na poslovne podatke iz baze."
        )
        
        messages = [
            {'role': 'system', 'content': system_prompt},
        ]
        if conversation_context:
            messages.append({'role': 'system', 'content': f"Prethodni razgovor:\n{conversation_context}"})
        messages.append({'role': 'user', 'content': usr_msg})
        
        log_event(f"Šaljem upit lokalnom {OLLAMA_MODEL} modelu na Ollama server...")
        
        response = ollama.chat(
            model=OLLAMA_MODEL,
            messages=messages
        )
        
        ai_resp = response['message']['content']
        log_event("Odgovor od LLM modela uspešno generisan i vraćen.")
        
        # Ažuriramo konverzacijsku memoriju za konkretnu sesiju
        history.append({'role': 'user', 'content': usr_msg})
        history.append({'role': 'assistant', 'content': ai_resp})
        
        return ChatResponse(
            response=ai_resp,
            sources=matched_sources[:5]
        )
        
    except Exception as e:
        log_event(f"Greška tokom izvršavanja chat upita: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
