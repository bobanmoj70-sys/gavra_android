"""
Vehicle ML API Endpoints
Povezuje VoziloMLModel sa FastAPI
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pandas as pd
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from data.etl_vozilo import extract_enriched_vozila as extract_vozila
from models.vozilo_model import VoziloMLModel

router = APIRouter(prefix="/vozilo", tags=["Vehicle AI"])

# Global model instance
_vozilo_model = VoziloMLModel()


def init_vozilo_model():
    """Inicijalizuje model pri startup-u — uvek trenira od nule"""
    try:
        data = extract_vozila()
        if data and len(data) > 0:
            _vozilo_model.train(data)
            _vozilo_model.save()
        else:
            print("[WARN] No data for vehicle model training")
    except Exception as e:
        print(f"[WARN] Could not auto-train vehicle model: {e}")


class ServisPredictionRequest(BaseModel):
    vozilo_id: Optional[str] = None
    trenutna_km: Optional[float] = None


@router.get("/health")
def health():
    return {
        "status": "healthy",
        "model_trained": _vozilo_model.is_trained
    }


@router.get("/memory")
def memory():
    """Sta je vozilo model naucio - kao beba koja pamti"""
    return _vozilo_model.memory.get_learning_summary()


@router.get("/predict/all")
def predict_all():
    """Predvidja servis za sva vozila"""
    if not _vozilo_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    data = extract_vozila()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No vehicles found")
    result = _vozilo_model.analyze_vehicle_health(data.get('vozila', pd.DataFrame()))
    return result


@router.post("/predict/service")
def predict_service(req: ServisPredictionRequest):
    """Predvidja servis za specificno vozilo"""
    if not _vozilo_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    data = extract_vozila()
    df = data.get('vozila', pd.DataFrame())
    if req.vozilo_id:
        df = df[df['id'] == req.vozilo_id]
    if len(df) == 0:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    result = _vozilo_model.analyze_vehicle_health(df)
    return result['vehicles'][0] if result['vehicles'] else {}


@router.post("/train")
def train_model():
    """Ponovo trenira model"""
    data = extract_vozila()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _vozilo_model.train(data)
    _vozilo_model.save()
    return {
        "status": "trained",
        "samples": metrics['samples'],
        "features": metrics['feature_count'],
        "r2_score": metrics['r2_score']
    }
