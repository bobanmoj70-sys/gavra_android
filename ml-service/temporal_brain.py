"""Modul za učenje vremenskih sekvenci i detekciju trendova (LSTM/GRU).

Učenje:
- Za svaku tabelu i numeričku kolonu, čuva poslednjnih N redova (sortirano po created_at/id)
- Trenira mali GRU model da PREDIČE sledeću vrednost iz prethodnih M vrednosti
- Ako STVARNA vrednost značajno devijira od PREDVIĐANJA → ANOMALIJA (pre nego što autoencoder)

Prednost: Detektuje skokove u trendovima (npr. amount koji uvek raste, odjednom pada 90%)
"""

import json
import sqlite3
from datetime import datetime
from collections import deque

import numpy as np

# --- HIPERPARAMETRI ---
SEQUENCE_LENGTH = 5        # Koliko prethodnih vrednosti koristi za predviđanje
HIDDEN_DIM = 8            # GRU skriveni sloj
LEARNING_RATE = 0.02
CLIP_VALUE = 10.0
MIN_SAMPLES_FOR_SEQUENCE = 20  # Pre nego što počne sa anomalijom detekcijom
MAX_SEQUENCE_LOG_ROWS = 5000
PREDICTION_ERROR_Z_THRESHOLD = 3.0


def init_schema(conn: sqlite3.Connection):
    """Kreira tabele za sekvencijalno učenje."""
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS temporal_state (
            table_name TEXT NOT NULL,
            column_name TEXT NOT NULL,
            gru_weights_json TEXT NOT NULL,
            value_history_json TEXT NOT NULL,
            prediction_mean REAL NOT NULL DEFAULT 0,
            prediction_m2 REAL NOT NULL DEFAULT 0,
            prediction_n INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT,
            PRIMARY KEY (table_name, column_name)
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS temporal_prediction_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            column_name TEXT NOT NULL,
            source_id TEXT,
            actual_value REAL NOT NULL,
            predicted_value REAL,
            error REAL,
            error_z_score REAL,
            is_anomaly BOOLEAN DEFAULT 0,
            created_at TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_temporal_table ON temporal_prediction_log(table_name)")
    conn.commit()


def reset_brain(conn: sqlite3.Connection):
    """Briše sve naučene sekvencijalne težine."""
    cursor = conn.cursor()
    cursor.execute("DELETE FROM temporal_state")
    cursor.execute("DELETE FROM temporal_prediction_log")
    conn.commit()


def _new_gru_weights() -> dict:
    """GRU inicijalizacija - male nasumične težine."""
    rng = np.random.default_rng()
    limit = np.sqrt(6.0 / (SEQUENCE_LENGTH + HIDDEN_DIM))
    
    return {
        # Reset gate
        "Wr": (rng.uniform(-limit, limit, (SEQUENCE_LENGTH, HIDDEN_DIM))).tolist(),
        "Ur": (rng.uniform(-limit, limit, (HIDDEN_DIM, HIDDEN_DIM))).tolist(),
        "br": np.zeros(HIDDEN_DIM).tolist(),
        
        # Update gate
        "Wz": (rng.uniform(-limit, limit, (SEQUENCE_LENGTH, HIDDEN_DIM))).tolist(),
        "Uz": (rng.uniform(-limit, limit, (HIDDEN_DIM, HIDDEN_DIM))).tolist(),
        "bz": np.zeros(HIDDEN_DIM).tolist(),
        
        # Candidate hidden
        "Wh": (rng.uniform(-limit, limit, (SEQUENCE_LENGTH, HIDDEN_DIM))).tolist(),
        "Uh": (rng.uniform(-limit, limit, (HIDDEN_DIM, HIDDEN_DIM))).tolist(),
        "bh": np.zeros(HIDDEN_DIM).tolist(),
        
        # Output (GRU hidden → numerička predikcija)
        "Wo": (rng.uniform(-limit, limit, (HIDDEN_DIM, 1))).tolist(),
        "bo": np.array([0.0]).tolist(),
    }


def _load_state(conn: sqlite3.Connection, table_name: str, column_name: str) -> dict:
    """Učitava sekvencijalno stanje za (tabela, kolona)."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT gru_weights_json, value_history_json, prediction_mean, prediction_m2, prediction_n
        FROM temporal_state WHERE table_name=? AND column_name=?
    """, (table_name, column_name))
    
    row = cursor.fetchone()
    if row is None:
        return {
            "weights": _new_gru_weights(),
            "value_history": deque(maxlen=SEQUENCE_LENGTH * 10),  # Čuva N poslednjих vrednosti
            "prediction_mean": 0.0,
            "prediction_m2": 0.0,
            "prediction_n": 0,
        }
    
    weights_json, history_json, pred_mean, pred_m2, pred_n = row
    return {
        "weights": json.loads(weights_json),
        "value_history": deque(json.loads(history_json), maxlen=SEQUENCE_LENGTH * 10),
        "prediction_mean": pred_mean,
        "prediction_m2": pred_m2,
        "prediction_n": pred_n,
    }


