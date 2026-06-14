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
from api.vozilo_routes import router as vozilo_router, init_vozilo_model, _vozilo_model
from api.gorivo_routes import router as gorivo_router, init_gorivo_model, _gorivo_model
from api.putnik_routes import router as putnik_router, init_putnik_model, _putnik_model
from api.zahtevi_routes import router as zahtevi_router, init_zahtevi_model, _zahtevi_model
from api.znanje_routes import router as znanje_router, init_znanje_model

app = FastAPI(title="Gavra ML API", version="3.0.0")

# Include all routers
app.include_router(vozilo_router)
app.include_router(gorivo_router)
app.include_router(putnik_router)
app.include_router(zahtevi_router)
app.include_router(znanje_router)

# Initialize model
financial_model = FinancialMLModel()

@app.on_event("startup")
async def startup_event():
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

    # Always train from scratch on startup
    try:
        df = extract_finances()
        if len(df) > 0:
            financial_model.train(df)
            financial_model.save()
            print("[OK] Financial ML Model trained and saved from scratch")
        else:
            print("[WARN] No data available for training")
    except Exception as e:
        print(f"[WARN] Could not train financial model from scratch: {e}")
        try:
            financial_model.load()
            print("[OK] Financial ML Model loaded from saved file as fallback")
        except Exception as e2:
            print(f"[WARN] Could not load saved model either: {e2}")

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
        "amount_model_trained": financial_model.is_amount_trained,
        "type_model_trained": financial_model.is_type_trained
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_trained": financial_model.is_amount_trained and financial_model.is_type_trained,
        "amount_model_trained": financial_model.is_amount_trained,
        "type_model_trained": financial_model.is_type_trained,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/memory")
async def memory_check():
    """Sta je financial model naucio - kao beba koja pamti"""
    return financial_model.memory.get_learning_summary()

