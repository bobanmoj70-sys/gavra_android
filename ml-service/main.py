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
PORT = int(os.environ.get('PORT', '8000'))

# Backend mora čitati sve tabele, pa preferiramo SERVICE_ROLE_KEY (zaobilazi RLS).
# Ako nije definisan, fallback na ANON_KEY (može biti ograničen RLS pravilima).
SUPABASE_KEY = SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError('SUPABASE_URL i SUPABASE_SERVICE_ROLE_KEY (ili SUPABASE_ANON_KEY) moraju biti definisani u .env fajlu')

if not ML_API_KEY:
    raise RuntimeError('ML_API_KEY mora biti definisan u .env fajlu radi zaštite endpointa')

# Gemini API ključ se proverava ovde, ali greška se baca tek pri prvom chat pozivu
# da bi server mogao da se pokrene i uči podatke čak i ako ključ nije podešen.
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY')

# Lokalne SQLite baze
DB_FILE = os.path.join(os.path.dirname(__file__), "gavra_ai.db")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager za inicijalizaciju i gašenje resursa."""
    global supabase, embedder, realtime_task, reconciliation_task
    
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
        reconciliation_task = asyncio.create_task(periodic_reconciliation_loop())
        
        yield
        
        # Shutdown
        if realtime_task:
            realtime_task.cancel()
            try:
                await realtime_task
            except asyncio.CancelledError:
                pass
        if reconciliation_task:
            reconciliation_task.cancel()
            try:
                await reconciliation_task
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
reconciliation_task = None
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
    "spreman", "spremna", "spremno", "molim", "hvala", "izvoli", "izvolite",
    "ima", "imaju", "imam", "imaš", "imamo", "imate", "imao", "imala", "imalo",
    "nema", "nemaju", "nemam", "nemaš", "nemamo", "nemate"
}

_UUID_LIKE_RE = re.compile(r"\b[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[1-5][0-9a-fA-F]{3}\b-[89abAB][0-9a-fA-F]{3}\b-[0-9a-fA-F]{12}\b")
_DATE_LIKE_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?\b")
_NUMBER_LIKE_RE = re.compile(r"\b\d+(?:\.\d+)?\b")

# Gemini API konfiguracija
GEMINI_MODEL = os.environ.get('GEMINI_MODEL', 'gemini-2.5-flash')
GEMINI_TIMEOUT_SECONDS = int(os.environ.get('GEMINI_TIMEOUT_SECONDS', '30'))
GEMINI_TEMPERATURE = float(os.environ.get('GEMINI_TEMPERATURE', '0.3'))
GEMINI_MAX_OUTPUT_TOKENS = int(os.environ.get('GEMINI_MAX_OUTPUT_TOKENS', '800'))

# Parametri vektorske pretrage
VECTOR_DIMENSION = 384  # all-MiniLM-L6-v2
VECTOR_TOP_K = 15
VECTOR_MIN_SIMILARITY = 0.30

# Keširanje cestih chat upita (smanjuje pozive ka AI modelu)
CHAT_CACHE_MAXSIZE = int(os.environ.get('CHAT_CACHE_MAXSIZE', '100'))
CHAT_CACHE_ENABLED = os.environ.get('CHAT_CACHE_ENABLED', 'true').lower() in ('true', '1', 'yes')

# Paginacija i inkrementalno učenje iz Supabase
HISTORY_SYNC_PAGE_SIZE = int(os.environ.get('HISTORY_SYNC_PAGE_SIZE', '1000'))
HISTORY_SYNC_MAX_ROWS_PER_TABLE = int(os.environ.get('HISTORY_SYNC_MAX_ROWS_PER_TABLE', '50000'))

# Interval periodične reconciliation provere (uklanja zapise obrisane dok server nije slušao realtime)
RECONCILIATION_INTERVAL_SECONDS = int(os.environ.get('RECONCILIATION_INTERVAL_SECONDS', str(6 * 3600)))  # podrazumevano 6h

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

    def _all_columns_snapshot_suffix() -> str:
        try:
            snapshot = {k: v for k, v in row.items() if k not in ["embedding"]}
            return f" AllColumnsSnapshot: {json.dumps(snapshot, ensure_ascii=False, sort_keys=True)}"
        except Exception:
            return ""

    all_columns_suffix = _all_columns_snapshot_suffix()
    
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
            putnik_id = row.get("putnik_v3_auth_id", "")
            broj_voznji = row.get("broj_voznji", 0)
            naplatio = row.get("naplatio_ime", "")
            naplaceno_by = row.get("naplaceno_by", "")
            ime = row.get("ime", "")
            poslednja_dopuna = row.get("poslednja_dopuna", 0)
            dogadjaj_id = row.get("dogadjaj_id", "")

            json_summary = []
            for key in ["nenaplacene_voznje_json", "realizovane_voznje_json", "otkazane_voznje_json", "uplate_json"]:
                val = row.get(key)
                if val and isinstance(val, list) and len(val) > 0:
                    # Napravi sažetak sa ključnim podacima
                    items = []
                    for i, item in enumerate(val[:5], 1):
                        if isinstance(item, dict):
                            parts = []
                            if "datum" in item:
                                parts.append(f"datum {item['datum']}")
                            if "cena" in item:
                                parts.append(f"cena {item['cena']}")
                            if "iznos" in item:
                                parts.append(f"iznos {item['iznos']}")
                            if "grad" in item:
                                parts.append(f"grad {item['grad']}")
                            if "vreme" in item:
                                parts.append(f"vreme {item['vreme']}")
                            if "operativna_id" in item:
                                parts.append(f"operativna_id {item['operativna_id']}")
                            if "uplata_id" in item:
                                parts.append(f"uplata_id {item['uplata_id']}")
                            if "otkazao_by" in item:
                                parts.append(f"otkazao_by {item['otkazao_by']}")
                            if "naplatio_by" in item:
                                parts.append(f"naplatio_by {item['naplatio_by']}")
                            items.append(f"stavka {i}: " + ", ".join(parts))
                        else:
                            items.append(f"stavka {i}: {item}")
                    more = f" (i još {len(val) - 5} stavki)" if len(val) > 5 else ""
                    json_summary.append(f"{key} ({len(val)} stavki){more}: " + "; ".join(items))
            json_text = " Dodatni podaci: " + "; ".join(json_summary) + "." if json_summary else ""

            return f"Finansije ({tip}): Transakcija '{naziv}' iznosi {iznos} RSD. Kategorija: {kategorija}. Isplata izvršena iz: '{isplata_iz}'. Period: obuhvata mesec {mesec}/{godina}. Putnik ID: {putnik_id}, ime: {ime}, broj vožnji: {broj_voznji}, naplatio: {naplatio}, naplaćeno od strane ID: {naplaceno_by}. Poslednja dopuna: {poslednja_dopuna} RSD. Događaj ID: {dogadjaj_id}.{json_text}{all_columns_suffix}"
        # 2. Zahtevi vožnji
        elif table_name == "v3_zahtevi":
            putnik_id = row.get("created_by") or row.get("putnik_id", "nepoznato")
            grad = row.get("grad", "nepoznato")
            datum = row.get("datum", "")
            vreme = row.get("trazeni_polazak_at", "")
            status = row.get("status", "obrada").upper()
            polazak_at = row.get("polazak_at") or "nije dodeljen"
            alt_pre = row.get("alternativa_pre_at") or "nema"
            alt_posle = row.get("alternativa_posle_at") or "nema"
            updated_by = row.get("updated_by") or "nepoznat"
            koristi_sekundarnu = "da" if row.get("koristi_sekundarnu") else "ne"
            adresa_override_id = row.get("adresa_override_id") or "nema"
            scheduled_at = row.get("scheduled_at") or "nije zakazano"
            return f"Zahtev za vožnju: Putnik sa ID {putnik_id} je podneo zahtev za datum {datum}. Relacija/Grad: {grad}. Traženo vreme polaska: u {vreme}. Trenutni status zahteva: {status}. Konačno dodeljeno vreme polaska: {polazak_at}. Alternativa pre: {alt_pre}, posle: {alt_posle}. Ažurirao: {updated_by}. Koristi sekundarnu adresu: {koristi_sekundarnu}. Adresa override ID: {adresa_override_id}. Zakazano u: {scheduled_at}.{all_columns_suffix}"

        # 3. Gorivo
        elif table_name == "v3_gorivo":
            # Podržava oba formata: transakcije sipanja i agregirano stanje rezervoara
            has_transaction_fields = any(
                row.get(key) is not None for key in ["vozilo_id", "iznos", "litara", "km_sat", "kartica", "kreirano_by"]
            )

            if has_transaction_fields:
                vozilo_id = row.get("vozilo_id", "nepoznato")
                iznos = row.get("iznos", 0)
                litara = row.get("litara", 0)
                km_sat = row.get("km_sat", 0)
                kartica = "da" if row.get("kartica") else "ne"
                kreirano_by = row.get("kreirano_by", "nepoznato")
                return f"Sipanje goriva: Vozilo ID {vozilo_id}. Iznos: {iznos} RSD. Sipano: {litara} litara. Kilometraža/sat: {km_sat}. Plaćeno karticom: {kartica}. Uneo: {kreirano_by}.{all_columns_suffix}"

            kapacitet = row.get("kapacitet_litri", 0)
            trenutno = row.get("trenutno_stanje_litri", 0)
            alarm = row.get("alarm_nivo_litri", 0)
            pistolj = row.get("brojac_pistolj_litri", 0)
            cena = row.get("cena_po_litru", 0)
            dug = row.get("dug_iznos", 0)
            return f"Stanje goriva: Rezervoar kapaciteta {kapacitet} litara, trenutno stanje {trenutno} litara. Alarmni nivo: {alarm} litara. Brojač pištolja: {pistolj} litara. Cena po litru: {cena} RSD. Dug: {dug} RSD.{all_columns_suffix}"

        # 4. Adrese
        elif table_name == "v3_adrese":
            naziv = row.get("naziv", "Bez naziva")
            grad = row.get("grad", "")
            lat = row.get("gps_lat", "")
            lng = row.get("gps_lng", "")
            return f"Adresa u sistemu: Naziv '{naziv}', grad: {grad}. Geografske koordinate su Latitudu {lat} i Longitudu {lng}.{all_columns_suffix}"

        # 5. Korisnici (Auth)
        elif table_name == "v3_auth":
            ime = row.get("ime", "Neznano ime")
            telefon = row.get("telefon", "")
            telefon2 = row.get("telefon_2", "")
            tip = row.get("tip", "korisnik").upper()
            cena_dan = row.get("cena_po_danu", 0)
            cena_pokupljenju = row.get("cena_po_pokupljenju", 0)
            adresa_bc = row.get("adresa_primary_bc_id", "")
            adresa_vs = row.get("adresa_primary_vs_id", "")
            adresa_sec_bc = row.get("adresa_secondary_bc_id", "")
            adresa_sec_vs = row.get("adresa_secondary_vs_id", "")
            boja = row.get("boja", "")
            platform = row.get("platform", "")
            app_version = row.get("app_version", "")
            last_seen = row.get("last_seen_at", "")
            platform_2 = row.get("platform_2", "")
            app_version_2 = row.get("app_version_2", "")
            last_seen_2 = row.get("last_seen_at_2", "")
            return f"Korisnički profil/Nalog ({tip}): Ime: {ime}, telefon: {telefon}, telefon 2: {telefon2}, boja: {boja}. Cena po danu: {cena_dan} RSD, cena po pokupljenju: {cena_pokupljenju} RSD. Primarna adresa BC: {adresa_bc}, primarna adresa VS: {adresa_vs}. Sekundarna adresa BC: {adresa_sec_bc}, sekundarna adresa VS: {adresa_sec_vs}. Platforma: {platform}, verzija aplikacije: {app_version}, poslednja aktivnost: {last_seen}. Drugi uređaj - platforma: {platform_2}, verzija: {app_version_2}, poslednja aktivnost: {last_seen_2}.{all_columns_suffix}"

        # 6. Vozila
        elif table_name == "v3_vozila":
            marka = row.get("marka", "Nepoznata marka")
            model = row.get("model", "")
            naziv = f"{marka} {model}".strip() or "Neznato vozilo"
            tablica = row.get("registracija", "Bez tablica")
            trenutna_km = row.get("trenutna_km", 0) or 0
            godina = row.get("godina_proizvodnje", "")
            broj_sasije = row.get("broj_sasije", "")
            registracija_vazi_do = row.get("registracija_vazi_do", "")
            napomena = row.get("napomena", "")
            
            servisni_podaci = []
            if row.get("mali_servis_datum"):
                servisni_podaci.append(f"mali servis: {row['mali_servis_datum']} na {row.get('mali_servis_km', 0)} km")
            if row.get("veliki_servis_datum"):
                servisni_podaci.append(f"veliki servis: {row['veliki_servis_datum']} na {row.get('veliki_servis_km', 0)} km")
            if row.get("plocice_prednje_datum"):
                servisni_podaci.append(f"prednje pločice: {row['plocice_prednje_datum']} na {row.get('plocice_prednje_km', 0)} km")
            if row.get("plocice_zadnje_datum"):
                servisni_podaci.append(f"zadnje pločice: {row['plocice_zadnje_datum']} na {row.get('plocice_zadnje_km', 0)} km")
            if row.get("akumulator_datum"):
                servisni_podaci.append(f"akumulator: {row['akumulator_datum']} na {row.get('akumulator_km', 0)} km")
            if row.get("alternator_datum"):
                servisni_podaci.append(f"alternator: {row['alternator_datum']} na {row.get('alternator_km', 0)} km")
            if row.get("trap_datum"):
                servisni_podaci.append(f"trap: {row['trap_datum']} na {row.get('trap_km', 0)} km")
            if row.get("gume_prednje_datum"):
                opis = row.get("gume_prednje_opis", "")
                opis_text = f" ({opis})" if opis else ""
                servisni_podaci.append(f"prednje gume{opis_text}: {row['gume_prednje_datum']} na {row.get('gume_prednje_km', 0)} km")
            if row.get("gume_zadnje_datum"):
                opis = row.get("gume_zadnje_opis", "")
                opis_text = f" ({opis})" if opis else ""
                servisni_podaci.append(f"zadnje gume{opis_text}: {row['gume_zadnje_datum']} na {row.get('gume_zadnje_km', 0)} km")
            
            radio = row.get("radio", "")
            radio_text = f" Radio: {radio}." if radio else ""
            
            servisni_deo = "; ".join(servisni_podaci) if servisni_podaci else "nema evidentiranih servisnih podataka"
            
            return f"Vozilo u voznom parku: {naziv}, registarska oznaka: {tablica}, godina proizvodnje: {godina}, broj šasije: {broj_sasije}. Registracija važi do: {registracija_vazi_do}. Trenutna kilometraža: {trenutna_km} km. Napomena: {napomena}. Servisni podaci: {servisni_deo}.{radio_text}{all_columns_suffix}"

        # 7. Računi
        elif table_name == "v3_racuni":
            firma = row.get("firma_naziv", "Bez naziva")
            pib = row.get("firma_pib", "")
            mb = row.get("firma_mb", "")
            ziro = row.get("firma_ziro", "")
            adresa = row.get("firma_adresa", "")
            redni_broj = row.get("redni_broj", "")
            godina = row.get("godina", "")
            status = row.get("status", "")
            return f"Račun izdat od strane firme '{firma}' (PIB: {pib}, MB: {mb}). Žiro račun: {ziro}, adresa: {adresa}. Redni broj računa: {redni_broj}/{godina}. Status: {status}.{all_columns_suffix}"

        # 8. Operativna nedelja (Plan vožnji)
        elif table_name == "v3_operativna_nedelja":
            datum = row.get("datum", "")
            grad = row.get("grad", "")
            polazak_at = row.get("polazak_at") or "nije dodeljen"
            pokupljen_at = row.get("pokupljen_at") or "nije pokupljen"
            created_by = row.get("created_by") or "nepoznat"
            updated_by = row.get("updated_by") or "nepoznat"
            koristi_sekundarnu = "da" if row.get("koristi_sekundarnu") else "ne"
            adresa_override_id = row.get("adresa_override_id") or "nema"
            otkazano = ""
            if row.get("otkazano_by"):
                otkazano = f" OTKAZANO od strane {row['otkazano_by']} u {row.get('otkazano_at', '')}."
            return f"Operativni plan i raspored: Datum {datum}, grad: {grad}, planirano vreme polaska: {polazak_at}, vreme pokupljanja: {pokupljen_at}. Kreirao: {created_by}, ažurirao: {updated_by}. Koristi sekundarnu adresu: {koristi_sekundarnu}. Adresa override ID: {adresa_override_id}.{otkazano}{all_columns_suffix}"

        # 9. Trenutna dodela (aktivna dodela putnika na termin)
        elif table_name == "v3_trenutna_dodela":
            putnik_id = row.get("putnik_id") or "nepoznat"
            termin_id = row.get("termin_id") or "nepoznat"
            vozac_id = row.get("vozac_id") or "nedodeljen"
            vozilo_id = row.get("vozilo_id") or "nedodeljeno"
            adresa_id = row.get("adresa_id") or "nema"
            redosled = row.get("redosled", "nedefinisan")
            return f"Trenutna dodela putnika: Putnik ID {putnik_id} dodeljen terminu {termin_id}. Vozač ID: {vozac_id}, Vozilo ID: {vozilo_id}, Adresa ID: {adresa_id}, Redosled: {redosled}.{all_columns_suffix}"

        # 10. Slotovi trenutne dodele (kapaciteti po terminima)
        elif table_name == "v3_trenutna_dodela_slot":
            termin_id = row.get("termin_id") or "nepoznat"
            vozac_id = row.get("vozac_id") or "nedodeljen"
            vozilo_id = row.get("vozilo_id") or "nedodeljeno"
            kapacitet = row.get("kapacitet", 0)
            zauzeto = row.get("zauzeto", 0)
            slobodno = max(0, kapacitet - zauzeto)
            return f"Slot trenutne dodele: Termin ID {termin_id}, Vozač ID: {vozac_id}, Vozilo ID: {vozilo_id}. Ukupan kapacitet: {kapacitet}, zauzeto mesta: {zauzeto}, slobodno: {slobodno}.{all_columns_suffix}"

        # Opšta pretraga za ostale tabele
        else:
            clean_fields = {k: v for k, v in row.items() if v is not None and k not in ['id', 'created_at', 'updated_at']}
            return f"Podatak iz tabele '{table_name}': {json.dumps(clean_fields, ensure_ascii=False)}.{all_columns_suffix}"
            
    except Exception as e:
        return f"Greška pri parsiranju reda iz tabele {table_name}: {e}. Raw row: {json.dumps(row, ensure_ascii=False, default=str)}"

# --- FUNKCIJA ZA ANALIZU I DETEKCIJU ANOMALIJA (SAM ZAKLJUČUJE ŠTA JE BITNO) ---
def _upsert_insight(conn, cursor, title: str, description: str, source_table: str, source_id: str, severity: str):
    """Ažurira postojeći zaključak po (title, source_table, source_id) ili ubacuje novi,
    i sinhronizuje ga u knowledge base radi chat pretrage."""
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
    
    # Sinhronizuj u knowledge base
    unique_id = f"ai_insights:{source_table}:{source_id or 'global'}:{hashlib.sha256(title.encode('utf-8')).hexdigest()[:16]}"
    content_text = f"{title}: {description}"
    embedding_str = ""
    
    global embedder
    if embedder:
        try:
            emb = embedder.encode(content_text).tolist()
            embedding_str = json.dumps(emb)
            _upsert_vector(conn, unique_id, emb)
        except Exception:
            pass
    
    cursor.execute("""
        INSERT OR REPLACE INTO ai_knowledge_base (id, source_table, source_id, content, embedding, metadata, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (
        unique_id,
        "ai_insights",
        source_id or "global",
        content_text,
        embedding_str,
        json.dumps({"source_table": source_table, "source_id": source_id or "global"}, ensure_ascii=False),
        now
    ))


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
                            conn,
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
                conn,
                cursor,
                "Rashodi premašili prihode",
                f"Ukupni zabeleženi rashodi u bazi iznose {rashodi:.1f} RSD kroz {n_rashod} transakcija, dok su prihodi {prihodi:.1f} RSD. Kompanija posluje sa deficitom u ovom posmatranom periodu.",
                "v3_finansije",
                hashlib.sha256("Rashodi premašili prihode".encode('utf-8')).hexdigest()[:16],
                "significant"
            )
        elif prihodi > 0:
            _upsert_insight(
                conn,
                cursor,
                "Stabilan finansijski bilans",
                f"Prihodi iznose ukupno {prihodi:.1f} RSD, dok su rashodi uspešno zadržani na {rashodi:.1f} RSD. Neto profit iznosi {(prihodi-rashodi):.1f} RSD.",
                "v3_finansije",
                hashlib.sha256("Stabilan finansijski bilans".encode('utf-8')).hexdigest()[:16],
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
            
            title = f"Dominantno gradsko tržište: {omiljeni_grad}"
            _upsert_insight(
                conn,
                cursor,
                title,
                f"Grad sa ubedljivo najvećim brojem zahteva za transport je {omiljeni_grad} sa ukupno {gradovi[omiljeni_grad]} vožnji, što predstavlja {procenat:.1f}% od ukupnih zahteva u aplikaciji.",
                "v3_zahtevi",
                hashlib.sha256(title.encode('utf-8')).hexdigest()[:16],
                "nominal"
            )

        # 4. AGREGATNI PREGLED KORISNIKA I VOZILA (za tačne odgovore na "koliko" pitanja)
        cursor.execute("SELECT content, metadata FROM ai_knowledge_base WHERE source_table='v3_auth'")
        auth_rows = cursor.fetchall()
        tipovi = {}
        for content, metadata_json in auth_rows:
            try:
                metadata = json.loads(metadata_json or '{}')
                tip = (metadata.get("tip") or "").upper()
                if not tip and content:
                    # Fallback: izvuci tip iz teksta oblika (TIP)
                    m = re.search(r'\(([A-Z]+)\)', content)
                    tip = m.group(1).upper() if m else "NEPOZNATO"
                tipovi[tip] = tipovi.get(tip, 0) + 1
            except:
                continue
        
        ukupno_korisnika = sum(tipovi.values())
        if ukupno_korisnika > 0:
            _upsert_insight(
                conn,
                cursor,
                "Ukupan broj korisnika u sistemu",
                f"U sistemu je registrovano ukupno {ukupno_korisnika} korisnika. Raspodela po tipovima: {', '.join(f'{k}: {v}' for k, v in sorted(tipovi.items()))}.",
                "v3_auth",
                hashlib.sha256("Ukupan broj korisnika u sistemu".encode('utf-8')).hexdigest()[:16],
                "nominal"
            )
        
        if tipovi.get("VOZAC", 0) > 0:
            _upsert_insight(
                conn,
                cursor,
                "Ukupan broj vozača",
                f"U sistemu je registrovano ukupno {tipovi['VOZAC']} vozača.",
                "v3_auth",
                hashlib.sha256("Ukupan broj vozača".encode('utf-8')).hexdigest()[:16],
                "nominal"
            )
        
        cursor.execute("SELECT content FROM ai_knowledge_base WHERE source_table='v3_vozila'")
        vozila_count = len(cursor.fetchall())
        if vozila_count > 0:
            _upsert_insight(
                conn,
                cursor,
                "Ukupan broj vozila",
                f"U voznom parku se nalazi ukupno {vozila_count} vozila.",
                "v3_vozila",
                hashlib.sha256("Ukupan broj vozila".encode('utf-8')).hexdigest()[:16],
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

def _get_table_last_sync(cursor: sqlite3.Cursor, table_name: str) -> str | None:
    """Vraća poslednji zapamćeni updated_at za datu tabelu, ili None ako nije sinhronizovana."""
    cursor.execute(
        "SELECT val FROM sync_status WHERE key=?",
        (f"last_sync_at:{table_name}",)
    )
    row = cursor.fetchone()
    return row[0] if row else None


def _set_table_last_sync(cursor: sqlite3.Cursor, table_name: str, last_sync_at: str):
    """Čuva poslednji updated_at za datu tabelu."""
    cursor.execute(
        "INSERT OR REPLACE INTO sync_status (key, val) VALUES (?, ?)",
        (f"last_sync_at:{table_name}", last_sync_at)
    )


async def _fetch_all_rows_incremental(table_name: str, last_sync_at: str | None):
    """Dohvata sve redove iz tabele, inkrementalno ako je poznato poslednje sync vreme."""
    all_rows = []
    start = 0
    page_size = HISTORY_SYNC_PAGE_SIZE
    max_rows = HISTORY_SYNC_MAX_ROWS_PER_TABLE
    
    while len(all_rows) < max_rows:
        query = supabase.table(table_name).select("*").order("updated_at", desc=False)
        
        if last_sync_at:
            query = query.gt("updated_at", last_sync_at)
        
        response = await query.range(start, start + page_size - 1).execute()
        page = response.data or []
        
        if not page:
            break
        
        all_rows.extend(page)
        
        if len(page) < page_size:
            break
        
        start += page_size
        
        # Bezbednosna kapa da ne bismo beskonačno učitali
        if len(all_rows) >= max_rows:
            log_event(f"⚠️ Tabela {table_name} dostigla maksimalni limit od {max_rows} redova. Prekidam učenje.")
            break
    
    return all_rows


async def _fetch_all_ids(table_name: str) -> set[str]:
    """Dohvata SVE id vrednosti iz tabele (lagana paginirana select samo kolone id),
    radi poređenja sa lokalnom bazom znanja i uklanjanja obrisanih (orphan) zapisa."""
    ids: set[str] = set()
    start = 0
    page_size = HISTORY_SYNC_PAGE_SIZE
    max_rows = HISTORY_SYNC_MAX_ROWS_PER_TABLE
    
    while len(ids) < max_rows:
        response = await supabase.table(table_name).select("id").range(start, start + page_size - 1).execute()
        page = response.data or []
        
        if not page:
            break
        
        for row_data in page:
            rid = row_data.get("id")
            if rid is not None:
                ids.add(str(rid))
        
        if len(page) < page_size:
            break
        
        start += page_size
    
    return ids


def _reconcile_deleted_rows(conn: sqlite3.Connection, cursor: sqlite3.Cursor, table_name: str, existing_ids: set[str]) -> int:
    """Briše iz lokalne baze znanja zapise čiji izvorni red više ne postoji u Supabase-u
    (npr. obrisan dok server nije slušao realtime kanal). Vraća broj obrisanih zapisa."""
    cursor.execute("SELECT id, source_id FROM ai_knowledge_base WHERE source_table=?", (table_name,))
    local_rows = cursor.fetchall()
    
    orphans = [(unique_id, source_id) for unique_id, source_id in local_rows if source_id not in existing_ids]
    if not orphans:
        return 0
    
    for unique_id, _ in orphans:
        cursor.execute("DELETE FROM ai_knowledge_base WHERE id=?", (unique_id,))
        _delete_vector(conn, unique_id)
    
    conn.commit()
    return len(orphans)


async def _reconcile_all_tables():
    """Prolazi kroz sve prisluškivane tabele i uklanja iz lokalne baze znanja zapise
    čiji izvor više ne postoji u Supabase-u (kompenzuje propuštene DELETE realtime evente)."""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    total_removed = 0
    
    for table_name in TABLES_TO_SYNC:
        try:
            existing_ids = await _fetch_all_ids(table_name)
            removed = _reconcile_deleted_rows(conn, cursor, table_name, existing_ids)
            if removed:
                log_event(f"🧹 Reconciliation: uklonjeno {removed} zastarelih zapisa iz {table_name} (obrisani u Supabase-u).")
            total_removed += removed
        except Exception as e:
            log_event(f"Upozorenje: Reconciliation za tabelu {table_name} nije uspela: {e}")
    
    conn.close()
    if total_removed:
        log_event(f"🧹 Reconciliation završen. Ukupno uklonjeno {total_removed} zastarelih zapisa.")
        await analyze_and_detect_insights()
    return total_removed


async def periodic_reconciliation_loop():
    """Periodično (svakih RECONCILIATION_INTERVAL_SECONDS) proverava da li postoje
    lokalni zapisi čiji izvor je obrisan u Supabase-u dok server nije slušao (npr. downtime),
    i uklanja ih da AI ne 'pamti' nepostojeće podatke."""
    # Prva provera tek nakon inicijalnog perioda, da se ne preklapa sa startnim učenjem
    await asyncio.sleep(RECONCILIATION_INTERVAL_SECONDS)
    while True:
        try:
            log_event("🧹 Pokrećem periodičnu reconciliation proveru (traženje obrisanih zapisa)...")
            await _reconcile_all_tables()
        except Exception as e:
            log_event(f"Greška tokom periodične reconciliation provere: {e}")
        await asyncio.sleep(RECONCILIATION_INTERVAL_SECONDS)


async def _learn_past_data_async(force: bool = False):
    """Asinhrona verzija istorijskog učenja — direktno koristi Supabase klijent"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    if force:
        log_event("🔄 Forsiran resync: brišem per-table sync statuse i lokalnu bazu znanja...")
        cursor.execute("DELETE FROM sync_status WHERE key LIKE 'last_sync_at:%'")
        cursor.execute("DELETE FROM ai_knowledge_base")
        try:
            cursor.execute("DROP TABLE IF EXISTS vec_knowledge_base")
        except Exception as e:
            log_event(f"Upozorenje: Nije moguće obrisati vec_knowledge_base: {e}")
        conn.commit()
    
    log_event("Pokrećem učenje prošlosti (Istorijska sinhronizacija svih tabela)...")
    
    total_rows = 0
    skipped_unchanged = 0
    
    for table_name in TABLES_TO_SYNC:
        try:
            last_sync_at = None if force else _get_table_last_sync(cursor, table_name)
            mode = "sve redove" if (force or not last_sync_at) else f"redove novije od {last_sync_at}"
            log_event(f"Preuzimam podatke za tabelu: {table_name} ({mode})...")
            
            rows = await _fetch_all_rows_incremental(table_name, last_sync_at)
            
            if not rows:
                log_event(f"Nema novih redova za tabelu {table_name}.")
                continue
            
            rows_synced = 0
            newest_updated_at = last_sync_at or ""
            
            for row_data in rows:
                rid = str(row_data.get("id", ""))
                if not rid:
                    continue
                
                row_updated_at = row_data.get("updated_at", "")
                if row_updated_at and (not newest_updated_at or row_updated_at > newest_updated_at):
                    newest_updated_at = row_updated_at
                
                content_text = parse_row_to_text(table_name, row_data)
                metadata = _extract_metadata(table_name, row_data)
                unique_id = f"{table_name}:{rid}"
                content_signature = _content_signature(content_text)

                # Ako je sadržaj reda za isti ID suštinski isti, preskoči rebild embedding-a i upis.
                if _is_signature_unchanged(cursor, unique_id, content_signature):
                    skipped_unchanged += 1
                    rows_synced += 1
                    continue

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
            
            if newest_updated_at:
                _set_table_last_sync(cursor, table_name, newest_updated_at)
            
            total_rows += rows_synced
            conn.commit()
            log_event(f"Sinhronizovano {rows_synced} slogova iz tabele {table_name}.")
            
        except Exception as e:
            log_event(f"Upozorenje: Sinhronizacija tabele {table_name} nije uspela: {e}")
    
    # Zadržavamo i stari globalni flag radi kompatibilnosti
    cursor.execute("INSERT OR REPLACE INTO sync_status (key, val) VALUES ('history_synced', 'true')")
    conn.commit()
    conn.close()
    
    log_event(f"Istorijsko učenje završeno! Ukupno naučeno {total_rows} poslovnih događaja.")
    if skipped_unchanged:
        log_event(f"Preskočeno {skipped_unchanged} neizmenjenih redova (dedup zaštita).")

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
            
            # Dijagnostički callback: čekamo PRAVU potvrdu servera (SUBSCRIBED/CHANNEL_ERROR/TIMED_OUT)
            # umesto da samo pretpostavimo uspeh čim se pošalje join zahtev. subscribe() se vraća
            # odmah nakon slanja zahteva, ali biblioteka može u pozadini tiho da uradi unsubscribe
            # ako se dogodi mismatch između klijentskog i serverskog bindinga, pa moramo eksplicitno
            # da proverimo status preko ovog callback-a.
            subscribe_result: dict = {"status": None, "error": None}
            subscribe_done = asyncio.Event()
            loop = asyncio.get_event_loop()
            
            def on_subscribe(status, error=None):
                subscribe_result["status"] = status
                subscribe_result["error"] = error
                loop.call_soon_threadsafe(subscribe_done.set)
            
            await channel.subscribe(on_subscribe)
            
            try:
                await asyncio.wait_for(subscribe_done.wait(), timeout=15)
            except asyncio.TimeoutError:
                log_event("🔴 Realtime subscribe callback nije stigao u 15s. Server možda nije potvrdio prijavu. Pokušavam reconnect...")
                raise RuntimeError("Realtime subscribe potvrda nije stigla na vreme")
            
            status = subscribe_result["status"]
            error = subscribe_result["error"]
            status_name = getattr(status, "value", str(status))
            
            if status_name != "SUBSCRIBED":
                log_event(f"🔴 Realtime prijava NIJE uspela. Status: {status_name}. Greška: {error}. Pokušavam reconnect...")
                raise RuntimeError(f"Realtime subscribe nije uspeo: {status_name} ({error})")
            
            log_event("🟢 Realtime mrežni kanal je uspešno otvoren i POTVRĐEN od strane servera — sada aktivno sluša sve tabele u sistemu!")
            
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
            content_signature = _content_signature(content_text)

            if _is_signature_unchanged(cursor, unique_id, content_signature):
                conn.close()
                log_event(f"↩️ Preskočen neizmenjen zapis ({table_name}:{rid}) — dedup zaštita.")
                return

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


def _search_knowledge_base_sync(usr_msg: str, top_k: int = 25):
    """Sinhrona pretraga lokalne baze znanja. Vraća listu (content, source_id) tuple-a."""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # Učitaj sqlite-vec ekstenziju na konekciji
    try:
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
    except Exception:
        pass
    
    top_k = max(1, int(top_k))
    matched_scores: dict[str, tuple[str, str, float, str, str, dict]] = {}

    ref_key_table_hints = {
        "created_by": "v3_auth",
        "updated_by": "v3_auth",
        "otkazano_by": "v3_auth",
        "naplaceno_by": "v3_auth",
        "putnik_v3_auth_id": "v3_auth",
        "vozac_v3_auth_id": "v3_auth",
        "vozac_id": "v3_auth",
        "putnik_id": "v3_auth",
        "vozilo_id": "v3_vozila",
        "adresa_override_id": "v3_adrese",
        "adresa_id": "v3_adrese",
        "termin_id": "v3_trenutna_dodela_slot",
    }

    def _parse_metadata(metadata_json: str | None) -> dict:
        if not metadata_json:
            return {}
        try:
            metadata = json.loads(metadata_json)
            return metadata if isinstance(metadata, dict) else {}
        except Exception:
            return {}

    def _upsert_match(unique_id: str, source_table: str, source_id: str, content: str, metadata_json: str | None, score: float):
        source_id_str = str(source_id)
        parsed_metadata = _parse_metadata(metadata_json)
        existing = matched_scores.get(unique_id)
        if not existing or score > existing[2]:
            matched_scores[unique_id] = (
                content,
                f"{source_table}:{source_id_str}",
                score,
                source_table,
                source_id_str,
                parsed_metadata,
            )
    
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
            """, (q_blob, max(VECTOR_TOP_K * 2, top_k * 2)))
            
            for unique_id, distance in cursor.fetchall():
                # sqlite-vec distance je obično (1 - cosine_similarity) za vec0
                score = max(0.0, 1.0 - float(distance))
                if score < VECTOR_MIN_SIMILARITY:
                    continue
                cursor.execute("SELECT id, source_table, source_id, content, metadata FROM ai_knowledge_base WHERE id=?", (unique_id,))
                row = cursor.fetchone()
                if row:
                    _, source_table, source_id, content, metadata_json = row
                    _upsert_match(unique_id, source_table, source_id, content, metadata_json, score * 1.0)
        except Exception as e:
            log_event(f"Vektorska pretraga nije uspela: {e}. Koristim tekstualnu pretragu.")
    
    # 2. Tekstualna pretraga po ključnim rečima
    words = usr_msg.lower().split()
    keywords = [w for w in words if len(w) > 2 and w not in SRPSKE_STOP_RECI]
    
    if keywords:
        # Prvo pokušaj AND pretragu (sve ključne reči moraju biti prisutne) - najtačniji rezultati
        and_placeholders = ' AND '.join(["LOWER(content) LIKE ?" for _ in keywords])
        and_params = [f'%{kw}%' for kw in keywords]
        try:
            cursor.execute(f"SELECT id, source_table, source_id, content, metadata FROM ai_knowledge_base WHERE {and_placeholders} LIMIT 500", and_params)
            and_rows = cursor.fetchall()
        except Exception as e:
            log_event(f"AND tekstualna pretraga nije uspela: {e}")
            and_rows = []
        
        # Zatim OR pretragu za šire poklapanje
        or_placeholders = ' OR '.join(["LOWER(content) LIKE ?" for _ in keywords])
        or_params = [f'%{kw}%' for kw in keywords]
        try:
            cursor.execute(f"SELECT id, source_table, source_id, content, metadata FROM ai_knowledge_base WHERE {or_placeholders} LIMIT 500", or_params)
            or_rows = cursor.fetchall()
        except Exception as e:
            log_event(f"OR tekstualna pretraga nije uspela: {e}")
            or_rows = []
        
        # Kombinuj AND i OR rezultate, bez duplikata
        seen_ids = set()
        text_rows = []
        for row in and_rows + or_rows:
            unique_id = row[0]
            if unique_id not in seen_ids:
                seen_ids.add(unique_id)
                text_rows.append(row)

        and_ids = {r[0] for r in and_rows}
        
        for unique_id, source_table, source_id, content, metadata_json in text_rows:
            content_lower = content.lower()
            match_count = sum(1 for kw in keywords if kw in content_lower)
            if match_count == 0:
                continue
            # AND poklapanja dobijaju bonus
            is_and_match = unique_id in and_ids
            base_text_score = min(1.0, match_count / len(keywords)) * 0.8
            text_score = base_text_score + (0.2 if is_and_match else 0.0)
            
            if unique_id in matched_scores:
                _, _, sem_score, _, _, _ = matched_scores[unique_id]
                # Kombinujemo semantički i tekstualni score
                combined = max(sem_score, text_score * 1.2)
                _upsert_match(unique_id, source_table, source_id, content, metadata_json, combined)
            else:
                _upsert_match(unique_id, source_table, source_id, content, metadata_json, text_score)

    # 3. 1-hop proširenje: dodaj povezane redove na osnovu ID referenci iz metadata
    if matched_scores:
        sorted_seed_items = sorted(matched_scores.items(), key=lambda item: item[1][2], reverse=True)[:12]
        references_to_expand: dict[tuple[str | None, str], float] = {}

        for _, (_, _, seed_score, _, _, metadata) in sorted_seed_items:
            if not isinstance(metadata, dict):
                continue
            for key, value in metadata.items():
                if value is None or isinstance(value, (dict, list)):
                    continue

                key_str = str(key)
                if not (key_str in ref_key_table_hints or key_str.endswith("_id") or key_str in {"created_by", "updated_by", "otkazano_by"}):
                    continue

                value_str = str(value).strip()
                if not value_str or value_str.lower() in {"none", "null", "n/a", "0", "false"}:
                    continue

                hinted_table = ref_key_table_hints.get(key_str)
                ref_key = (hinted_table, value_str)
                previous = references_to_expand.get(ref_key, 0.0)
                references_to_expand[ref_key] = max(previous, seed_score)

        for (hinted_table, referenced_id), parent_score in references_to_expand.items():
            try:
                if hinted_table:
                    cursor.execute(
                        "SELECT id, source_table, source_id, content, metadata FROM ai_knowledge_base WHERE source_table=? AND source_id=? LIMIT 2",
                        (hinted_table, referenced_id),
                    )
                else:
                    cursor.execute(
                        "SELECT id, source_table, source_id, content, metadata FROM ai_knowledge_base WHERE source_id=? AND source_table!='ai_insights' LIMIT 3",
                        (referenced_id,),
                    )

                related_rows = cursor.fetchall()
                related_score = max(0.15, parent_score * 0.60)
                for unique_id, source_table, source_id, content, metadata_json in related_rows:
                    _upsert_match(unique_id, source_table, source_id, content, metadata_json, related_score)
            except Exception as e:
                log_event(f"Povezivanje konteksta nije uspelo za referencu {hinted_table}:{referenced_id}: {e}")
    
    conn.close()
    
    # Sortiraj po kombinovanom score-u i vrati raznovrsnije rezultate (near-duplicate dedup)
    sorted_matches = sorted(matched_scores.values(), key=lambda x: x[2], reverse=True)
    unique_matches: list[tuple[str, str]] = []
    duplicate_fallback: list[tuple[str, str]] = []
    seen_signatures: set[str] = set()

    for content, source_id, _, source_table, _, _ in sorted_matches:
        signature = _content_signature(content)
        signature_key = f"{source_table}:{signature}" if signature else f"{source_table}:{hashlib.sha256((content or '').encode('utf-8')).hexdigest()}"
        if signature_key in seen_signatures:
            duplicate_fallback.append((content, source_id))
            continue
        seen_signatures.add(signature_key)
        unique_matches.append((content, source_id))
        if len(unique_matches) >= top_k:
            break

    if len(unique_matches) < top_k:
        needed = top_k - len(unique_matches)
        unique_matches.extend(duplicate_fallback[:needed])

    return unique_matches[:top_k]


@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest, session_id: str = Header(None)):
    """Glavni pretraživač i generator pametnih odgovora koristeći Gemini API i lokalnu pretragu"""
    try:
        if not _check_chat_rate_limit(session_id):
            log_event(f"Rate limit premašen za sesiju: {session_id or 'default'}")
            raise HTTPException(
                status_code=429,
                detail=f"Previše zahteva. Dozvoljeno je {CHAT_RATE_LIMIT_MAX} chat poruka u {CHAT_RATE_LIMIT_WINDOW_SECONDS} sekundi."
            )
        
        usr_msg = request.message
        log_event(f"Korisnicki upit (sesija: {session_id or 'default'}): '{usr_msg}'")
        
        # Uzmi konverzacijsku istoriju za sesiju
        history = _get_or_create_session_history(session_id)
        conversation_context = "\n".join(
            [f"{msg['role']}: {msg['content']}" for msg in history]
        )
        
        # Direktna sinhrona pretraga (FastAPI sync endpoint vec radi u thread pool-u)
        matched = _search_knowledge_base_sync(usr_msg)
        matched_content = [content for content, _ in matched]
        matched_sources = [source_id for _, source_id in matched]
        
        context_str = "\n".join([f"[{source_id}] {content}" for content, source_id in matched])
        context_hash = _hash_context(context_str, conversation_context)
        
        # Proveri kes pre poziva Gemini
        cached_response = _chat_cache.get(usr_msg, context_hash)
        if cached_response is not None:
            log_event("Odgovor pronadjen u kesu, preskacem poziv ka Gemini.")
            history.append({'role': 'user', 'content': usr_msg})
            history.append({'role': 'assistant', 'content': cached_response})
            return ChatResponse(
                response=cached_response,
                sources=matched_sources[:5]
            )
        
        system_prompt = (
            "Ti si Gavra AI, asistent za logistiku i transport. Odgovaraj iskljucivo na osnovu podataka ispod.\n"
            "Svaki podatak ima izvor u formatu [tabela:id].\n"
            "-------------------\n"
            f"{context_str if context_str else 'Nema relevantnih podataka u bazi za ovo pitanje.'}\n"
            "-------------------\n"
            "PRAVILA:\n"
            "1. Koristi SAMO podatke iz gornjeg konteksta.\n"
            "2. Ako pitanje trazi broj (npr. 'koliko'), prebroj odgovarajuce redove u kontekstu.\n"
            "3. Ako odgovor nije u podacima, reci tacno: 'Oprostite, nemam te podatke u svojoj bazi podataka.'\n"
            "4. Nemoj izmisljati. Navedi izvor u formatu [tabela:id] za svaku tvrdnju.\n"
            "5. Odgovaraj na srpskom jeziku, kratko i jasno.\n"
            "\n"
            "Primer:\n"
            "Pitanje: Koliko vozaca ima?\n"
            "Odgovor: Na osnovu podataka, ukupno ima 3 vozaca [v3_auth:abc], [v3_auth:def], [v3_auth:ghi]."
        )
        
        log_event(f"Saljem upit ka Gemini ({GEMINI_MODEL})...")
        
        if not GEMINI_API_KEY:
            log_event("GEMINI_API_KEY nije definisan u .env fajlu.")
            raise HTTPException(
                status_code=503,
                detail="AI chat trenutno nije dostupan jer GEMINI_API_KEY nije konfigurisan na serveru."
            )
        
        try:
            gemini_url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
            
            # Ugradi prethodnu konverzaciju (ako postoji) da AI pamti kontekst unutar sesije
            gemini_contents = [
                {
                    "role": "user",
                    "parts": [{"text": system_prompt}]
                },
                {
                    "role": "model",
                    "parts": [{"text": "Razumem. Odgovaram iskljucivo na osnovu dostavljenih podataka."}]
                },
            ]
            for msg in history:
                gemini_role = "model" if msg.get('role') in ('assistant', 'ai', 'model') else "user"
                gemini_contents.append({
                    "role": gemini_role,
                    "parts": [{"text": msg.get('content', '')}]
                })
            gemini_contents.append({
                "role": "user",
                "parts": [{"text": usr_msg}]
            })
            
            gemini_body = {
                "contents": gemini_contents,
                "generationConfig": {
                    "temperature": GEMINI_TEMPERATURE,
                    "maxOutputTokens": GEMINI_MAX_OUTPUT_TOKENS,
                }
            }
            
            gemini_resp = requests.post(
                gemini_url,
                json=gemini_body,
                headers={'Content-Type': 'application/json'},
                timeout=GEMINI_TIMEOUT_SECONDS,
            )
            gemini_resp.raise_for_status()
            response = gemini_resp.json()
            
            ai_resp = response['candidates'][0]['content']['parts'][0]['text']
            log_event("Odgovor od Gemini uspesno generisan i vracen.")
            
        except requests.exceptions.Timeout:
            log_event(f"Gemini nije odgovorio u {GEMINI_TIMEOUT_SECONDS}s.")
            raise HTTPException(
                status_code=504,
                detail="AI modelu je potrebno previse vremena za odgovor. Pokusaj ponovo za trenutak."
            )
        except requests.exceptions.RequestException as e:
            log_event(f"Greska u komunikaciji sa Gemini API-jem: {e}")
            raise HTTPException(
                status_code=502,
                detail=f"Greska u komunikaciji sa AI serverom: {e}"
            )
        except (KeyError, IndexError) as e:
            log_event(f"Neocekivan odgovor od Gemini API-ja: {e}")
            raise HTTPException(
                status_code=502,
                detail="Neocekivan odgovor od AI modela."
            )
        
        # Sacuvaj u kes za buduce identicne upite
        _chat_cache.set(usr_msg, context_hash, ai_resp)
        
        # Azuriramo konverzacijsku memoriju za konkretnu sesiju
        history.append({'role': 'user', 'content': usr_msg})
        history.append({'role': 'assistant', 'content': ai_resp})
        
        return ChatResponse(
            response=ai_resp,
            sources=matched_sources[:5]
        )
        
    except Exception as e:
        log_event(f"Greska tokom izvrsavanja chat upita: {e}")
        raise HTTPException(status_code=500, detail=str(e))