def _save_state(conn: sqlite3.Connection, table_name: str, column_name: str, state: dict):
    """Čuva sekvencijalno stanje."""
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    cursor.execute("""
        INSERT INTO temporal_state 
        (table_name, column_name, gru_weights_json, value_history_json, 
         prediction_mean, prediction_m2, prediction_n, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(table_name, column_name) DO UPDATE SET
            gru_weights_json=excluded.gru_weights_json,
            value_history_json=excluded.value_history_json,
            prediction_mean=excluded.prediction_mean,
            prediction_m2=excluded.prediction_m2,
            prediction_n=excluded.prediction_n,
            updated_at=excluded.updated_at
    """, (
        table_name,
        column_name,
        json.dumps(state["weights"]),
        json.dumps(list(state["value_history"])),
        state["prediction_mean"],
        state["prediction_m2"],
        state["prediction_n"],
        now,
    ))
    conn.commit()


def _sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(x, -30, 30)))


def _tanh(x: np.ndarray) -> np.ndarray:
    return np.tanh(x)


def _gru_forward(x_sequence: np.ndarray, h_prev: np.ndarray, weights: dict) -> tuple[np.ndarray, np.ndarray]:
    """GRU korak - vraća predikciju i novi hidden state.
    
    x_sequence: (SEQUENCE_LENGTH,) - poslednji X-ovi
    h_prev: (HIDDEN_DIM,) - prethodni skriveni state
    """
    Wr = np.array(weights["Wr"])
    Ur = np.array(weights["Ur"])
    br = np.array(weights["br"])
    
    Wz = np.array(weights["Wz"])
    Uz = np.array(weights["Uz"])
    bz = np.array(weights["bz"])
    
    Wh = np.array(weights["Wh"])
    Uh = np.array(weights["Uh"])
    bh = np.array(weights["bh"])
    
    Wo = np.array(weights["Wo"])
    bo = np.array(weights["bo"])
    
    # Reset gate
    r = _sigmoid(x_sequence @ Wr + h_prev @ Ur + br)
    
    # Update gate
    z = _sigmoid(x_sequence @ Wz + h_prev @ Uz + bz)
    
    # Candidate hidden
    h_tilde = _tanh(x_sequence @ Wh + (r * h_prev) @ Uh + bh)
    
    # New hidden state
    h_new = (1 - z) * h_tilde + z * h_prev
    
    # Output (predikcija sledeće vrednosti)
    output = h_new @ Wo + bo
    
    return output, h_new


def _gru_train_step(x_sequence: np.ndarray, y_true: float, h_prev: np.ndarray, weights: dict) -> tuple[float, np.ndarray]:
    """Jedan GRU korak - forward, error, backward (simplified).
    
    Vraća: (prediction_error, novi_hidden_state)
    """
    y_pred, h_new = _gru_forward(x_sequence, h_prev, weights)
    y_pred_val = float(y_pred[0])
    
    error = y_true - y_pred_val
    pred_loss = error ** 2
    
    # Simplified gradient descent (nije puni BPTT, ali dovoljno za online learning)
    grad_scale = 0.1 * error
    
    Wo = np.array(weights["Wo"])
    bo = np.array(weights["bo"])
    
    # Update output layer (najjednostavnije)
    Wo -= LEARNING_RATE * grad_scale * h_new.reshape(-1, 1)
    bo -= LEARNING_RATE * grad_scale
    
    np.clip(Wo, -CLIP_VALUE, CLIP_VALUE, out=Wo)
    np.clip(bo, -CLIP_VALUE, CLIP_VALUE, out=bo)
    
    weights["Wo"] = Wo.tolist()
    weights["bo"] = bo.tolist()
    
    return pred_loss, h_new


def _welford_update(mean: float, m2: float, n: int, new_value: float):
    """Welford online algoritam za srednju vrednost i varijansu."""
    n += 1
    delta = new_value - mean
    mean += delta / n
    delta2 = new_value - mean
    m2 += delta * delta2
    return mean, m2, n