@app.get("/models/status")
async def models_status():
    """Status svih ML modela - sta su naucili, koliko su iskusni"""
    return {
        "timestamp": datetime.now().isoformat(),
        "models": {
            "financial": {
                "trained": financial_model.is_amount_trained and financial_model.is_type_trained,
                "memory": financial_model.memory.get_learning_summary()
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

@app.post("/predict/amount")
async def predict_amount(request: PredictionRequest):
    """
    Predikcija iznosa za buduće transakcije
    Model koristi naučeno znanje isključivo iz Supabase podataka
    """
    if not financial_model.is_amount_trained:
        raise HTTPException(status_code=400, detail="Amount model not trained. Call /train first.")

    try:
        # Extract current data for context
        df = extract_finances()

        # Filter by request parameters
        if request.month:
            df = df[df['mesec'] == request.month]
        if request.year:
            df = df[df['godina'] == request.year]
        if request.user_id:
            df = df[df['putnik_v3_auth_id'] == request.user_id]

        if len(df) == 0:
            return {
                "success": True,
                "prediction": 0,
                "message": "No matching data found"
            }

        # Predict
        predictions = financial_model.predict_amount(df)

        return {
            "success": True,
            "predictions": predictions[['iznos', 'predicted_amount']].to_dict('records'),
            "avg_predicted_amount": float(predictions['predicted_amount'].mean()),
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/predict/type")
async def predict_type(request: PredictionRequest):
    """
    Predikcija tipa transakcije (prihod/rashod)
    """
    if not financial_model.is_type_trained:
        raise HTTPException(status_code=400, detail="Type model not trained — need both 'prihod' and 'rashod' data in Supabase")
    
    try:
        df = extract_finances()
        
        if request.month:
            df = df[df['mesec'] == request.month]
        if request.year:
            df = df[df['godina'] == request.year]
        
        if len(df) == 0:
            return {
                "success": True,
                "predictions": [],
                "message": "No matching data found"
            }
        
        predictions = financial_model.predict_type(df)
        
        return {
            "success": True,
            "predictions": predictions[['tip', 'predicted_type', 'confidence']].to_dict('records'),
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/analyze/trends")
async def analyze_trends(request: AnalysisRequest):
    """
    Analizira finansijske trendove + anomalije
    """
    try:
        df = extract_finances()
        trends = financial_model.analyze_financial_trends(df)
        return {
            "success": True,
            "trends": trends,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/analyze/anomalies")
async def analyze_anomalies():
    """
    Detektuje anomalije u finansijskim transakcijama
    """
    try:
        df = extract_finances()
        if len(df) == 0:
            return {"success": True, "anomalies": [], "message": "No data"}
        anom_df = financial_model.detect_anomalies(df)
        anomalies = anom_df[anom_df.get('is_anomaly', 0) == 1][['naziv', 'iznos', 'tip', 'anomaly_score', 'anomaly_reason']].to_dict('records')
        return {
            "success": True,
            "anomaly_count": len(anomalies),
            "anomalies": anomalies[:20],
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/train")
async def train_model():
    """
    Trenira model na najnovijim podacima iz Supabase
    Model uči od nule bez pre-trained znanja
    """
    try:
        df = extract_finances()

        if len(df) == 0:
            raise HTTPException(status_code=400, detail="No data available in Supabase")

        metrics = financial_model.train(df)
        financial_model.save()
        
        return {
            "success": True,
            "message": "Model trained successfully",
            "metrics": metrics,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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
        df = extract_finances()
        if len(df) > 0:
            financial_model.train(df)
            financial_model.save()
            results["financial"] = {"status": "trained", "samples": len(df), "memory": financial_model.memory.get_learning_summary()}
        else:
            results["financial"] = {"status": "no_data"}
    except Exception as e:
        results["financial"] = {"status": "error", "message": str(e)}

    # Vozilo
    try:
        from data.etl_vozilo import extract_enriched_vozila as extract_vozila
        df = extract_vozila()
        if len(df) > 0:
            _vozilo_model.train(df)
            _vozilo_model.save()
            results["vozilo"] = {"status": "trained", "samples": len(df), "memory": _vozilo_model.memory.get_learning_summary()}
        else:
            results["vozilo"] = {"status": "no_data"}
    except Exception as e:
        results["vozilo"] = {"status": "error", "message": str(e)}

    # Gorivo
    try:
        from data.etl_gorivo import extract_enriched_gorivo as extract_gorivo
        df = extract_gorivo()
        if len(df) > 0:
            _gorivo_model.train(df)
            _gorivo_model.save()
            results["gorivo"] = {"status": "trained", "samples": len(df), "memory": _gorivo_model.memory.get_learning_summary()}
        else:
            results["gorivo"] = {"status": "no_data"}
    except Exception as e:
        results["gorivo"] = {"status": "error", "message": str(e)}

    # Putnik
    try:
        from data.etl_putnik import extract_finansije, extract_zahtevi
        fin = extract_finansije()
        zah = extract_zahtevi()
        if len(fin) > 0:
            _putnik_model.train(fin, zah)
            _putnik_model.save()
            results["putnik"] = {"status": "trained", "samples": len(fin), "memory": _putnik_model.memory.get_learning_summary()}
        else:
            results["putnik"] = {"status": "no_data"}
    except Exception as e:
        results["putnik"] = {"status": "error", "message": str(e)}

    # Zahtevi
    try:
        from data.etl_zahtevi import extract_enriched_zahtevi as extract_zahtevi
        df = extract_zahtevi()
        if len(df) > 0:
            _zahtevi_model.train(df)
            _zahtevi_model.save()
            results["zahtevi"] = {"status": "trained", "samples": len(df), "memory": _zahtevi_model.memory.get_learning_summary()}
        else:
            results["zahtevi"] = {"status": "no_data"}
    except Exception as e:
        results["zahtevi"] = {"status": "error", "message": str(e)}

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
