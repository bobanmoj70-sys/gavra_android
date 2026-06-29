from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import ollama
from supabase._async.client import create_client as create_async_client, AsyncClient
import os
import sys
import sqlite3
import json
import asyncio
from datetime import datetime
from sentence_transformers import SentenceTransformer
import numpy as np

# Rekonfigurisanje standardnog izlaza za UTF-8 podršku na Windows-u radi sprečavanja UnicodeEncodeError rušenja
if sys.platform.startswith('win'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except AttributeError:
        pass  # Starije verzije Pythona

# Supabase kredencijali
SUPABASE_URL = "https://gjtabtwudbrmfeyjiicu.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdqdGFidHd1ZGJybWZleWppaWN1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc0MzYyOTIsImV4cCI6MjA2MzAxMjI5Mn0.TwAfvlyLIpnVf-WOixvApaQr6NpK9u-VHpRkmbkAKYk"

# Lokalne SQLite baze
DB_FILE = os.path.join(os.path.dirname(__file__), "gavra_ai.db")

app = FastAPI(title="Gavra Realtime AI Backend")

# CORS podrška za komunikaciju sa mobilnim i drugim klijentima
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Globalni objekti
supabase: AsyncClient = None
embedder = None
live_logs = []  # Lista za čuvanje zadnjih 50 logova učenja u memoriji
realtime_task = None

class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    response: str
    sources: list = []

class LogResponse(BaseModel):
    logs: list

class InsightResponse(BaseModel):
    insights: list

# --- INICIJALIZACIJA LOKALNE SQLite BAZE ---
def init_local_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
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
            # Ako print baci UnicodeEncodeError, ispisujemo u standardnom izlazu sa zamenom karaktera
            cleaned_line = log_line.encode(sys.stdout.encoding or 'utf-8', errors='replace').decode(sys.stdout.encoding or 'utf-8')
            print(cleaned_line)
        except Exception:
            # Krajnja sigurna varijanta koja eliminiše sve nestandardne karaktere
            try:
                print(log_line.encode('ascii', errors='ignore').decode('ascii'))
            except Exception:
                pass
    live_logs.append(log_line)
    if len(live_logs) > 50:
        live_logs.pop(0)

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

        # Opšta pretraga za ostale tabele
        else:
            clean_fields = {k: v for k, v in row.items() if v is not None and k not in ['id', 'created_at', 'updated_at']}
            return f"Podatak iz tabele '{table_name}': {json.dumps(clean_fields, ensure_ascii=False)}."
            
    except Exception as e:
        return f"Greška pri parsiranju reda iz tabele {table_name}: {e}"

# --- FUNKCIJA ZA ANALIZU I DETEKCIJU ANOMALIJA (SAM ZAKLJUČUJE ŠTA JE BITNO) ---
def analyze_and_detect_insights():
    """Prolazi kroz lokalnu SQLite bazu i samostalno traži nepravilnosti, skokove, anomalije i zaključke"""
    try:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        # Očistimo stare nominalne zaključke (da uvek generišemo sveže), kritične čuvamo
        cursor.execute("DELETE FROM ai_insights WHERE severity != 'critical'")
        
        # 1. ANALIZA TROŠKOVA GORIVA (v3_gorivo)
        cursor.execute("SELECT content FROM ai_knowledge_base WHERE source_table='v3_gorivo'")
        fuel_rows = cursor.fetchall()
        
        amounts = []
        liters = []
        for (content,) in fuel_rows:
            try:
                # Pokušavamo da izvučemo iznose iz teksta
                # Format: "... litara goriva u vrednosti od {iznos} RSD"
                parts = content.split("vrednosti od ")
                if len(parts) > 1:
                    iznos = float(parts[1].split(" RSD")[0])
                    amounts.append(iznos)
                lp_parts = content.split("sipano ")
                if len(lp_parts) > 1:
                    litera = float(lp_parts[1].split(" litara")[0])
                    liters.append(litera)
            except:
                continue
        
        if amounts:
            avg_fuel = sum(amounts) / len(amounts)
            max_fuel = max(amounts)
            
            # Ako je neko sipanje preko 50% skuplje od proseka, zavedi anomaliju
            for (content,) in fuel_rows:
                try:
                    parts = content.split("vrednosti od ")
                    iznos = float(parts[1].split(" RSD")[0])
                    if iznos > avg_fuel * 1.5:
                        # Pronađimo ID originalnog zapisa
                        cursor.execute("SELECT source_id FROM ai_knowledge_base WHERE content=?", (content,))
                        sid = cursor.fetchone()
                        sid = sid[0] if sid else ""
                        
                        cursor.execute("""
                            INSERT INTO ai_insights (title, description, source_table, source_id, severity, created_at)
                            VALUES (?, ?, ?, ?, ?, ?)
                        """, (
                            "Uočena anomalija u trošku za gorivo",
                            f"Registrovan je izuzetno visok trošak goriva u iznosu od {iznos} RSD, što drastično odudara od prosečnog sipanja koje iznosi {avg_fuel:.1f} RSD.",
                            "v3_gorivo",
                            sid,
                            "significant",
                            datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        ))
                except:
                    continue

        # 2. ANALIZA SVEUKUPNIH RAČUNA I FINANSIJA (Rashodi naspram prihoda)
        cursor.execute("SELECT content FROM ai_knowledge_base WHERE source_table='v3_finansije'")
        fin_rows = cursor.fetchall()
        
        rashodi = 0
        prihodi = 0
        n_rashod = 0
        n_prihod = 0
        
        for (content,) in fin_rows:
            try:
                # Format: "Finansije ({TIP}): Transakcija '{naziv}' iznosi {iznos} RSD."
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
                
        if rashodi > zero_if_error(prihodi) and rashodi > 0:
            cursor.execute("""
                INSERT INTO ai_insights (title, description, source_table, source_id, severity, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                "Rashodi premašili prihode",
                f"Ukupni zabeleženi rashodi u bazi iznose {rashodi:.1f} RSD kroz {n_rashod} transakcija, dok su prihodi {prihodi:.1f} RSD. Kompanija posluje sa deficitom u ovom posmatranom periodu.",
                "v3_finansije",
                "",
                "significant",
                datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            ))
        elif prihodi > 0:
            cursor.execute("""
                INSERT INTO ai_insights (title, description, source_table, source_id, severity, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                "Stabilan finansijski bilans",
                f"Prihodi iznose ukupno {prihodi:.1f} RSD, dok su rashodi uspešno zadržani na {rashodi:.1f} RSD. Neto profit iznosi {(prihodi-rashodi):.1f} RSD.",
                "v3_finansije",
                "",
                "nominal",
                datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            ))

        # 3. ANALIZA ZAHTEVA PO GRADOVIMA (Sam zaključuje gde ima najviše zahteva)
        cursor.execute("SELECT content FROM ai_knowledge_base WHERE source_table='v3_zahtevi'")
        req_rows = cursor.fetchall()
        
        gradovi = {}
        for (content,) in req_rows:
            try:
                # Format: "... Relacija/Grad: {grad}..."
                if "Relacija/Grad: " in content:
                    grad = content.split("Relacija/Grad: ")[1].split(".")[0].strip()
                    gradovi[grad] = gradovi.get(grad, 0) + 1
            except:
                continue
                
        if gradovi:
            omiljeni_grad = max(gradovi, key=gradovi.get)
            ukupno_zahteva = sum(gradovi.values())
            procenat = (gradovi[omiljeni_grad] / ukupno_zahteva) * 100
            
            cursor.execute("""
                INSERT INTO ai_insights (title, description, source_table, source_id, severity, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                f"Dominantno gradsko tržište: {omiljeni_grad}",
                f"Grad sa ubedljivo najvećim brojem zahteva za transport je {omiljeni_grad} sa ukupno {gradovi[omiljeni_grad]} vožnji, što predstavlja {procenat:.1f}% od ukupnih zahteva u aplikaciji.",
                "v3_zahtevi",
                "",
                "nominal",
                datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            ))

        conn.commit()
        conn.close()
        log_event("Analiza baze uspešno izvršena. Generisani novi samostalni zaključci.")
    except Exception as e:
        log_event(f"Greška tokom izvršavanja analize zaključaka: {e}")

def zero_if_error(val):
    return val if val else 0

# --- UČENJE PROŠLOSTI (ISTORIJSKA SINHRONIZACIJA) ---
async def learn_past_data():
    """Jednokratno povlačenje svih istorijskih podataka iz Supabase-a i upisivanje u lokalnu SQLite bazu"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # Provera da li smo već sinhronizovali istoriju
    cursor.execute("SELECT val FROM sync_status WHERE key='history_synced'")
    synced = cursor.fetchone()
    
    if synced and synced[0] == "true":
        log_event("Istorijski podaci su već sinhronizovani. Preskačem istorijsko učenje.")
        conn.close()
        # Ipak pokrećemo analizu zaključaka da osiguramo ažurnost pri startu
        analyze_and_detect_insights()
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
                        # Vektorizacija teksta pomoću SentenceTransformera
                        emb = embedder.encode(content_text).tolist()
                        embedding_str = json.dumps(emb)
                    
                    # Generisanje jedinstvenog ID-ja u SQLite-u
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
            
    # Označavamo status sinhronizacije kao završen
    cursor.execute("INSERT OR REPLACE INTO sync_status (key, val) VALUES ('history_synced', 'true')")
    conn.commit()
    conn.close()
    
    log_event(f"Istorijsko učenje završeno! Ukupno naučeno {total_rows} poslovnih događaja.")
    
    # Pokrećemo prvu analizu zaključaka na osnovu sakupljenog istorijskog blaga
    analyze_and_detect_insights()

# --- REALTIME ASINHRONI LISTENERS (UČENJE U REALNOM VREMENU) ---
async def start_realtime_sync():
    """Pokreće beskonačnu async petlju koja osluškuje WebSocket promene i uči u pozadini"""
    log_event("Uspostavljam vezu sa Supabase Realtime WebSocket klijentom...")
    
    def handle_db_change(payload):
        # Callback prima sirove promene
        asyncio.create_task(process_realtime_event(payload))
        
    try:
        channel = supabase.channel("realtime-ai-learning")
        channel.on_postgres_changes(
            event="*",
            schema="public",
            callback=handle_db_change
        )
        await channel.subscribe()
        log_event("🟢 Realtime mrežni kanal je uspešno otvoren i sada aktivno sluša sve tabele u sistemu!")
    except Exception as e:
        log_event(f"🔴 Neuspešno otvaranje Realtime kanala: {e}")

async def process_realtime_event(payload: dict):
    """Procesira i uči pojedinačne realtime događaje upisom u SQLite"""
    try:
        event_type = payload.get("eventType")
        table_name = payload.get("table")
        
        # ID zapisa
        new_record = payload.get("new") or {}
        old_record = payload.get("old") or {}
        
        rid = str(new_record.get("id") or old_record.get("id") or "")
        if not rid or not table_name:
            return
            
        unique_id = f"{table_name}:{rid}"
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        
        # 1. DELETE Događaj
        if event_type == "DELETE":
            cursor.execute("DELETE FROM ai_knowledge_base WHERE id=?", (unique_id,))
            conn.commit()
            log_event(f"🗑️ Podatak uklonjen iz baze (DELETE iz {table_name}). Automatski zaboravljam događaj.")
            
        # 2. INSERT / UPDATE Događaj
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
        
        # Nakon svake izmene, asinhrono okidamo re-kalkulaciju anomalija
        analyze_and_detect_insights()
        
    except Exception as e:
        log_event(f"Greška pri obradi Realtime događaja učenja: {e}")


# --- FASTAPI ENDPOINTI ---

@app.on_event("startup")
async def startup_event():
    global supabase, embedder, realtime_task
    
    # 1. Inicijalizacija SQLite baze
    init_local_db()
    log_event("Lokalna SQLite baza podataka je inicijalizovana.")
    
    # 2. Kreiranje asinhronog Supabase klijenta
    supabase = await create_async_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    log_event("Supabase asinhrona konekcija uspešno otvorena.")
    
    # 3. Učitavanje SentenceTransformer-a za semantiku
    try:
        log_event("Učitavam SentenceTransformer model ('all-MiniLM-L6-v2') za semantičko razumevanje...")
        embedder = SentenceTransformer('all-MiniLM-L6-v2')
        log_event("Semantički model uspešno pokrenut i uskladišten.")
    except Exception as e:
        log_event(f"Upozorenje: Nije moguće podići SentenceTransformer: {e}. Koristićemo klasične SQLite LIKE pretrage.")
        
    # 4. Istorijsko učenje
    asyncio.create_task(learn_past_data())
    
    # 5. Pokretanje WebSocket Realtime sync-a
    realtime_task = asyncio.create_task(start_realtime_sync())

@app.on_event("shutdown")
async def shutdown_event():
    # Zatvaranje resursa pri gašenju
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
    return LogResponse(logs=live_logs)

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

@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Glavni pretraživač i generator pametnih odgovora koristeći Llama 3.2 i lokalnu pretragu"""
    try:
        usr_msg = request.message
        log_event(f"Korisnički upit: '{usr_msg}'")
        
        # 1. Semantička i hibridna pretraga unutar lokalne SQLite baze naučenih podataka
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        cursor.execute("SELECT id, content, embedding FROM ai_knowledge_base")
        kb_rows = cursor.fetchall()
        conn.close()
        
        # Spisak relevantnih zapisa
        matched_content = []
        
        if kb_rows:
            # Ako imamo embedder, uradićemo Kosinusnu semantičku sličnost
            if embedder:
                q_emb = embedder.encode(usr_msg)
                scores = []
                for kid, content, emb_json in kb_rows:
                    if emb_json:
                        emb = np.array(json.loads(emb_json))
                        # Kosinusna sličnost
                        dot_product = np.dot(q_emb, emb)
                        norm_q = np.linalg.norm(q_emb)
                        norm_emb = np.linalg.norm(emb)
                        score = dot_product / (norm_q * norm_emb) if norm_q > 0 and norm_emb > 0 else 0
                        scores.append((score, content))
                
                # Sortiramo i uzimamo top 15 najrelevantnijih zapisa iz istorije i realtime učenja
                scores.sort(key=lambda x: x[0], reverse=True)
                top_matches = scores[:15]
                log_event(f"Semantička pretraga nad SQLite bazom završena. Najbolji score: {top_matches[0][0]:.3f}" if top_matches else "Nema poklapanja.")
                
                matched_content = [item[1] for item in top_matches if item[0] > 0.15]
            
            # Bez obzira na semantiku, radimo i brzu tekstualnu pretragu (npr. ključne reči "BC", "VS", vremena, imena)
            words = usr_msg.lower().split()
            keywords = [w for w in words if len(w) > 2 and w not in ["ili", "sam", "kod", "bilo", "sve"]]
            
            if keywords:
                text_matches = []
                for kid, content, _ in kb_rows:
                    content_lower = content.lower()
                    match_count = sum(1 for kw in keywords if kw in content_lower)
                    if match_count > 0:
                        text_matches.append((match_count, content))
                
                text_matches.sort(key=lambda x: x[0], reverse=True)
                # Spajamo rezultate bez duplikata
                for _, content in text_matches[:10]:
                    if content not in matched_content:
                        matched_content.append(content)

        # Trinaest najvažnijih spajamo u jedan String konteksta
        context_str = "\n".join([f"- {content}" for content in matched_content[:15]])
        
        # 2. DEFINISANJE ISTINE: Strog System Prompt koji mu nalaže da ako podatak ne postoji u bazi, ne izmišlja!
        system_prompt = (
            "Ti si Gavra AI, visoko stručni i pouzdani analitički sistem za logistiku i transport, razvijen isključivo za vlasnika aplikacije.\n"
            "Tvoj zadatak je da odgovaraš na pitanja isključivo na osnovu sledećih sirovih podataka dobijenih iz tabela u realnom vremenu:\n"
            "-------------------\n"
            f"{context_str if context_str else 'U bazi trenutno nema zabeleženih relevantnih podataka za ovo pitanje.'}\n"
            "-------------------\n"
            "STROLGA PRAVILA ZA ODGOVARANJE:\n"
            "1. Odgovaraj ISKLJUČIVO na osnovu gore navedenih podataka o finansijama, vožnjama, putnicima, vozačima i gorivu.\n"
            "2. Ukoliko odgovor na pitanje ne može da se izvuče iz dostavljenih sirovih podataka, tvoj jedini odgovor MORA biti: \n"
            "   'Oprostite, nemam te podatke u svojoj bazi podataka.'\n"
            "3. Nemoj izmišljati, pretpostavljati niti dopunjavati podatke opštim znanjem sa interneta! Ako ne vidiš tačne brojeve ili imena u kontekstu, za tebe oni ne postoje.\n"
            "4. Piši odgovore tečnim, prijatnim i profesionalnim srpskim jezikom, sa uvažavanjem i bez suvišnog filozofiranja."
        )
        
        log_event("Šaljem upit lokalnom Llama 3.2 modelu na Ollama server...")
        
        # Poziv lokalnog Ollama klijenta
        response = ollama.chat(
            model='llama3.2',
            messages=[
                {'role': 'system', 'content': system_prompt},
                {'role': 'user', 'content': usr_msg}
            ]
        )
        
        ai_resp = response['message']['content']
        log_event("Odgovor od Llama 3.2 modela uspešno generisan i vraćen.")
        
        return ChatResponse(
            response=ai_resp,
            sources=matched_content[:5]
        )
        
    except Exception as e:
        log_event(f"Greška tokom izvršavanja chat upita: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # Pokrećemo server na svim adresama na portu 8000
    uvicorn.run(app, host="0.0.0.0", port=8000)
