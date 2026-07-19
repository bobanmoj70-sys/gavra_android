"""Modul za objašnjivost: koja kolona je kriva za anomaliju?

Logika:
- Autoencoder detektuje anomaliju
- Ali korisnik pita: "ZAŠTO?"
- Ovaj modul to objašnjava: perturbacija svake kolone, meri kako to menja error

Primer:
  Red: {driver_id: 5, amount: 5000000, city: 'Paris'}
  Autoencoder: "ANOMALIJA!"
  Feature Importance: "80% amount, 15% city, 5% driver_id"
  Korisnik zna: "Problem je što je amount ogroman"
"""

import numpy as np
import sqlite3
from datetime import datetime

# Koristimo istu logiku kao neural_brain za feature hashing
def _stable_hash(text: str) -> int:
    """Deterministički heš."""
    import hashlib
    return int(hashlib.md5(text.encode("utf-8")).hexdigest(), 16)


def _bucket(text: str, dim: int) -> int:
    return _stable_hash(text) % dim


def _row_to_features(row: dict, feature_dim: int = 24) -> np.ndarray:
    """Ista konverzija kao u neural_brain."""
    features = np.zeros(feature_dim, dtype=np.float64)
    ignored = {"id", "created_at", "updated_at", "embedding"}
    clip_value = 10.0
    
    for key, value in row.items():
        if key in ignored or value is None:
            continue
        
        key_str = str(key)
        
        if isinstance(value, bool):
            idx = _bucket(key_str, feature_dim)
            features[idx] += 1.0 if value else -1.0
            continue
        
        if isinstance(value, (int, float)):
            idx = _bucket(key_str, feature_dim)
            v = float(value)
            scaled = np.sign(v) * np.log1p(abs(v))
            features[idx] += scaled
            continue
        
        if isinstance(value, (list, dict)):
            idx = _bucket(key_str + ":len", feature_dim)
            try:
                features[idx] += np.log1p(len(value))
            except TypeError:
                pass
            continue
        
        idx = _bucket(f"{key_str}={value}", feature_dim)
        features[idx] += 1.0
    
    np.clip(features, -clip_value, clip_value, out=features)
    return features


def init_schema(conn: sqlite3.Connection):
    """Kreira tabele za feature importance logovanje."""
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS feature_importance_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            source_id TEXT,
            original_error REAL,
            importance_json TEXT,
            top_features_json TEXT,
            created_at TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_importance_table ON feature_importance_log(table_name)")
    conn.commit()


def reset_brain(conn: sqlite3.Connection):
    """Briše sve importance logove."""
    cursor = conn.cursor()
    cursor.execute("DELETE FROM feature_importance_log")
    conn.commit()


def _forward_pass(x: np.ndarray, weights: dict) -> float:
    """Izvršava forward pass i vraća reconstruction error (MSE)."""
    W1 = np.array(weights["W1"])
    b1 = np.array(weights["b1"])
    W2 = np.array(weights["W2"])
    b2 = np.array(weights["b2"])
    
    z1 = x @ W1 + b1
    a1 = np.tanh(z1)
    out = a1 @ W2 + b2
    
    diff = out - x
    error = float(np.mean(diff ** 2))
    return error


def analyze_feature_importance(
    conn: sqlite3.Connection,
    table_name: str,
    row: dict,
    original_error: float,
    weights: dict,
    feature_dim: int = 24
) -> dict:
    """Analizira koja kolona je uzrokovala anomaliju kroz perturbaciju.
    
    Vraća:
    - importance_scores: {kolona -> % uticaja}
    - top_culprits: Sortiran popis najčudnijih kolona
    """
    # Konvertuj red u feature vektor
    features = _row_to_features(row, feature_dim)
    
    # Normalizuj (kao u neural_brain)
    mean = np.zeros(feature_dim)
    std = np.ones(feature_dim)
    normalized = (features - mean) / np.where(std < 1e-6, 1.0, std)
    np.clip(normalized, -10.0, 10.0, out=normalized)
    
    importance_scores = {}
    
    # Za svaku KOLONU (ne feature), perturbuj i meri effect
    for col_name, col_value in row.items():
        if col_name in {"id", "created_at", "updated_at", "embedding"} or col_value is None:
            continue
        
        # Napravi varijantu reda BEZ ove kolone
        row_without = {k: v for k, v in row.items() if k != col_name}
        
        # Konvertuj u feature i forward pass
        features_without = _row_to_features(row_without, feature_dim)
        normalized_without = (features_without - mean) / np.where(std < 1e-6, 1.0, std)
        np.clip(normalized_without, -10.0, 10.0, out=normalized_without)
        
        error_without = _forward_pass(normalized_without, weights)
        
        # Koliko se greška promenila?
        error_change = abs(error_without - original_error)
        importance_scores[col_name] = float(error_change)
    
    # Normalizuj tako da sabir = 100%
    total_importance = sum(importance_scores.values())
    if total_importance > 0:
        for col in importance_scores:
            importance_scores[col] = (importance_scores[col] / total_importance) * 100.0
    
    # Sortiraj - najčudnije prvo
    top_culprits = sorted(importance_scores.items(), key=lambda x: x[1], reverse=True)
    
    return {
        "importance": importance_scores,
        "top_culprits": top_culprits[:5],  # Top 5
    }


def log_feature_importance(
    conn: sqlite3.Connection,
    table_name: str,
    source_id: str,
    row: dict,
    original_error: float,
    weights: dict
) -> dict:
    """Računaj importance i spremi u bazu."""
    import json
    
    importance_data = analyze_feature_importance(conn, table_name, row, original_error, weights)
    
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # Top culprits kao lepa lista za UI
    top_features_list = [
        {"column": col, "importance": round(imp, 2)}
        for col, imp in importance_data["top_culprits"]
    ]
    
    cursor.execute("""
        INSERT INTO feature_importance_log
        (table_name, source_id, original_error, importance_json, top_features_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        table_name,
        source_id,
        original_error,
        json.dumps(importance_data["importance"]),
        json.dumps(top_features_list),
        now
    ))
    
    conn.commit()
    
    return {
        "top_features": top_features_list,
        "explanation": f"Anomalija je verovatno uzrokovana sa: {', '.join([f'{c} ({round(i, 1)}%)' for c, i in importance_data['top_culprits'][:3]])}"
    }


def get_importance_report(conn: sqlite3.Connection) -> dict:
    """Dohvata recent importance analize."""
    import json
    
    cursor = conn.cursor()
    cursor.execute("""
        SELECT table_name, source_id, original_error, top_features_json, created_at
        FROM feature_importance_log ORDER BY id DESC LIMIT 100
    """)
    
    recent = []
    for table_name, source_id, error, top_features_json, created_at in cursor.fetchall():
        try:
            top_features = json.loads(top_features_json)
        except:
            top_features = []
        
        recent.append({
            "table": table_name,
            "source_id": source_id,
            "error": round(error, 4),
            "top_features": top_features,
            "created_at": created_at,
        })
    
    return {
        "recent_analyses": recent,
    }