def _extract_metadata(table_name: str, row: dict) -> dict:
    """Izdvaja ključne numeričke/kategoričke vrednosti iz reda za pouzdaniju analizu."""
    metadata = {}
    if not row:
        return metadata
    
    try:
        if table_name == "v3_finansije":
            metadata["tip"] = row.get("tip") or "rashod"
            metadata["iznos"] = float(row.get("iznos", 0) or 0)
            metadata["kategorija"] = row.get("kategorija", "")
            metadata["mesec"] = row.get("mesec", "")
            metadata["godina"] = row.get("godina", "")
            metadata["naziv"] = row.get("naziv", "")
            metadata["ime"] = row.get("ime", "")
            metadata["putnik_v3_auth_id"] = row.get("putnik_v3_auth_id", "")
            metadata["naplaceno_by"] = row.get("naplaceno_by", "")
            metadata["poslednja_dopuna"] = float(row.get("poslednja_dopuna", 0) or 0)
        elif table_name == "v3_gorivo":
            metadata["vozilo_id"] = row.get("vozilo_id", "")
            metadata["iznos"] = float(row.get("iznos", 0) or 0)
            metadata["litara"] = float(row.get("litara", 0) or 0)
            metadata["km_sat"] = float(row.get("km_sat", 0) or 0)
            metadata["kartica"] = bool(row.get("kartica"))
            metadata["kreirano_by"] = row.get("kreirano_by", "")
            metadata["kapacitet_litri"] = float(row.get("kapacitet_litri", 0) or 0)
            metadata["trenutno_stanje_litri"] = float(row.get("trenutno_stanje_litri", 0) or 0)
            metadata["cena_po_litru"] = float(row.get("cena_po_litru", 0) or 0)
            metadata["dug_iznos"] = float(row.get("dug_iznos", 0) or 0)
        elif table_name == "v3_zahtevi":
            metadata["grad"] = row.get("grad", "")
            metadata["status"] = row.get("status", "")
            metadata["datum"] = row.get("datum", "")
        elif table_name == "v3_auth":
            metadata["tip"] = row.get("tip", "")
            metadata["ime"] = row.get("ime", "")
            metadata["cena_po_danu"] = float(row.get("cena_po_danu", 0) or 0)
        elif table_name == "v3_racuni":
            metadata["firma_naziv"] = row.get("firma_naziv", "")
            metadata["firma_pib"] = row.get("firma_pib", "")
            metadata["redni_broj"] = row.get("redni_broj", "")
            metadata["godina"] = row.get("godina", "")
            metadata["status"] = row.get("status", "")
        elif table_name == "v3_vozila":
            metadata["marka"] = row.get("marka", "")
            metadata["model"] = row.get("model", "")
            metadata["registracija"] = row.get("registracija", "")
            metadata["trenutna_km"] = float(row.get("trenutna_km", 0) or 0)
            metadata["mali_servis_km"] = float(row.get("mali_servis_km", 0) or 0)
            metadata["veliki_servis_km"] = float(row.get("veliki_servis_km", 0) or 0)
            metadata["plocice_prednje_km"] = float(row.get("plocice_prednje_km", 0) or 0)
            metadata["plocice_zadnje_km"] = float(row.get("plocice_zadnje_km", 0) or 0)
        elif table_name == "v3_operativna_nedelja":
            metadata["datum"] = row.get("datum", "")
            metadata["grad"] = row.get("grad", "")
            metadata["polazak_at"] = row.get("polazak_at", "")
            metadata["pokupljen_at"] = row.get("pokupljen_at", "")
            metadata["created_by"] = row.get("created_by", "")
            metadata["koristi_sekundarnu"] = bool(row.get("koristi_sekundarnu"))
            metadata["otkazano"] = bool(row.get("otkazano_by"))
    except Exception:
        pass

    # Opšti fallback: dodaj sve preostale kolone kao metadata (skalarno ili JSON)
    for key, value in row.items():
        if key in metadata or value is None:
            continue
        try:
            if isinstance(value, (str, int, float, bool)):
                metadata[key] = value
            elif isinstance(value, (dict, list)):
                metadata[key] = json.dumps(value, ensure_ascii=False, sort_keys=True)
            else:
                metadata[key] = str(value)
        except Exception:
            continue
    
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


def _content_signature(content: str) -> str:
    """Normalizovan potpis sadržaja za near-duplicate poređenje."""
    if not content:
        return ""
    normalized = content.lower()
    normalized = _UUID_LIKE_RE.sub("<uuid>", normalized)
    normalized = _DATE_LIKE_RE.sub("<date>", normalized)
    normalized = _NUMBER_LIKE_RE.sub("<num>", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    if len(normalized) > 500:
        normalized = normalized[:500]
    return normalized


def _is_signature_unchanged(cursor: sqlite3.Cursor, unique_id: str, new_signature: str) -> bool:
    """Proverava da li se sadržaj postojećeg reda suštinski nije promenio."""
    if not new_signature:
        return False
    cursor.execute("SELECT content FROM ai_knowledge_base WHERE id=?", (unique_id,))
    existing = cursor.fetchone()
    if not existing:
        return False
    return _content_signature(existing[0] or "") == new_signature


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
