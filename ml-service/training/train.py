"""
Training Pipeline for Financial ML Model
Trenira model isključivo na Supabase podacima
"""
import sys
import os

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from data.etl import extract_finances
from models.financial_model import FinancialMLModel
import config

def train_financial_model():
    """Trenira finansijski ML model od nule"""
    print("=" * 60)
    print("FINANCIAL ML MODEL TRAINING PIPELINE")
    print("=" * 60)
    print("Model uči isključivo iz Supabase podataka (v3_finansije)")
    print("Bez pre-trained znanja - čisti learning od nule")
    print("=" * 60)
    
    # 1. Extract data from Supabase
    print("\n[Step 1/3] Extracting data from Supabase...")
    df = extract_finances()
    
    if len(df) == 0:
        print("ERROR: No data extracted from Supabase")
        return None
    
    print(f"  ✓ Extracted {len(df)} financial records")
    
    # 2. Train model
    print("\n[Step 2/3] Training ML model...")
    model = FinancialMLModel()
    metrics = model.train(df)
    
    # 3. Save model
    print("\n[Step 3/3] Saving trained model...")
    model.save()
    
    print("\n" + "=" * 60)
    print("TRAINING COMPLETE")
    print("=" * 60)
    print(f"Model saved to: {config.MODEL_DIR}")
    print(f"Amount Model R²: {metrics['amount_r2']:.3f}")
    print(f"Amount Model MSE: {metrics['amount_mse']:.2f}")
    print("=" * 60)
    
    return metrics

if __name__ == "__main__":
    train_financial_model()
