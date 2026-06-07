"""
Gorivo ML API Endpoints
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from data.etl_vozilo import extract_gorivo
from models.gorivo_model import GorivoMLModel

router = APIRouter(prefix="/gorivo", tags=["Gorivo AI"])

_gorivo_model = GorivoMLModel()


def init_gorivo_model():
    _gorivo_model.load()
    if not _gorivo_model.is_trained:
        try:
            df = extract_gorivo()
            if len(df) > 0:
                _gorivo_model.train(df)
                _gorivo_model.save()
        except Exception as e:
            print(f"[WARN] Could not auto-train gorivo model: {e}")


@router.get("/health")
def health():
    return {"status": "healthy", "model_trained": _gorivo_model.is_trained}


@router.get("/predict")
def predict_all():
    if not _gorivo_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    df = extract_gorivo()
    if len(df) == 0:
        raise HTTPException(status_code=404, detail="No fuel data")
    return _gorivo_model.analyze_fuel(df)


@router.post("/train")
def train_model():
    df = extract_gorivo()
    if len(df) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _gorivo_model.train(df)
    _gorivo_model.save()
    return {"status": "trained", **metrics}
