"""
Zahtevi ML API Endpoints
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from fastapi import APIRouter, HTTPException
from data.etl_zahtevi import extract_enriched_zahtevi as extract_zahtevi
from models.zahtevi_model import ZahteviMLModel

router = APIRouter(prefix="/zahtevi", tags=["Zahtevi AI"])

_zahtevi_model = ZahteviMLModel()


def init_zahtevi_model():
    _zahtevi_model.load()
    if not _zahtevi_model.is_trained:
        try:
            df = extract_zahtevi()
            if len(df) > 0:
                _zahtevi_model.train(df)
                _zahtevi_model.save()
        except Exception as e:
            print(f"[WARN] Could not auto-train zahtevi model: {e}")


@router.get("/health")
def health():
    return {"status": "healthy", "model_trained": _zahtevi_model.is_trained}


@router.get("/predict/next-week")
def predict_next_week():
    if not _zahtevi_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    return _zahtevi_model.predict_next_week()


@router.get("/analyze/trends")
def analyze_trends():
    df = extract_zahtevi()
    if len(df) == 0:
        raise HTTPException(status_code=404, detail="No request data")
    if not _zahtevi_model.is_trained:
        _zahtevi_model.train(df)
        _zahtevi_model.save()
    return _zahtevi_model.analyze_trends(df)


@router.post("/train")
def train_model():
    df = extract_zahtevi()
    if len(df) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _zahtevi_model.train(df)
    _zahtevi_model.save()
    return {"status": "trained", **metrics}
