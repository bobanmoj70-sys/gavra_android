"""
FastAPI Endpoints for Financial ML Model
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import pandas as pd
from datetime import datetime

from data.etl import extract_enriched_finances as extract_finances
from models.financial_model import FinancialMLModel
from api.financial_routes import router as financial_router, init_financial_model
from api.vozilo_routes import router as vozilo_router, init_vozilo_model, _vozilo_model
from api.gorivo_routes import router as gorivo_router, init_gorivo_model, _gorivo_model
from api.putnik_routes import router as putnik_router, init_putnik_model, _putnik_model
from api.zahtevi_routes import router as zahtevi_router, init_zahtevi_model, _zahtevi_model
from api.znanje_routes import router as znanje_router, init_znanje_model

app = FastAPI(title="Gavra ML API", version="3.0.0")

# Include all routers
app.include_router(financial_router)
app.include_router(vozilo_router)
app.include_router(gorivo_router)
app.include_router(putnik_router)
app.include_router(zahtevi_router)
app.include_router(znanje_router)

# Import financial model instance from router
from api.financial_routes import _financial_model

@app.on_event("startup")
async def startup_event():
    try:
        init_financial_model()
    except Exception as e:
        print(f"[WARN] init_financial_model failed: {e}")
    try:
        init_vozilo_model()
    except Exception as e:
        print(f"[WARN] init_vozilo_model failed: {e}")
    try:
        init_gorivo_model()
    except Exception as e:
        print(f"[WARN] init_gorivo_model failed: {e}")
    try:
        init_putnik_model()
    except Exception as e:
        print(f"[WARN] init_putnik_model failed: {e}")
    try:
        init_zahtevi_model()
    except Exception as e:
        print(f"[WARN] init_zahtevi_model failed: {e}")
    try:
        init_znanje_model()
    except Exception as e:
        print(f"[WARN] init_znanje_model failed: {e}")

# Pydantic models
class PredictionRequest(BaseModel):
    month: Optional[int] = None
    year: Optional[int] = None
    user_id: Optional[str] = None

class AnalysisRequest(BaseModel):
    days_back: int = 30

@app.get("/")
async def root():
    return {
        "message": "Gavra ML API (Finansije, Vozila, Gorivo, Putnici, Zahtevi)",
        "status": "running",
        "amount_model_trained": _financial_model.is_amount_trained,
        "type_model_trained": _financial_model.is_type_trained
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_trained": _financial_model.is_amount_trained and _financial_model.is_type_trained,
        "amount_model_trained": _financial_model.is_amount_trained,
        "type_model_trained": _financial_model.is_type_trained,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/memory")
async def memory_check():
    """Sta je financial model naucio - kao beba koja pamti"""
    return _financial_model.memory.get_learning_summary()

@app.get("/models/status")
async def models_status():
    """Status svih ML modela - sta su naucili, koliko su iskusni"""
    return {
        "timestamp": datetime.now().isoformat(),
        "models": {
            "financial": {
                "trained": _financial_model.is_amount_trained and _financial_model.is_type_trained,
                "memory": _financial_model.memory.get_learning_summary()
            },
            "vozilo": {
                "trained": _vozilo_model.is_trained,
                "memory": _vozilo_model.memory.get_learning_summary()
            },
            "gorivo": {
                "trained": _gorivo_model.is_trained,
                "memory": _gorivo_model.memory.get_learning_summary()
            },
            "putnik": {
                "trained": _putnik_model.is_trained,
                "memory": _putnik_model.memory.get_learning_summary()
            },
            "zahtevi": {
                "trained": _zahtevi_model.is_trained,
                "memory": _zahtevi_model.memory.get_learning_summary()
            }
        }
    }

@app.post("/retrain-all")
async def retrain_all():
    """
    Trenira SVE modele od nule - kao da su se rodili ispocetka.
    Uklanja staro pamcenje, ucimo sve iznova.
    """
    import time
    start = time.time()
    results = {}

    # Financial
    try:
        data = extract_finances()
        if data and len(data) > 0:
            _financial_model.train(data)
            _financial_model.save()
            results["financial"] = {"status": "trained", "tables": len(data), "memory": _financial_model.memory.get_learning_summary()}
        else:
            results["financial"] = {"status": "no_data"}
    except Exception as e:
        results["financial"] = {"status": "error", "message": str(e)}

    # Vozilo
    try:
        from data.etl_vozilo import extract_enriched_vozila as extract_vozila
        data = extract_vozila()
        if data and len(data) > 0:
            _vozilo_model.train(data)
            _vozilo_model.save()
            results["vozilo"] = {"status": "trained", "tables": len(data), "memory": _vozilo_model.memory.get_learning_summary()}
        else:
            results["vozilo"] = {"status": "no_data"}
    except Exception as e:
        results["vozilo"] = {"status": "error", "message": str(e)}

    # Gorivo
    try:
        from data.etl_gorivo import extract_enriched_gorivo as extract_gorivo
        data = extract_gorivo()
        if data and len(data) > 0:
            _gorivo_model.train(data)
            _gorivo_model.save()
            results["gorivo"] = {"status": "trained", "tables": len(data), "memory": _gorivo_model.memory.get_learning_summary()}
        else:
            results["gorivo"] = {"status": "no_data"}
    except Exception as e:
        results["gorivo"] = {"status": "error", "message": str(e)}

    # Putnik
    try:
        from data.etl_putnik import extract_enriched_putnik as extract_putnik
        data = extract_putnik()
        if data and len(data) > 0:
            _putnik_model.train(data)
            _putnik_model.save()
            results["putnik"] = {"status": "trained", "tables": len(data), "memory": _putnik_model.memory.get_learning_summary()}
        else:
            results["putnik"] = {"status": "no_data"}
    except Exception as e:
        results["putnik"] = {"status": "error", "message": str(e)}

    # Zahtevi
    try:
        from data.etl_zahtevi import extract_enriched_zahtevi as extract_zahtevi
        data = extract_zahtevi()
        if data and len(data) > 0:
            _zahtevi_model.train(data)
            _zahtevi_model.save()
            results["zahtev"] = {"status": "trained", "tables": len(data), "memory": _zahtevi_model.memory.get_learning_summary()}
        else:
            results["zahtev"] = {"status": "no_data"}
    except Exception as e:
        results["zahtev"] = {"status": "error", "message": str(e)}

    elapsed = round(time.time() - start, 2)
    return {
        "success": True,
        "message": f"Svi modeli su ponovo istrenirani od nule za {elapsed}s",
        "elapsed_seconds": elapsed,
        "results": results,
        "timestamp": datetime.now().isoformat()
    }

@app.post("/auto-train")
async def auto_train():
    """
    AUTOMATSKI trenira SVE modele - otkriva sve tabele, kolone, podatke
    Sistem sam uči od nule bez ikakvog ručnog podesavanja
    Poziva se kad se uđe u AI znanje ekran
    """
    import time
    import sys
    import os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'training'))
    
    from training.auto_train import auto_train_all
    
    start = time.time()
    try:
        results = auto_train_all()
        elapsed = round(time.time() - start, 2)
        
        return {
            "success": True,
            "message": f"Auto-training complete in {elapsed}s",
            "elapsed_seconds": elapsed,
            "results": results,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
