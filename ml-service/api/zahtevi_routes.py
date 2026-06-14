"""
Zahtevi ML API Endpoints
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pandas as pd
from fastapi import APIRouter, HTTPException
from data.etl_zahtevi import extract_enriched_zahtevi
from models.zahtevi_model import ZahteviMLModel

router = APIRouter(prefix="/zahtevi", tags=["Zahtevi AI"])

_zahtevi_model = ZahteviMLModel()


def init_zahtevi_model():
    try:
        df = extract_enriched_zahtevi()
        if len(df) > 0:
            _zahtevi_model.train(df)
            _zahtevi_model.save()
        else:
            print("[WARN] No data for zahtevi model training")
    except Exception as e:
        print(f"[WARN] Could not auto-train zahtevi model: {e}")


@router.get("/health")
def health():
    return {
        "status": "healthy",
        "model_trained": _zahtevi_model.is_trained,
        "ensemble_enabled": True,
        "xgboost_available": True
    }


@router.get("/memory")
def memory():
    """Sta je zahtevi model naucio - kao beba koja pamti"""
    return _zahtevi_model.memory.get_learning_summary()


@router.get("/predict/next-week")
def predict_next_week():
    if not _zahtevi_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    data = extract_enriched_zahtevi()
    if not data or data.get('zahtevi', pd.DataFrame()).empty:
        raise HTTPException(status_code=404, detail="No request data")
    return _zahtevi_model.predict_next_week(data)


@router.get("/analyze/trends")
def analyze_trends():
    data = extract_enriched_zahtevi()
    if not data or data.get('zahtevi', pd.DataFrame()).empty:
        raise HTTPException(status_code=404, detail="No request data")
    if not _zahtevi_model.is_trained:
        _zahtevi_model.train(data)
        _zahtevi_model.save()
    return _zahtevi_model.analyze_trends(data.get('zahtevi', pd.DataFrame()))


@router.post("/train")
def train_model():
    data = extract_enriched_zahtevi()
    if not data or data.get('zahtevi', pd.DataFrame()).empty:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _zahtevi_model.train(data)
    _zahtevi_model.save()
    return {"status": "trained", **metrics}
