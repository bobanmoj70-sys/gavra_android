"""
Financial ML API Endpoints
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pandas as pd
from fastapi import APIRouter, HTTPException
from data.etl import extract_enriched_finances as extract_finances
from models.financial_model import FinancialMLModel

router = APIRouter(prefix="/financial", tags=["Financial AI"])

_financial_model = FinancialMLModel()


def init_financial_model():
    try:
        data = extract_finances()
        if data and len(data) > 0:
            _financial_model.train(data)
            _financial_model.save()
        else:
            print("[WARN] No data for financial model training")
    except Exception as e:
        print(f"[WARN] Could not auto-train financial model: {e}")


@router.get("/health")
def health():
    return {"status": "healthy", "model_trained": _financial_model.is_amount_trained or _financial_model.is_type_trained}


@router.get("/memory")
def memory():
    """Sta je financial model naucio - kao beba koja pamti"""
    return _financial_model.memory.get_learning_summary()


@router.get("/predict/amount")
def predict_amount():
    if not _financial_model.is_amount_trained:
        raise HTTPException(status_code=503, detail="Amount model not trained")
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No financial data")
    return _financial_model.predict_amount(data.get('finansije', pd.DataFrame()))


@router.get("/predict/type")
def predict_type():
    if not _financial_model.is_type_trained:
        raise HTTPException(status_code=503, detail="Type model not trained")
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No financial data")
    return _financial_model.predict_type(data.get('finansije', pd.DataFrame()))


@router.get("/analyze/trends")
def analyze_trends():
    if not _financial_model.is_amount_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No financial data")
    return _financial_model.analyze_trends(data.get('finansije', pd.DataFrame()))


@router.get("/detect/anomalies")
def detect_anomalies():
    if not _financial_model.is_amount_trained:
        raise HTTPException(status_code=503, detail="Model not trained")
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No financial data")
    return _financial_model.detect_anomalies(data.get('finansije', pd.DataFrame()))


@router.post("/train")
def train_model():
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _financial_model.train(data)
    _financial_model.save()
    return {"status": "trained", **metrics}
