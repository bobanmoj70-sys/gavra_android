"""
Putnik ML API Endpoints
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from fastapi import APIRouter, HTTPException
from data.etl_putnik import extract_finansije, extract_zahtevi
from models.putnik_model import PutnikMLModel

router = APIRouter(prefix="/putnik", tags=["Putnik AI"])

_putnik_model = PutnikMLModel()


def init_putnik_model():
    _putnik_model.load()
    if not _putnik_model.is_trained:
        try:
            fin = extract_finansije()
            zah = extract_zahtevi()
            if len(fin) > 0:
                _putnik_model.train(fin, zah)
                _putnik_model.save()
        except Exception as e:
            print(f"[WARN] Could not auto-train putnik model: {e}")


@router.get("/health")
def health():
    return {"status": "healthy", "model_trained": _putnik_model.is_trained}


@router.get("/predict/all")
def predict_all():
    if not _putnik_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    fin = extract_finansije()
    zah = extract_zahtevi()
    if len(fin) == 0:
        raise HTTPException(status_code=404, detail="No passenger data")
    return _putnik_model.analyze_passengers(fin, zah)


@router.post("/train")
def train_model():
    fin = extract_finansije()
    zah = extract_zahtevi()
    if len(fin) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _putnik_model.train(fin, zah)
    _putnik_model.save()
    return {"status": "trained", **metrics}
