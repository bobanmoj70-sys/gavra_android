"""
AI Znanje (Knowledge Base) API Endpoints
Chat asistent koji odgovara na pitanja o podacima iz baze
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from data.etl_znanje import extract_all_tables, get_database_schema
from models.znanje_model import ZnanjeAIModel

router = APIRouter(prefix="/znanje", tags=["AI Znanje"])

_znanje_model = ZnanjeAIModel()


def init_znanje_model():
    """Inicijalizuje AI Znanje pri startup-u"""
    try:
        data = extract_all_tables()
        schema = get_database_schema()
        _znanje_model.train(data, schema)
        print("[OK] AI Znanje asistent spreman")
    except Exception as e:
        print(f"[WARN] AI Znanje init error: {e}")


class AskRequest(BaseModel):
    pitanje: str


class ReloadRequest(BaseModel):
    pass


@router.get("/health")
def health():
    return {
        "status": "healthy",
        "ready": _znanje_model.is_ready,
        "tables_loaded": len(_znanje_model.data_cache) if _znanje_model.is_ready else 0
    }


@router.post("/ask")
def ask_question(req: AskRequest):
    """Postavi pitanje AI asistentu"""
    if not _znanje_model.is_ready:
        raise HTTPException(status_code=503, detail="AI Znanje nije ucitao podatke")

    try:
        result = _znanje_model.ask(req.pitanje)
        return {
            "success": True,
            "pitanje": req.pitanje,
            **result
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