def observe_temporal_sequence(conn: sqlite3.Connection, table_name: str, row: dict, source_id: str) -> dict | None:
    """Glavna ulazna tačka: mreža vidi novu vrednost, uči trend, detektuje skokove.
    
    Vraća detaljnu analizu ako je predviđanje značajno krivo (anomalija tipa "skok u trend").
    """
    if not row:
        return None
    
    # Izvuci sve numeričke kolone iz reda
    numeric_values: dict[str, float] = {}
    for key, value in row.items():
        if isinstance(value, (int, float)) and key not in {"id", "created_at", "updated_at"}:
            try:
                v = float(value)
                # Log-scaling kao u neural_brain
                scaled = float(np.sign(v) * np.log1p(abs(v)))
                numeric_values[key] = scaled
            except (ValueError, TypeError):
                pass
    
    if not numeric_values:
        return None  # Nema numeričkih kolona
    
    results = []
    
    for col_name, col_value in numeric_values.items():
        state = _load_state(conn, table_name, col_name)
        state["value_history"].append(col_value)
        
        # Ako nemamo dovoljno istorije, samo skupljamo podatke
        if len(state["value_history"]) < SEQUENCE_LENGTH + 1:
            _save_state(conn, table_name, col_name, state)
            continue
        
        # Imamo dovoljno: izvuci sekvencu i treniraj
        history_list = list(state["value_history"])
        x_seq = np.array(history_list[-SEQUENCE_LENGTH-1:-1], dtype=np.float64)
        y_true = history_list[-1]
        
        # GRU forward/backward
        h_prev = np.zeros(HIDDEN_DIM)
        pred_loss, h_new = _gru_train_step(x_seq, y_true, h_prev, state["weights"])
        
        # Ažuriraj statistiku greške
        pred_mean, pred_m2, pred_n = _welford_update(
            state["prediction_mean"],
            state["prediction_m2"],
            state["prediction_n"],
            pred_loss
        )
        state["prediction_mean"] = pred_mean
        state["prediction_m2"] = pred_m2
        state["prediction_n"] = pred_n
        
        # Proveri anomaliju
        is_anomaly = False
        z_score = None
        
        if pred_n > MIN_SAMPLES_FOR_SEQUENCE:
            pred_std = np.sqrt(pred_m2 / pred_n) if pred_n > 1 else 1.0
            if pred_std > 1e-9:
                z_score = float((pred_loss - pred_mean) / pred_std)
                is_anomaly = z_score > PREDICTION_ERROR_Z_THRESHOLD
        
        if is_anomaly:
            # Log anomaliju
            y_pred, _ = _gru_forward(x_seq, np.zeros(HIDDEN_DIM), state["weights"])
            y_pred_val = float(y_pred[0])
            
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO temporal_prediction_log 
                (table_name, column_name, source_id, actual_value, predicted_value, error, error_z_score, is_anomaly, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                table_name, col_name, source_id,
                y_true, y_pred_val, float(pred_loss), float(z_score),
                1, datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            ))
            
            _trim_log(cursor)
            conn.commit()
            
            results.append({
                "table": table_name,
                "column": col_name,
                "source_id": source_id,
                "actual": y_true,
                "predicted": y_pred_val,
                "error": float(pred_loss),
                "z_score": z_score,
                "detail": f"Trend anomalija u '{table_name}' kolona '{col_name}': "
                         f"očekivao sam ~{y_pred_val:.4f}, a dobio sam {y_true:.4f} "
                         f"({z_score:.1f}σ izvan trenda)"
            })
        
        _save_state(conn, table_name, col_name, state)
    
    return results[0] if results else None


def _trim_log(cursor: sqlite3.Cursor):
    """Čuva samo poslednje MAX_SEQUENCE_LOG_ROWS."""
    cursor.execute("SELECT COUNT(*) FROM temporal_prediction_log")
    count = cursor.fetchone()[0]
    if count > MAX_SEQUENCE_LOG_ROWS:
        excess = count - MAX_SEQUENCE_LOG_ROWS
        cursor.execute("""
            DELETE FROM temporal_prediction_log WHERE id IN (
                SELECT id FROM temporal_prediction_log ORDER BY id ASC LIMIT ?
            )
        """, (excess,))


def get_temporal_report(conn: sqlite3.Connection) -> dict:
    """Vraća izveštaj o sekvencijalnom učenju."""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT table_name, column_name, prediction_n, prediction_mean, updated_at
        FROM temporal_state ORDER BY table_name, column_name
    """)
    
    sequences = []
    for table_name, col_name, pred_n, pred_mean, updated_at in cursor.fetchall():
        sequences.append({
            "table": table_name,
            "column": col_name,
            "samples_seen": pred_n,
            "avg_prediction_error": round(pred_mean, 6) if pred_mean else 0,
            "updated_at": updated_at,
            "ready_for_anomaly": pred_n >= MIN_SAMPLES_FOR_SEQUENCE,
        })
    
    cursor.execute("""
        SELECT table_name, column_name, actual_value, predicted_value, error_z_score, created_at
        FROM temporal_prediction_log WHERE is_anomaly=1 ORDER BY id DESC LIMIT 50
    """)
    
    anomalies = []
    for table_name, col_name, actual, predicted, z_score, created_at in cursor.fetchall():
        anomalies.append({
            "table": table_name,
            "column": col_name,
            "actual": actual,
            "predicted": predicted,
            "z_score": z_score,
            "created_at": created_at,
        })
    
    return {
        "architecture": f"GRU sequence length={SEQUENCE_LENGTH}, hidden={HIDDEN_DIM}",
        "sequences": sequences,
        "trend_anomalies": anomalies,
    }
