"""
Training Pipeline - Vehicle ML Model
Trenira model iskljucivo iz Supabase v3_vozila podataka
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from data.etl_vozilo import extract_vozila
from models.vozilo_model import VoziloMLModel


def train_vehicle_model():
    """Trenira model na vozilo podacima"""
    print("=" * 50)
    print("Vehicle ML Training")
    print("=" * 50)

    # Extract
    df = extract_vozila()
    if len(df) == 0:
        print("[ERROR] No vehicle data found")
        return False

    # Train
    model = VoziloMLModel()
    metrics = model.train(df)
    print(f"\nTraining complete:")
    print(f"  - Samples: {metrics['samples']}")
    print(f"  - Features: {metrics['feature_count']}")
    print(f"  - R2 Score: {metrics['r2_score']:.4f}")

    # Save
    model.save()
    print("\n[OK] Vehicle model trained and saved")
    return True


if __name__ == "__main__":
    train_vehicle_model()
