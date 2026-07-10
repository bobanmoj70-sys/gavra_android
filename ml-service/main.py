from fastapi import FastAPI, HTTPException, Depends, Request, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field
import requests
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
import sqlite_vec
import re
from contextlib import asynccontextmanager
from functools import lru_cache
import hashlib
import threading
import logging
from logging.handlers import RotatingFileHandler

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


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager za inicijalizaciju i gašenje resursa."""
    global supabase, embedder, realtime_task
    
    try:
        init_local_db()
        log_event("Lokalna SQLite baza podataka je inicijalizovana.")
        
        if not SUPABASE_SERVICE_ROLE_KEY:
            log_event("⚠️  Upozorenje: SUPABASE_SERVICE_ROLE_KEY nije definisan. Koristim SUPABASE_ANON_KEY. AI može biti ograničen RLS pravilima i ne videti sve tabele.")
        
        supabase = await create_async_client(SUPABASE_URL, SUPABASE_KEY)
        log_event("Supabase asinhrona konekcija uspešno otvorena.")
        
        # Učitavanje SentenceTransformer-a za semantiku (lazy, u pozadinskom thread-u)
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
        
        yield
        
        # Shutdown
        if realtime_task:
            realtime_task.cancel()
            try:
                await realtime_task
            except asyncio.CancelledError:
                pass
        log_event("Gavra AI Backend je uspešno zaustavljen.")
    except asyncio.CancelledError:
        log_event("Gavra AI Backend je zaustavljen po zahtevu (CancelledError).")
        if realtime_task:
            realtime_task.cancel()
        raise
    except Exception as e:
        log_event(f"Greška u lifespan-u: {e}")
        raise


# CORS podrška za komunikaciju sa mobilnim i drugim klijentima
app = FastAPI(title="Gavra Realtime AI Backend", lifespan=lifespan)

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
    message: str = Field(..., max_length=2000)


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

# Šira lista srpskih stop-reči za kvalitetniju tekstualnu pretragu
SRPSKE_STOP_RECI = {
    "ili", "sam", "kod", "bilo", "sve", "kako", "šta", "gde", "kad", "kada",
    "i", "u", "je", "se", "na", "za", "sa", "od", "do", "po", "da", "ne",
    "li", "pa", "ako", "koji", "koja", "koje", "što", "kakav", "kakva", "kakvo",
    "ovaj", "ova", "ovo", "taj", "ta", "to", "svaki", "svaka", "svako", "svi", "sva",
    "mi", "ti", "on", "ona", "ono", "vi", "oni", "one", "smo", "ste", "su",
    "bi", "bismo", "biste", "bih", "si", "ću", "ćeš", "će", "ćemo", "ćete",
    "neću", "nećeš", "neće", "nećemo", "nećete", "ma", "baš", "već", "još",
    "samo", "takođe", "međutim", "dakle", "zato", "jer", "dok", "čiji", "čija", "čije",
    "gdje", "kuda", "odakle", "koliko", "kolika", "mnogo", "malo", "više", "manje",
    "najviše", "najmanje", "tako", "ovako", "onako", "ovde", "onde", "tamo",
    "ovamo", "onamo", "gore", "dole", "levo", "desno", "blizu", "daleko",
    "spreman", "spremna", "spremno", "molim", "hvala", "izvoli", "izvolite"
}

# Ollama parametri za kontrolisanije i brže odgovore
OLLAMA_TEMPERATURE = float(os.environ.get('OLLAMA_TEMPERATURE', '0.3'))
OLLAMA_MAX_TOKENS = int(os.environ.get('OLLAMA_MAX_TOKENS', '800'))
OLLAMA_TIMEOUT_SECONDS = int(os.environ.get('OLLAMA_TIMEOUT_SECONDS', '30'))

# Parametri vektorske pretrage
VECTOR_DIMENSION = 384  # all-MiniLM-L6-v2
VECTOR_TOP_K = 15
VECTOR_MIN_SIMILARITY = 0.30

# Keširanje čestih chat upita (smanjuje pozive ka Ollama)
CHAT_CACHE_MAXSIZE = int(os.environ.get('CHAT_CACHE_MAXSIZE', '100'))
CHAT_CACHE_ENABLED = os.environ.get('CHAT_CACHE_ENABLED', 'true').lower() in ('true', '1', 'yes')

# Tabele koje AI prati i uči u realnom vremenu
TABLES_TO_SYNC = [
    "v3_adrese", "v3_auth", "v3_vozila", "v3_zahtevi",
    "v3_gorivo", "v3_finansije", "v3_racuni",
    "v3_trenutna_dodela", "v3_trenutna_dodela_slot",
    "v3_operativna_nedelja", "v3_kapacitet_slots", "v3_app_settings"
]

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
    
    # Učitavanje sqlite-vec ekstenzije za efikasnu vektorsku pretragu
    try:
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        cursor.execute("SELECT vec_version()")
        vec_ver = cursor.fetchone()[0]
        log_event(f"sqlite-vec ekstenzija učitana (verzija {vec_ver}).")
    except Exception as e:
        log_event(f"Upozorenje: sqlite-vec ekstenzija nije učitana: {e}. Vektorska pretraga će biti spora.")
    
    # Brana baza znanja
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS ai_knowledge_base (
            id TEXT PRIMARY KEY,
            source_table TEXT,
            source_id TEXT,
            content TEXT,
            embedding TEXT,  -- JSON niz brojeva (fallback)
            metadata TEXT,   -- JSON sa izvornim vrednostima za pouzdaniju analizu
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
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_kb_metadata ON ai_knowledge_base(metadata)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_insights_severity ON ai_insights(severity)')
    
    # Vektorska tabela za efikasnu semantičku pretragu
    cursor.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_knowledge_base USING vec0(
            id TEXT PRIMARY KEY,
            embedding FLOAT[{dim}]
        )
    '''.format(dim=VECTOR_DIMENSION))
    
    conn.commit()
    conn.close()

# Konfiguracija file logging-a (rotirajući fajl do 5MB, max 3 backup-a)
LOG_FILE = os.path.join(os.path.dirname(__file__), "gavra_ai.log")
_file_logger = logging.getLogger("gavra_ai_file")
_file_logger.setLevel(logging.INFO)
_file_logger.propagate = False

if not _file_logger.handlers:
    try:
        handler = RotatingFileHandler(LOG_FILE, maxBytes=5*1024*1024, backupCount=3, encoding='utf-8')
        handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
        _file_logger.addHandler(handler)
    except Exception as e:
        print(f"Nije moguće konfigurisati file logger: {e}")


def log_event(message: str):
    """Zapisuje događaj u konzolu, memorijski log i rotirajući fajl."""
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
    _file_logger.info(message)


# Regex za maskiranje potencijalno osetljivih podataka u logovima
_SENSITIVE_PATTERNS = [
    (re.compile(r'\b\d{13,16}\b'), '***MASKED_CARD***'),  # brojevi kartica
    (re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'), '***MASKED_EMAIL***'),
]


def _sanitize_log_line(line: str) -> str:
    """Maskira osetljive podatke u log liniji pre slanja klijentu."""
    sanitized = line
    for pattern, replacement in _SENSITIVE_PATTERNS:
        sanitized = pattern.sub(replacement, sanitized)
    return sanitized


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
        cursor.execute("SELECT source_id, metadata FROM ai_knowledge_base WHERE source_table='v3_gorivo'")
        fuel_rows = cursor.fetchall()
        
        amounts = []
        for _, metadata_json in fuel_rows:
            try:
                metadata = json.loads(metadata_json or '{}')
                iznos = float(metadata.get("iznos", 0))
                if iznos > 0:
                    amounts.append(iznos)
            except:
                continue
        
        if amounts:
            avg_fuel = sum(amounts) / len(amounts)
            
            for source_id, metadata_json in fuel_rows:
                try:
                    metadata = json.loads(metadata_json or '{}')
                    iznos = float(metadata.get("iznos", 0))
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
        cursor.execute("SELECT metadata FROM ai_knowledge_base WHERE source_table='v3_finansije'")
        fin_rows = cursor.fetchall()
        
        rashodi = 0.0
        prihodi = 0.0
        n_rashod = 0
        n_prihod = 0
        
        for (metadata_json,) in fin_rows:
            try:
                metadata = json.loads(metadata_json or '{}')
                iznos = float(metadata.get("iznos", 0))
                tip = metadata.get("tip", "rashod").lower()
                if iznos <= 0:
                    continue
                if tip == "prihod":
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
        cursor.execute("SELECT metadata FROM ai_knowledge_base WHERE source_table='v3_zahtevi'")
        req_rows = cursor.fetchall()
        
        gradovi = {}
        for (metadata_json,) in req_rows:
            try:
                metadata = json.loads(metadata_json or '{}')
                grad = metadata.get("grad", "").strip()
                if grad:
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
async def _learn_past_data_async(force: bool = False):
    """Asinhrona verzija istorijskog učenja — direktno koristi Supabase klijent"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    if not force:
        cursor.execute("SELECT val FROM sync_status WHERE key='history_synced'")
        synced = cursor.fetchone()
        
        if synced and synced[0] == "true":
            log_event("Istorijski podaci su već sinhronizovani. Preskačem istorijsko učenje.")
            conn.close()
            return
    else:
        log_event(" Forsiran resync: brišem status sinhronizacije...")
        cursor.execute("DELETE FROM sync_status WHERE key='history_synced'")
        cursor.execute("DELETE FROM ai_knowledge_base")
        conn.commit()
    
    log_event("Pokrećem učenje prošlosti (Istorijska sinhronizacija svih tabela)...")
    
    total_rows = 0
    
    for table_name in TABLES_TO_SYNC:
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
                    metadata = _extract_metadata(table_name, row_data)
                    unique_id = f"{table_name}:{rid}"
                    embedding_str = ""
                    
                    if embedder:
                        emb = embedder.encode(content_text).tolist()
                        embedding_str = json.dumps(emb)
                        _upsert_vector(conn, unique_id, emb)
                    
                    cursor.execute("""
                        INSERT OR REPLACE INTO ai_knowledge_base (id, source_table, source_id, content, embedding, metadata, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (
                        unique_id,
                        table_name,
                        rid,
                        content_text,
                        embedding_str,
                        json.dumps(metadata, ensure_ascii=False),
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

async def learn_past_data(force: bool = False):
    """Async wrapper za istorijsko učenje"""
    await _learn_past_data_async(force=force)
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
            for table_name in TABLES_TO_SYNC:
                channel.on_postgres_changes(
                    event="*",
                    schema="public",
                    table=table_name,
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
            _delete_vector(conn, unique_id)
            conn.commit()
            log_event(f"🗑️ Podatak uklonjen iz baze (DELETE iz {table_name}). Automatski zaboravljam događaj.")
        else:
            content_text = parse_row_to_text(table_name, new_record)
            metadata = _extract_metadata(table_name, new_record)
            embedding_str = ""
            
            if embedder:
                emb = embedder.encode(content_text).tolist()
                embedding_str = json.dumps(emb)
                _upsert_vector(conn, unique_id, emb)
            
            cursor.execute("""
                INSERT OR REPLACE INTO ai_knowledge_base (id, source_table, source_id, content, embedding, metadata, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                unique_id,
                table_name,
                rid,
                content_text,
                embedding_str,
                json.dumps(metadata, ensure_ascii=False),
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
    """Vraća najnovije logove učenja u realnom vremenu (maskirane)"""
    return LogResponse(logs=[_sanitize_log_line(line) for line in live_logs])

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

@app.post("/resync")
async def resync():
    """Forsira ponovno učenje svih istorijskih podataka iz Supabase-a."""
    log_event("Ručno pokrenut resync od strane klijenta.")
    asyncio.create_task(learn_past_data(force=True))
    return {"status": "resync_started"}


def _search_knowledge_base_sync(usr_msg: str):
    """Sinhrona pretraga lokalne baze znanja. Vraća listu (content, source_id) tuple-a."""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # Učitaj sqlite-vec ekstenziju na konekciji
    try:
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
    except Exception:
        pass
    
    matched_scores: dict[str, tuple[str, str, float]] = {}  # source_id -> (content, table_id, score)
    
    # 1. Semantička pretraga preko sqlite-vec
    if embedder:
        try:
            q_emb = embedder.encode(usr_msg)
            q_blob = sqlite_vec.serialize_float32(q_emb.tolist())
            cursor.execute("""
                SELECT id, distance
                FROM vec_knowledge_base
                WHERE embedding MATCH ?
                ORDER BY distance
                LIMIT ?
            """, (q_blob, VECTOR_TOP_K * 2))
            
            for unique_id, distance in cursor.fetchall():
                # sqlite-vec distance je obično (1 - cosine_similarity) za vec0
                score = max(0.0, 1.0 - float(distance))
                if score < VECTOR_MIN_SIMILARITY:
                    continue
                cursor.execute("SELECT id, source_table, source_id, content FROM ai_knowledge_base WHERE id=?", (unique_id,))
                row = cursor.fetchone()
                if row:
                    _, source_table, source_id, content = row
                    matched_scores[unique_id] = (content, f"{source_table}:{source_id}", score * 1.0)
        except Exception as e:
            log_event(f"Vektorska pretraga nije uspela: {e}. Koristim tekstualnu pretragu.")
    
    # 2. Tekstualna pretraga po ključnim rečima
    words = usr_msg.lower().split()
    keywords = [w for w in words if len(w) > 2 and w not in SRPSKE_STOP_RECI]
    
    if keywords:
        placeholders = ' OR '.join(["LOWER(content) LIKE ?" for _ in keywords])
        params = [f'%{kw}%' for kw in keywords]
        cursor.execute(f"SELECT id, source_table, source_id, content FROM ai_knowledge_base WHERE {placeholders} LIMIT 200", params)
        
        for unique_id, source_table, source_id, content in cursor.fetchall():
            content_lower = content.lower()
            match_count = sum(1 for kw in keywords if kw in content_lower)
            if match_count == 0:
                continue
            # Normalizovan tekstualni score: procenat poklopljenih reči
            text_score = min(1.0, match_count / len(keywords)) * 0.8
            
            if unique_id in matched_scores:
                content, source, sem_score = matched_scores[unique_id]
                # Kombinujemo semantički i tekstualni score
                combined = max(sem_score, text_score * 1.2)
                matched_scores[unique_id] = (content, source, combined)
            else:
                matched_scores[unique_id] = (content, f"{source_table}:{source_id}", text_score)
    
    conn.close()
    
    # Sortiraj po kombinovanom score-u i vrati top 15
    sorted_matches = sorted(matched_scores.values(), key=lambda x: x[2], reverse=True)
    return [(content, source_id) for content, source_id, _ in sorted_matches[:15]]


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
        
        # Uzmi konverzacijsku istoriju za sesiju
        history = _get_or_create_session_history(session_id)
        conversation_context = "\n".join(
            [f"{msg['role']}: {msg['content']}" for msg in history]
        )
        
        # Direktna sinhrona pretraga (FastAPI sync endpoint već radi u thread pool-u)
        matched = _search_knowledge_base_sync(usr_msg)
        matched_content = [content for content, _ in matched]
        matched_sources = [source_id for _, source_id in matched]
        
        context_str = "\n".join([f"[{source_id}] {content}" for content, source_id in matched])
        context_hash = _hash_context(context_str, conversation_context)
        
        # Proveri keš pre poziva Ollama
        cached_response = _chat_cache.get(usr_msg, context_hash)
        if cached_response is not None:
            log_event("Odgovor pronađen u kešu, preskačem poziv ka Ollama.")
            history.append({'role': 'user', 'content': usr_msg})
            history.append({'role': 'assistant', 'content': cached_response})
            return ChatResponse(
                response=cached_response,
                sources=matched_sources[:5]
            )
        
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
            "6. Ako korisnik nastavlja prethodni razgovor, koristi prethodne poruke kao kontekst, ali se i dalje oslanjaj isključivo na poslovne podatke iz baze.\n"
            "\n"
            "PRIMERI ODGOVARANJA:\n"
            "Pitanje: Koliko je ukupno rashoda ovog meseca?\n"
            "Odgovor: Ukupni rashodi u tekućem mesecu iznose 125.000 RSD [v3_finansije:xyz-789]. Najveći trošak je gorivo od 45.000 RSD [v3_gorivo:abc-123].\n"
            "\n"
            "Pitanje: Koji grad ima najviše zahteva za vožnju?\n"
            "Odgovor: Grad sa najviše zahteva je Beograd sa 42 vožnje [v3_zahtevi:def-456], što čini 58% od ukupnog broja zahteva.\n"
            "\n"
            "Pitanje: Šta je kvantna fizika?\n"
            "Odgovor: Oprostite, nemam te podatke u svojoj bazi podataka."
        )
        
        messages = [
            {'role': 'system', 'content': system_prompt},
        ]
        if conversation_context:
            messages.append({'role': 'system', 'content': f"Prethodni razgovor:\n{conversation_context}"})
        messages.append({'role': 'user', 'content': usr_msg})
        
        log_event(f"Šaljem upit lokalnom {OLLAMA_MODEL} modelu na Ollama server...")
        
        try:
            ollama_resp = requests.post(
                'http://127.0.0.1:11434/api/chat',
                json={
                    'model': OLLAMA_MODEL,
                    'messages': messages,
                    'stream': False,
                    'options': {
                        'temperature': OLLAMA_TEMPERATURE,
                        'num_predict': OLLAMA_MAX_TOKENS,
                    },
                    'keep_alive': '5m',
                },
                headers={'Connection': 'close'},
                timeout=OLLAMA_TIMEOUT_SECONDS,
            )
            ollama_resp.raise_for_status()
            response = ollama_resp.json()
        except requests.exceptions.Timeout:
            log_event(f"Ollama model nije odgovorio u {OLLAMA_TIMEOUT_SECONDS}s.")
            raise HTTPException(
                status_code=504,
                detail=f"AI modelu je potrebno previše vremena za odgovor. Pokušaj ponovo za trenutak."
            )
        except requests.exceptions.RequestException as e:
            log_event(f"Greška u komunikaciji sa Ollama serverom: {e}")
            raise HTTPException(
                status_code=502,
                detail=f"Greška u komunikaciji sa AI serverom: {e}"
            )
        
        ai_resp = response['message']['content']
        log_event("Odgovor od LLM modela uspešno generisan i vraćen.")
        
        # Sačuvaj u keš za buduće identične upite
        _chat_cache.set(usr_msg, context_hash, ai_resp)
        
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


def _extract_metadata(table_name: str, row: dict) -> dict:
    """Izdvaja ključne numeričke/kategoričke vrednosti iz reda za pouzdaniju analizu."""
    metadata = {}
    if not row:
        return metadata
    
    try:
        if table_name == "v3_finansije":
            metadata["tip"] = row.get("tip", "rashod")
            metadata["iznos"] = float(row.get("iznos", 0) or 0)
            metadata["kategorija"] = row.get("kategorija", "")
            metadata["mesec"] = row.get("mesec", "")
            metadata["godina"] = row.get("godina", "")
        elif table_name == "v3_gorivo":
            metadata["vozilo_id"] = row.get("vozilo_id", "")
            metadata["iznos"] = float(row.get("iznos", 0) or 0)
            metadata["litara"] = float(row.get("litara", 0) or 0)
            metadata["km_sat"] = float(row.get("km_sat", 0) or 0)
        elif table_name == "v3_zahtevi":
            metadata["grad"] = row.get("grad", "")
            metadata["status"] = row.get("status", "")
            metadata["datum"] = row.get("datum", "")
        elif table_name == "v3_auth":
            metadata["tip"] = row.get("tip", "")
            metadata["ime"] = row.get("ime", "")
            metadata["cena_po_danu"] = float(row.get("cena_po_danu", 0) or 0)
        elif table_name == "v3_racuni":
            metadata["stanje"] = float(row.get("stanje", 0) or 0)
            metadata["tip"] = row.get("tip", "")
        elif table_name == "v3_operativna_nedelja":
            metadata["dan"] = row.get("dan", "")
            metadata["pravac"] = row.get("pravac", "")
            metadata["putnik_id"] = row.get("putnik_id", "")
            metadata["vozac_id"] = row.get("vozac_id", "")
    except Exception:
        pass
    
    return metadata


def _ensure_vec_extension(conn: sqlite3.Connection):
    """Učitava sqlite-vec ekstenziju na datoj konekciji, ignorisanjem grešaka."""
    try:
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
    except Exception:
        pass


def _delete_vector(conn: sqlite3.Connection, unique_id: str):
    """Briše vektor iz vektorske tabele."""
    _ensure_vec_extension(conn)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM vec_knowledge_base WHERE id=?", (unique_id,))


def _upsert_vector(conn: sqlite3.Connection, unique_id: str, embedding: list):
    """Upsertuje embedding u vektorsku tabelu."""
    _ensure_vec_extension(conn)
    cursor = conn.cursor()
    emb_blob = sqlite_vec.serialize_float32(embedding)
    cursor.execute("DELETE FROM vec_knowledge_base WHERE id=?", (unique_id,))
    cursor.execute(
        "INSERT INTO vec_knowledge_base(id, embedding) VALUES (?, ?)",
        (unique_id, emb_blob)
    )


class _LRUChatCache:
    """Jednostavan thread-safe LRU keš za chat odgovore."""
    def __init__(self, maxsize: int):
        self.maxsize = maxsize
        self._cache: dict[str, str] = {}
        self._lock = threading.Lock()

    def _make_key(self, query: str, context_hash: str) -> str:
        normalized = " ".join(query.lower().split())
        return hashlib.sha256(f"{normalized}|{context_hash}".encode('utf-8')).hexdigest()

    def get(self, query: str, context_hash: str) -> str | None:
        if self.maxsize <= 0:
            return None
        key = self._make_key(query, context_hash)
        with self._lock:
            value = self._cache.pop(key, None)
            if value is not None:
                # Pomeri na kraj (najskorije korišćen)
                self._cache[key] = value
            return value

    def set(self, query: str, context_hash: str, response: str):
        if self.maxsize <= 0:
            return
        key = self._make_key(query, context_hash)
        with self._lock:
            if key in self._cache:
                self._cache.pop(key)
            elif len(self._cache) >= self.maxsize:
                # Ukloni najstariji
                oldest = next(iter(self._cache))
                del self._cache[oldest]
            self._cache[key] = response


_chat_cache = _LRUChatCache(CHAT_CACHE_MAXSIZE if CHAT_CACHE_ENABLED else 0)


def _hash_context(context_str: str, conversation_context: str) -> str:
    """Pravi hash od konteksta koji utiče na odgovor."""
    return hashlib.sha256(
        f"{context_str}\n{conversation_context}".encode('utf-8')
    ).hexdigest()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
