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
    return {
        "status": "healthy",
        "model_trained": _financial_model.is_amount_trained or _financial_model.is_type_trained,
        "ensemble_enabled": True,
        "xgboost_available": True,
        "prophet_trained": _financial_model.is_prophet_trained,
        "online_learning_enabled": _financial_model.is_online_trained,
        "rfe_applied": _financial_model.is_rfe_applied
    }


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
    anomalies_df = _financial_model.detect_anomalies(data.get('finansije', pd.DataFrame()))
    # Filter to only anomalous records and return as expected format
    anomalous = anomalies_df[anomalies_df['is_anomaly'] == 1] if 'is_anomaly' in anomalies_df.columns else anomalies_df
    return {
        "top_anomalies": anomalous.head(20).to_dict(orient='records'),
        "total_anomalies": len(anomalous)
    }


@router.post("/train")
def train_model():
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _financial_model.train(data)
    _financial_model.save()
    return {"status": "trained", **metrics}


@router.post("/train/prophet")
def train_prophet():
    """Trenira Prophet time series model za finansijske trendove"""
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    metrics = _financial_model.train_prophet(data.get('finansije', pd.DataFrame()))
    _financial_model.save()
    return {"status": "prophet_trained", **metrics}


@router.get("/predict/trends")
def predict_trends(days_ahead: int = 30):
    """Predviđa finansijske trendove za narednih N dana"""
    if not _financial_model.is_prophet_trained:
        raise HTTPException(status_code=503, detail="Prophet model not trained")
    return _financial_model.predict_trends(days_ahead)


@router.post("/online/init")
def init_online_learning():
    """Inicijalizuje online learning model za real-time ažuriranje"""
    success = _financial_model.init_online_learning()
    if success:
        _financial_model.save()
        return {"status": "online_learning_initialized"}
    else:
        raise HTTPException(status_code=503, detail="Online learning initialization failed")


@router.post("/online/update")
def update_online(features: dict, target: float):
    """Ažurira model u real-time sa novim podacima"""
    result = _financial_model.update_online(features, target)
    if 'error' in result:
        raise HTTPException(status_code=400, detail=result['error'])
    _financial_model.save()
    return result


@router.post("/online/predict")
def predict_online(features: dict):
    """Predikcija koristeći online learning model"""
    result = _financial_model.predict_online(features)
    if 'error' in result:
        raise HTTPException(status_code=400, detail=result['error'])
    return result


@router.post("/feature-selection/rfe")
def apply_rfe(n_features_to_select: int = 10):
    """Primenjuje Recursive Feature Elimination za selekciju najbitnijih feature-a"""
    data = extract_finances()
    if not data or len(data) == 0:
        raise HTTPException(status_code=404, detail="No training data")
    
    df = data.get('finansije', pd.DataFrame())
    if 'iznos' not in df.columns:
        raise HTTPException(status_code=400, detail="Missing target column 'iznos'")
    
    # Pripremi X i y za RFE
    feature_cols = [c for c in df.columns if c not in ['iznos', 'created_at', 'id']]
    X = df[feature_cols].fillna(0)
    y = df['iznos'].values
    
    result = _financial_model.apply_rfe(X, y, n_features_to_select)
    if 'error' in result:
        raise HTTPException(status_code=400, detail=result['error'])
    
    _financial_model.save()
    return result
