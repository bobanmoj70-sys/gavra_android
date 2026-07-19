"""Gavra Backend: OSRM reverse proxy + prava neuronska mreža koja uči od nule.

Sav stari AI kod (RAG chat, embeddings, statistički "baby" učenik) je uklonjen.
Ostaje: (1) OSRM reverse proxy, (2) autentična neuronska mreža (autoenkoder,
ručni backpropagation, numpy — vidi neural_brain.py) koja se hrani SVIM redovima
iz SVIH tabela javne Supabase šeme, potpuno automatski otkrivenih (bez ijednog
hardkodovanog imena tabele), i uči iz njih od nule bez ijedne poslovne pretpostavke.
"""
from fastapi import FastAPI, HTTPException, Depends, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
import os
import sys
import json
import sqlite3
import asyncio
import logging
from logging.handlers import RotatingFileHandler
from datetime import datetime
from collections import deque
from contextlib import asynccontextmanager

import httpx
from dotenv import load_dotenv
from supabase._async.client import create_client as create_async_client, AsyncClient

import neural_brain
import entity_embeddings

# Učitavanje .env pre bilo kakve druge inicijalizacije
load_dotenv()

# Rekonfigurisanje standardnog izlaza za UTF-8 podršku na Windows-u
if sys.platform.startswith('win'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except AttributeError:
        pass

# --- KONFIGURACIJA IZ ENVIRONMENTA ---
ML_API_KEY = os.environ.get('ML_API_KEY')
PORT = int(os.environ.get('PORT', '8000'))
OSRM_LOCAL_URL = os.environ.get('OSRM_LOCAL_URL', 'http://127.0.0.1:5000')
SUPABASE_URL = os.environ.get('SUPABASE_URL')
SUPABASE_SERVICE_ROLE_KEY = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
SUPABASE_ANON_KEY = os.environ.get('SUPABASE_ANON_KEY')
SUPABASE_KEY = SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY

if not ML_API_KEY:
    raise RuntimeError('ML_API_KEY mora biti definisan u .env fajlu radi zaštite endpointa')

# Lokalna SQLite baza gde neuronska mreža čuva svoje težine i statistiku
DB_FILE = os.path.join(os.path.dirname(__file__), "gavra_ai.db")

# Koliko redova po tabeli maksimalno učitavamo u jednom istorijskom prolazu
HISTORY_PAGE_SIZE = 500
HISTORY_MAX_ROWS_PER_TABLE = 20000
# Koliko često (sekundi) se ponovo otkrivaju tabele i pokreće reconciliation prolaz
RESYNC_INTERVAL_SECONDS = 3600

# --- LOGOVANJE (konzola + memorija + rotirajući fajl) ---
LOG_FILE = os.path.join(os.path.dirname(__file__), "gavra_ai.log")
_file_logger = logging.getLogger("gavra_osrm_file")
_file_logger.setLevel(logging.INFO)
_file_logger.propagate = False

if not _file_logger.handlers:
    try:
        handler = RotatingFileHandler(LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=3, encoding='utf-8')
        handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
        _file_logger.addHandler(handler)
    except Exception as e:
        print(f"Nije moguće konfigurisati file logger: {e}")

live_logs = deque(maxlen=200)
# Živi tok "misli" neuronske mreže — poslednjih N odluka/zapažanja o SVAKOM redu koji
# je obradila (ne samo anomalije), radi transparentnog uvida u ponašanje u realnom vremenu.
neural_thoughts = deque(maxlen=100)
# Živi tok otkrivenih VEZA/predikcija (entity_embeddings) — šta mreža trenutno
# zaključuje o odnosima između vrednosti i predviđenim numeričkim kolonama.
neural_relations = deque(maxlen=100)


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
            pass
    live_logs.append(log_line)
    _file_logger.info(message)


# HTTP klijent za OSRM reverse proxy
osrm_client: httpx.AsyncClient | None = None

# Supabase klijent i pozadinski zadaci za hranjenje neuronske mreže
supabase: AsyncClient | None = None
realtime_task = None
resync_task = None
TABLES_TO_LEARN: list[str] = []


def init_local_db():
    """Priprema lokalnu SQLite bazu (šema neuronske mreže)."""
    conn = sqlite3.connect(DB_FILE)
    neural_brain.init_schema(conn)
    entity_embeddings.init_schema(conn)
    conn.commit()
    conn.close()


async def _discover_public_tables() -> list[str]:
    """Automatski otkriva SVE tabele/view-ove u 'public' šemi preko PostgREST OpenAPI
    opisa — bez ijednog ručno ukucanog imena tabele. Ovo je jedini način na koji ovaj
    servis 'zna' šta uopšte postoji da uči; nove tabele se automatski pridružuju bez
    izmene koda ili restarta (pokupi ih periodični _resync_loop)."""
    if not SUPABASE_URL or not SUPABASE_KEY:
        return []
    url = f"{SUPABASE_URL}/rest/v1/"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Accept": "application/openapi+json",
    }
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()
            spec = resp.json()
            paths = spec.get("paths", {})
            tables = sorted({
                path.strip("/") for path in paths.keys()
                if path.strip("/") and "/" not in path.strip("/")
            })
            return tables
    except Exception as e:
        log_event(f"Upozorenje: Auto-otkrivanje tabela nije uspelo: {e}")
        return []


