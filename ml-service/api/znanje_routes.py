"""
AI Znanje (Knowledge Base) API Endpoints
Chat asistent koji odgovara na pitanja o podacima iz baze
"""
import sys, os, threading, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from data.etl_znanje import extract_all_tables, get_database_schema
from models.znanje_model import ZnanjeAIModel
from services.gemini_service import GeminiService

router = APIRouter(prefix="/znanje", tags=["AI Znanje"])

_znanje_model = ZnanjeAIModel()
_gemini_service = GeminiService()


def _load_znanje_data():
    """Ucitava podatke i trenira model. Vraca True ako uspe."""
    try:
        data = extract_all_tables()
        schema = get_database_schema()
        _znanje_model.train(data, schema)
        print("[OK] AI Znanje asistent spreman")
        return True
    except Exception as e:
        print(f"[WARN] AI Znanje load error: {e}")
        return False


def _background_retry():
    """Background thread koji ponavlja ucitavanje svakih 30s dok ne uspe."""
    retry_interval = 30
    while not _znanje_model.is_ready:
        time.sleep(retry_interval)
        print("[Znanje] Retry ucitavanja podataka...")
        if _load_znanje_data():
            break


def init_znanje_model():
    """Inicijalizuje AI Znanje pri startup-u, pokrece retry u pozadini ako ne uspe."""
    if not _load_znanje_data():
        t = threading.Thread(target=_background_retry, daemon=True)
        t.start()
        print("[Znanje] Background retry pokrenut (svakih 30s)")


class AskRequest(BaseModel):
    pitanje: str


class ReloadRequest(BaseModel):
    pass


@router.get("/health")
def health():
    stats = {}
    if _znanje_model.is_ready and _znanje_model.data_cache:
        for table, df in _znanje_model.data_cache.items():
            stats[table] = len(df)
    total_records = sum(stats.values()) if stats else 0
    return {
        "status": "healthy",
        "ready": _znanje_model.is_ready,
        "tables_loaded": len(_znanje_model.data_cache) if _znanje_model.is_ready else 0,
        "total_records": total_records,
        "table_stats": stats,
        "gemini_available": _gemini_service.is_available(),
        "server": "AI Znanje - Generalni Asistent"
    }


@router.post("/ask")
def ask_question(req: AskRequest):
    """Postavi pitanje AI asistentu — prvo proba Gemini, fallback na lokalni sistem"""
    if not _znanje_model.is_ready:
        raise HTTPException(status_code=503, detail="AI Znanje nije ucitao podatke")

    try:
        # PRVO: probaj Google Gemini (pametniji, prirodniji odgovori)
        if _gemini_service.is_available():
            context = _znanje_model.build_context_for_llm(req.pitanje)
            gemini_result = _gemini_service.ask(req.pitanje, context)
            if gemini_result['tip'] == 'gemini':
                return {
                    "success": True,
                    "pitanje": req.pitanje,
                    "odgovor": gemini_result['odgovor'],
                    "tip": "gemini",
                    "source": "google_gemini_flash"
                }

        # FALLBACK: stari sistem (embeddings + regex + rule-based)
        result = _znanje_model.ask(req.pitanje)
        return {
            "success": True,
            "pitanje": req.pitanje,
            **result,
            "source": "local_znanje_ai"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/reload")
def reload_data():
    """Osvezi podatke iz baze"""
    try:
        data = extract_all_tables()
        schema = get_database_schema()
        result = _znanje_model.train(data, schema)
        return {"success": True, **result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/train")
def train_model():
    """Alias za reload - ponovo uci sve podatke"""
    return reload_data()
