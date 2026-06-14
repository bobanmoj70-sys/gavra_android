"""
Gorivo ML API Endpoints
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pandas as pd
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from data.etl_gorivo import extract_enriched_gorivo as extract_gorivo
from models.gorivo_model import GorivoMLModel

router = APIRouter(prefix="/gorivo", tags=["Gorivo AI"])

_gorivo_model = GorivoMLModel()


def init_gorivo_model():
    try:
        data = extract_gorivo()
        if data and len(data) > 0:
            _gorivo_model.train(data)
            _gorivo_model.save()
        else:
            print("[WARN] No data for gorivo model training")
    except Exception as e:
        print(f"[WARN] Could not auto-train gorivo model: {e}")


@router.get("/health")
def health():
    return {
        "status": "healthy",
        "model_trained": _gorivo_model.is_trained,
        "ensemble_enabled": True,
        "xgboost_available": True
    }


@router.get("/memory")
def memory():
    """Sta je gorivo model naucio - kao beba koja pamti"""
    return _gorivo_model.memory.get_learning_summary()


@router.get("/predict")
def predict_all():
    if not _gorivo_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    data = extract_gorivo()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No fuel data")
    return _gorivo_model.analyze_fuel(data.get('gorivo', pd.DataFrame()))


@router.post("/train")
def train_model():
    data = extract_gorivo()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _gorivo_model.train(data)
    _gorivo_model.save()
    return {"status": "trained", **metrics}