async def _fetch_all_rows(table_name: str) -> list[dict]:
    """Dohvata sve redove iz tabele (paginirano) radi istorijskog učenja."""
    all_rows: list[dict] = []
    start = 0
    while len(all_rows) < HISTORY_MAX_ROWS_PER_TABLE:
        try:
            response = await supabase.table(table_name).select("*").range(start, start + HISTORY_PAGE_SIZE - 1).execute()
        except Exception as e:
            log_event(f"Upozorenje: Čitanje tabele {table_name} nije uspelo: {e}")
            break
        page = response.data or []
        if not page:
            break
        all_rows.extend(page)
        if len(page) < HISTORY_PAGE_SIZE:
            break
        start += HISTORY_PAGE_SIZE
    return all_rows


async def _learn_all_tables_historical():
    """Jednokratni (pri startu i periodično) prolaz kroz SVE otkrivene tabele —
    neuronska mreža radi po jedan korak učenja za svaki postojeći red."""
    global TABLES_TO_LEARN
    TABLES_TO_LEARN = await _discover_public_tables()
    if not TABLES_TO_LEARN:
        log_event("Upozorenje: Nijedna tabela nije otkrivena — neuronska mreža nema šta da uči.")
        return

    log_event(f"🔎 Otkriveno {len(TABLES_TO_LEARN)} tabela: {', '.join(TABLES_TO_LEARN)}")
    conn = sqlite3.connect(DB_FILE)
    total_learned = 0
    total_anomalies = 0

    for table_name in TABLES_TO_LEARN:
        rows = await _fetch_all_rows(table_name)
        if not rows:
            continue
        for row_data in rows:
            rid = str(row_data.get("id", ""))
            try:
                thought = neural_brain.observe_and_think(conn, table_name, row_data, rid)
                total_learned += 1
                if thought:
                    neural_thoughts.append(thought)
                    if thought["stage"] == "anomalija":
                        total_anomalies += 1
                        log_event(f"🧠 Neuronska mreža zapažanje: {thought['detail']}")
            except Exception as e:
                log_event(f"Upozorenje: Učenje nije uspelo za {table_name}:{rid}: {e}")
            try:
                relation = entity_embeddings.observe_and_relate(conn, table_name, row_data, rid)
                if relation:
                    neural_relations.append(relation)
            except Exception as e:
                log_event(f"Upozorenje: Učenje odnosa nije uspelo za {table_name}:{rid}: {e}")
        log_event(f"🧠 Naučeno {len(rows)} redova iz tabele {table_name}.")

    conn.close()
    log_event(f"🧠 Istorijsko učenje završeno. Ukupno {total_learned} redova, {total_anomalies} anomalija uočeno.")


async def _resync_loop():
    """Periodično ponovo otkriva tabele i uči iz njih — jedini razlog zašto nove tabele
    i novi redovi bivaju automatski uočeni bez restarta servera."""
    while True:
        await asyncio.sleep(RESYNC_INTERVAL_SECONDS)
        try:
            log_event("🔄 Pokrećem periodično osvežavanje učenja...")
            await _learn_all_tables_historical()
        except Exception as e:
            log_event(f"Greška tokom periodičnog osvežavanja učenja: {e}")


def _process_realtime_row_sync(table_name: str, row: dict):
    """Sinhrona obrada jednog realtime reda — mreža uči jedan korak iz njega."""
    rid = str(row.get("id", ""))
    conn = sqlite3.connect(DB_FILE)
    try:
        thought = neural_brain.observe_and_think(conn, table_name, row, rid)
        if thought:
            neural_thoughts.append(thought)
            if thought["stage"] == "anomalija":
                log_event(f"🧠 Neuronska mreža zapažanje (realtime): {thought['detail']}")
    except Exception as e:
        log_event(f"Upozorenje: Realtime učenje nije uspelo za {table_name}:{rid}: {e}")
    try:
        relation = entity_embeddings.observe_and_relate(conn, table_name, row, rid)
        if relation:
            neural_relations.append(relation)
    except Exception as e:
        log_event(f"Upozorenje: Realtime učenje odnosa nije uspelo za {table_name}:{rid}: {e}")
    finally:
        conn.close()


