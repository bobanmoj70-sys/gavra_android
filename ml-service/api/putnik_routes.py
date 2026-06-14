"""
Putnik ML API Endpoints
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from fastapi import APIRouter, HTTPException
from data.etl_putnik import extract_enriched_putnik as extract_putnik
from models.putnik_model import PutnikMLModel

router = APIRouter(prefix="/putnik", tags=["Putnik AI"])

_putnik_model = PutnikMLModel()


def init_putnik_model():
    try:
        data = extract_putnik()
        if data and len(data) > 0:
            _putnik_model.train(data)
            _putnik_model.save()
        else:
            print("[WARN] No data for putnik model training")
    except Exception as e:
        print(f"[WARN] Could not auto-train putnik model: {e}")


@router.get("/health")
def health():
    return {
        "status": "healthy",
        "model_trained": _putnik_model.is_trained,
        "ensemble_enabled": True,
        "xgboost_available": True,
        "multi_task_enabled": True
    }


@router.get("/memory")
def memory():
    """Sta je putnik model naucio - kao beba koja pamti"""
    return _putnik_model.memory.get_learning_summary()


@router.get("/predict/all")
def predict_all():
    if not _putnik_model.is_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    data = extract_putnik()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No passenger data")
    return _putnik_model.analyze_passengers(data)


@router.post("/train")
def train_model():
    data = extract_putnik()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _putnik_model.train(data)
    _putnik_model.save()
    return {"status": "trained", **metrics}
