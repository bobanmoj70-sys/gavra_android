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
from api.vozilo_routes import router as vozilo_router, init_vozilo_model
from api.gorivo_routes import router as gorivo_router, init_gorivo_model
from api.putnik_routes import router as putnik_router, init_putnik_model
from api.zahtevi_routes import router as zahtevi_router, init_zahtevi_model

app = FastAPI(title="Gavra ML API", version="3.0.0")

# Include all routers
app.include_router(vozilo_router)
app.include_router(gorivo_router)
app.include_router(putnik_router)
app.include_router(zahtevi_router)

init_vozilo_model()
init_gorivo_model()
init_putnik_model()
init_zahtevi_model()

# Initialize model
financial_model = FinancialMLModel()

# Load model if available
try:
    financial_model.load()
    print("[OK] Financial ML Model loaded successfully")
except:
    print("[MISSING] No saved model found. Train model first.")

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
        "model_trained": financial_model.is_trained
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_trained": financial_model.is_trained,
        "timestamp": datetime.now().isoformat()
    }

@app.post("/predict/amount")
async def predict_amount(request: PredictionRequest):
    """
    Predikcija iznosa za buduće transakcije
    Model koristi naučeno znanje isključivo iz Supabase podataka
    """
    if not financial_model.is_trained:
        raise HTTPException(status_code=400, detail="Model not trained. Call /train first.")
    
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
    if not financial_model.is_trained:
        raise HTTPException(status_code=400, detail="Model not trained. Call /train first.")
    
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
    Analizira finansijske trendove
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