async def _process_realtime_event(payload: dict):
    table_name = payload.get("table")
    event_type = payload.get("eventType")
    new_record = payload.get("new") or {}
    if not table_name or event_type == "DELETE" or not new_record:
        return
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _process_realtime_row_sync, table_name, new_record)


async def _start_realtime_sync():
    """Pokreće beskonačnu petlju sa reconnect logikom, prisluškuje SVE otkrivene tabele."""
    backoff_seconds = 5
    max_backoff = 300
    while True:
        try:
            if not TABLES_TO_LEARN:
                await asyncio.sleep(10)
                continue

            log_event("Uspostavljam vezu sa Supabase Realtime WebSocket klijentom...")

            def handle_db_change(payload):
                asyncio.create_task(_process_realtime_event(payload))

            channel = supabase.channel("realtime-neural-learning")
            for table_name in TABLES_TO_LEARN:
                channel.on_postgres_changes(event="*", schema="public", table=table_name, callback=handle_db_change)

            subscribe_done = asyncio.Event()
            subscribe_result: dict = {"status": None}
            loop = asyncio.get_event_loop()

            def on_subscribe(status, error=None):
                subscribe_result["status"] = status
                loop.call_soon_threadsafe(subscribe_done.set)

            await channel.subscribe(on_subscribe)
            try:
                await asyncio.wait_for(subscribe_done.wait(), timeout=15)
            except asyncio.TimeoutError:
                raise RuntimeError("Realtime subscribe potvrda nije stigla na vreme")

            status_name = getattr(subscribe_result["status"], "value", str(subscribe_result["status"]))
            if status_name != "SUBSCRIBED":
                raise RuntimeError(f"Realtime subscribe nije uspeo: {status_name}")

            log_event("🟢 Realtime kanal potvrđen — neuronska mreža sada uči u realnom vremenu iz svih tabela.")
            backoff_seconds = 5

            while True:
                await asyncio.sleep(30)
                is_joined = getattr(channel, 'is_joined', None)
                if is_joined is False:
                    log_event("🟡 Realtime kanal više nije aktivan. Pokušavam reconnect...")
                    break
        except Exception as e:
            log_event(f"🔴 Realtime greška: {e}")

        log_event(f"⏳ Ponovni pokušaj konekcije za {backoff_seconds}s...")
        await asyncio.sleep(backoff_seconds)
        backoff_seconds = min(backoff_seconds * 2, max_backoff)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager — inicijalizuje OSRM proxy i pokreće neuronsku mrežu."""
    global osrm_client, supabase, realtime_task, resync_task

    init_local_db()
    log_event("Lokalna SQLite baza (neuronska mreža) je inicijalizovana.")

    osrm_client = httpx.AsyncClient(base_url=OSRM_LOCAL_URL, timeout=30.0)
    log_event(f"OSRM reverse proxy klijent inicijalizovan za {OSRM_LOCAL_URL}.")

    if SUPABASE_URL and SUPABASE_KEY:
        try:
            supabase = await create_async_client(SUPABASE_URL, SUPABASE_KEY)
            log_event("Supabase konekcija uspešno otvorena — neuronska mreža počinje da uči.")
            asyncio.create_task(_learn_all_tables_historical())
            realtime_task = asyncio.create_task(_start_realtime_sync())
            resync_task = asyncio.create_task(_resync_loop())
        except Exception as e:
            log_event(f"Upozorenje: Supabase konekcija nije uspela, neuronska mreža neće učiti: {e}")
    else:
        log_event("Upozorenje: SUPABASE_URL/KEY nisu podešeni — neuronska mreža neće učiti (samo OSRM proxy aktivan).")

    yield

    if osrm_client:
        await osrm_client.aclose()
        osrm_client = None
        log_event("OSRM reverse proxy klijent zatvoren.")
    if realtime_task:
        realtime_task.cancel()
        try:
            await realtime_task
        except asyncio.CancelledError:
            pass
    if resync_task:
        resync_task.cancel()
        try:
            await resync_task
        except asyncio.CancelledError:
            pass
    log_event("Servis je uspešno zaustavljen.")


app = FastAPI(title="Gavra OSRM Proxy", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- AUTENTIKACIJA ---
api_key_header = APIKeyHeader(name='X-API-Key', auto_error=False)


async def verify_api_key(request: Request, api_key: str = Depends(api_key_header)):
    # Dozvoljavamo root health check bez ključa
    if request.url.path == '/':
        return True
    if api_key != ML_API_KEY:
        raise HTTPException(status_code=401, detail='Nevažeći API ključ')
    return True


app.router.dependencies.append(Depends(verify_api_key))


# --- ENDPOINTI ---
@app.get("/")
def read_root():
    return {
        "status": "active",
        "service": "Gavra OSRM Proxy + Neuronska mreža",
        "logs_cached": len(live_logs),
        "tables_learning": len(TABLES_TO_LEARN),
    }


@app.get("/logs")
def get_logs():
    return {"logs": list(live_logs)}


@app.get("/neural")
def get_neural_report():
    """Izveštaj o stanju neuronske mreže: koliko je tabela/redova naučila, prosečna
    reconstruction greška po tabeli i poslednje uočene anomalije (neobične kombinacije
    vrednosti u redu)."""
    conn = sqlite3.connect(DB_FILE)
    try:
        report = neural_brain.get_report(conn)
    finally:
        conn.close()
    return report


@app.get("/neural/thoughts")
def get_neural_thoughts():
    """Živi tok 'razmišljanja' neuronske mreže — šta trenutno misli/zaključuje o SVAKOM
    redu koji obrađuje (ne samo o anomalijama). Za svaki red vraća: stepen poznatosti
    (uci / vrlo_poznato / normalno / neuobicajeno / anomalija), reconstruction grešku,
    z-skor i čitljivo objašnjenje. Najnoviji su prvi."""
    return {"thoughts": list(reversed(neural_thoughts))}


@app.get("/neural/relations")
def get_neural_relations():
    """Izveštaj o naučenim ODNOSIMA (embeddinzima): za svaku tabelu, koliko različitih
    vrednosti (tokena) je viđeno, najfrekventniji tokeni, i koje numeričke kolone se
    trenutno predviđaju iz konteksta ostatka reda."""
    conn = sqlite3.connect(DB_FILE)
    try:
        report = entity_embeddings.get_report(conn)
    finally:
        conn.close()
    return report


@app.get("/neural/relations/live")
def get_neural_relations_live():
    """Živi tok poslednjih obrađenih redova: koliko je tokena mreža prepoznala u redu, i
    za svaku numeričku kolonu — predviđena vs stvarna vrednost (regresija iz konteksta)."""
    return {"relations": list(reversed(neural_relations))}


@app.get("/neural/similar")
def get_similar_tokens(table: str, token: str, top_n: int = 8):
    """Vraća tokene koje je mreža SAMA naučila da su najsličniji datom tokenu (npr.
    token='grad=Beograd') — konkretan, proverljiv dokaz otkrivenih veza u podacima.
    Primer: GET /neural/similar?table=v3_gorivo&token=nacin_placanja=kartica"""
    conn = sqlite3.connect(DB_FILE)
    try:
        similar = entity_embeddings.find_similar(conn, table, token, top_n=top_n)
    finally:
        conn.close()
    return {"table": table, "token": token, "similar": similar}


@app.post("/neural/reset")
def reset_neural_brain():
    """Briše SVE naučene težine i statistiku (i anomalije i naučene odnose) — mreža se
    ponovo rađa nasumično inicijalizovana."""
    conn = sqlite3.connect(DB_FILE)
    try:
        neural_brain.reset_brain(conn)
        entity_embeddings.reset_brain(conn)
    finally:
        conn.close()
    neural_thoughts.clear()
    neural_relations.clear()
    log_event("🧠 Neuronska mreža je resetovana na zahtev — sve težine su ponovo nasumične.")
    return {"status": "reset"}


@app.post("/resync")
async def trigger_resync():
    """Ručno pokreće ponovno otkrivanje tabela i istorijsko učenje (bez čekanja na periodični ciklus)."""
    asyncio.create_task(_learn_all_tables_historical())
    return {"status": "resync pokrenut u pozadini"}


@app.api_route("/osrm/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"])
async def osrm_proxy(request: Request, path: str):
    """Reverse proxy za OSRM backend. Tailscale Funnel /osrm -> /osrm/* -> lokalni OSRM:5000/*"""
    if not osrm_client:
        raise HTTPException(status_code=503, detail="OSRM reverse proxy nije inicijalizovan")

    try:
        url = httpx.URL(path=f"/{path}", query=request.url.query.encode("utf-8"))

        headers = {}
        for key, value in request.headers.items():
            if key.lower() in ("host", "content-length", "transfer-encoding"):
                continue
            headers[key] = value

        body = await request.body()

        rp_resp = await osrm_client.request(
            method=request.method,
            url=url,
            headers=headers,
            content=body,
        )

        return Response(
            content=rp_resp.content,
            status_code=rp_resp.status_code,
            headers={
                k: v for k, v in rp_resp.headers.items()
                if k.lower() not in ("content-encoding", "transfer-encoding", "content-length")
            },
            media_type=rp_resp.headers.get("content-type"),
        )
    except httpx.RequestError as e:
        log_event(f"OSRM proxy greška: {e}")
        raise HTTPException(status_code=502, detail=f"OSRM nije dostupan: {e}")
    except Exception as e:
        log_event(f"Neočekivana OSRM proxy greška: {e}")
        raise HTTPException(status_code=500, detail=f"OSRM proxy greška: {e}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
