"""Ensemble scorer — kombinuje sve detektore u jedan kompozitni score.

## Ključna razlika: NEMA ručnih pragova — sistem SAM uči šta je normalno.

Stara verzija je imala hardkodirane vrednosti:
    if autoencoder_z > 3.0: ...   # zašto 3.0? ko je to odlučio?
    weights = [0.40, 0.30, ...]   # zašto te težine?

Nova verzija: za svaku tabelu posebno, sistem UČI iz podataka šta je
"normalna" vrednost svakog detektora, i reaguje samo kad detektor
značajno odskoči od SOPSTVENE naučene norme za TU tabelu.

Tehnika: Welford online statistika po (tabela, detektor) —
isti algoritam koji koristi neural_brain za error statistiku.

Jedina "ručna" vrednost je META_Z_THRESHOLD = 2.0 —
statistička konvencija (95. percentil), ne poslovna pretpostavka.

EMA_ALPHA: mreža lagano "zaboravlja" staro normalno ponašanje,
adaptirajući se na promene u poslovnom procesu.
"""
import json
import sqlite3
from datetime import datetime

import numpy as np

# Jedini fiksni parametar — statistička konvencija, ne poslovna vrednost
# 2.0 = gornji 5% po normalnoj raspodeli (95. percentil)
META_Z_THRESHOLD = 2.0

# EMA decay: ~500 novih redova = "poluvreme zaboravljanja" stare norme
EMA_ALPHA = 0.002

# Minimalan broj uzoraka pre nego što počnemo da koristimo naučene pragove
MIN_CALIBRATION_SAMPLES = 30

MAX_ENSEMBLE_LOG_ROWS = 10000

# Imena detektora — jedino što je fiksno su nazivi, ne vrednosti
DETECTORS = ["autoencoder", "temporal", "cross_table", "feature_culprit"]


def init_schema(conn: sqlite3.Connection):
    """Kreira tabele za kalibraciju i composite scores."""
    cursor = conn.cursor()

    # Tabela za naučene pragove: Welford statistika po (tabela, detektor)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS ensemble_calibration (
            table_name TEXT NOT NULL,
            detector TEXT NOT NULL,
            mean REAL NOT NULL DEFAULT 0,
            m2 REAL NOT NULL DEFAULT 0,
            n INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT,
            PRIMARY KEY (table_name, detector)
        )
    """)

    # Tabela za snimljene composite alarme
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS ensemble_scores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            source_id TEXT,
            composite_score REAL NOT NULL,
            detectors_fired INTEGER NOT NULL DEFAULT 0,
            severity TEXT NOT NULL DEFAULT 'low',
            autoencoder_z REAL,
            autoencoder_meta_z REAL,
            temporal_z REAL,
            temporal_meta_z REAL,
            cross_table_z REAL,
            cross_table_meta_z REAL,
            feature_culprit_pct REAL,
            feature_meta_z REAL,
            reasons_json TEXT,
            created_at TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_ensemble_table ON ensemble_scores(table_name)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_ensemble_severity ON ensemble_scores(severity)")
    conn.commit()


def reset_scores(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("DELETE FROM ensemble_scores")
    cursor.execute("DELETE FROM ensemble_calibration")
    conn.commit()


def _welford_update(mean: float, m2: float, n: int, value: float) -> tuple[float, float, int]:
    """Jedan korak Welford online algoritma za mean i varijansu."""
    n += 1
    delta = value - mean
    mean += delta / n
    delta2 = value - mean
    m2 += delta * delta2
    return mean, m2, n


def _load_calibration(conn: sqlite3.Connection, table_name: str, detector: str) -> dict:
    cursor = conn.cursor()
    cursor.execute(
        "SELECT mean, m2, n FROM ensemble_calibration WHERE table_name=? AND detector=?",
        (table_name, detector)
    )
    row = cursor.fetchone()
    if row:
        return {"mean": row[0], "m2": row[1], "n": row[2]}
    return {"mean": 0.0, "m2": 0.0, "n": 0}


def _save_calibration(conn: sqlite3.Connection, table_name: str, detector: str, cal: dict):
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO ensemble_calibration (table_name, detector, mean, m2, n, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(table_name, detector) DO UPDATE SET
            mean=excluded.mean, m2=excluded.m2, n=excluded.n, updated_at=excluded.updated_at
    """, (table_name, detector, cal["mean"], cal["m2"], cal["n"],
          datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
    conn.commit()


def _compute_meta_z(cal: dict, value: float) -> float | None:
    """Koliko standardnih devijacija je 'value' iznad naučene srednje vrednosti
    za ovaj detektor i ovu tabelu. Vraća None ako nemamo dovoljno uzoraka."""
    if cal["n"] < MIN_CALIBRATION_SAMPLES:
        return None
    std = np.sqrt(cal["m2"] / cal["n"]) if cal["n"] > 1 else 0.0
    if std < 1e-9:
        return None
    return float((value - cal["mean"]) / std)


def _update_calibration_ema(cal: dict, value: float) -> dict:
    """Ažurira kalibraciju:
    - Prvih MIN_CALIBRATION_SAMPLES: čisti Welford (brzo učenje)
    - Posle: EMA za mean (adaptivno zaboravljanje), Welford za varijansu
    """
    if cal["n"] < MIN_CALIBRATION_SAMPLES:
        mean, m2, n = _welford_update(cal["mean"], cal["m2"], cal["n"], value)
    else:
        # EMA za mean — zaboravlja staro "normalno" kako se biznis menja
        mean = (1.0 - EMA_ALPHA) * cal["mean"] + EMA_ALPHA * value
        _, m2, n = _welford_update(cal["mean"], cal["m2"], cal["n"], value)
    return {"mean": mean, "m2": m2, "n": n}


def _trim_log(cursor: sqlite3.Cursor):
    cursor.execute("SELECT COUNT(*) FROM ensemble_scores")
    count = cursor.fetchone()[0]
    if count > MAX_ENSEMBLE_LOG_ROWS:
        excess = count - MAX_ENSEMBLE_LOG_ROWS
        cursor.execute("""
            DELETE FROM ensemble_scores WHERE id IN (
                SELECT id FROM ensemble_scores ORDER BY id ASC LIMIT ?
            )
        """, (excess,))


def compute_and_save(
    conn: sqlite3.Connection,
    table_name: str,
    source_id: str,
    autoencoder_z: float | None = None,
    temporal_z: float | None = None,
    cross_table_z: float | None = None,
    feature_culprit_pct: float | None = None,
) -> dict:
    """Izračunava composite score koristeći NAUČENE pragove za ovu tabelu.

    Logika:
    1. Za svaki detektor, ažuriramo Welford kalibraciju (učimo šta je normalno)
    2. Računamo meta-z-score: koliko je ovaj signal neobičan ZA OVU TABELU
    3. Detektor "pali" samo ako je meta-z > META_Z_THRESHOLD (2.0)
    4. Composite score = zbir (meta-z - prag) doprinosa, normalizovan na 0-3
    5. Severity zavisi od broja upaljenih detektora
    """
    signals = {
        "autoencoder": autoencoder_z,
        "temporal": temporal_z,
        "cross_table": cross_table_z,
        "feature_culprit": feature_culprit_pct,
    }

    meta_zs = {}
    calibrations = {}

    # Faza 1: učenje kalibracije i računanje meta-z za svaki detektor
    for detector, value in signals.items():
        cal = _load_calibration(conn, table_name, detector)
        if value is not None:
            cal = _update_calibration_ema(cal, value)
            _save_calibration(conn, table_name, detector, cal)
            mz = _compute_meta_z(cal, value)
            meta_zs[detector] = mz
        else:
            meta_zs[detector] = None
        calibrations[detector] = cal

    # Faza 2: koji detektori su prešli NAUČENI prag?
    score = 0.0
    detectors_fired = 0
    reasons = []

    for detector, mz in meta_zs.items():
        if mz is not None and mz > META_Z_THRESHOLD:
            # Doprinos = koliko sigma iznad praga, kapiran na 3.0
            contribution = min((mz - META_Z_THRESHOLD) / META_Z_THRESHOLD, 3.0)
            score += contribution
            detectors_fired += 1
            n = calibrations[detector]["n"]
            val = signals[detector]
            reasons.append(
                f"{detector}: meta-z={mz:.1f}σ iznad naučene norme "
                f"(kalibracija: {n} uzoraka, vrednost={val:.2f})"
            )

    score = round(min(score, 3.0), 4)

    # Severity: samo od broja detektora koji su prešli SOPSTVENI naučeni prag
    if detectors_fired >= 3:
        severity = "critical"
    elif detectors_fired >= 2:
        severity = "high"
    elif detectors_fired == 1:
        severity = "medium"
    else:
        severity = "low"

    result = {
        "table": table_name,
        "source_id": source_id,
        "composite_score": score,
        "detectors_fired": detectors_fired,
        "severity": severity,
        "reasons": reasons,
        "autoencoder_z": autoencoder_z,
        "autoencoder_meta_z": meta_zs.get("autoencoder"),
        "temporal_z": temporal_z,
        "temporal_meta_z": meta_zs.get("temporal"),
        "cross_table_z": cross_table_z,
        "cross_table_meta_z": meta_zs.get("cross_table"),
        "feature_culprit_pct": feature_culprit_pct,
        "feature_meta_z": meta_zs.get("feature_culprit"),
    }

    # Snimamo u bazu samo ako ima bar jedan signal koji je prešao prag
    if detectors_fired > 0:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO ensemble_scores
                (table_name, source_id, composite_score, detectors_fired, severity,
                 autoencoder_z, autoencoder_meta_z,
                 temporal_z, temporal_meta_z,
                 cross_table_z, cross_table_meta_z,
                 feature_culprit_pct, feature_meta_z,
                 reasons_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            table_name, source_id, score, detectors_fired, severity,
            autoencoder_z, meta_zs.get("autoencoder"),
            temporal_z, meta_zs.get("temporal"),
            cross_table_z, meta_zs.get("cross_table"),
            feature_culprit_pct, meta_zs.get("feature_culprit"),
            json.dumps(reasons, ensure_ascii=False),
            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        ))
        _trim_log(cursor)
        conn.commit()

    return result


def get_calibration_status(conn: sqlite3.Connection) -> list[dict]:
    """Koliko je sistem naučio po tabeli i detektoru — koliko mu još treba kalibracije."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT table_name, detector, mean, m2, n, updated_at
        FROM ensemble_calibration
        ORDER BY table_name, detector
    """)
    result = []
    for table_name, detector, mean, m2, n, updated_at in cursor.fetchall():
        std = float(np.sqrt(m2 / n)) if n > 1 else 0.0
        result.append({
            "table": table_name,
            "detector": detector,
            "learned_mean": round(mean, 4),
            "learned_std": round(std, 4),
            "samples": n,
            "calibrated": n >= MIN_CALIBRATION_SAMPLES,
            "threshold_in_original_units": round(mean + META_Z_THRESHOLD * std, 4) if n >= MIN_CALIBRATION_SAMPLES else None,
            "updated_at": updated_at,
        })
    return result


def get_report(conn: sqlite3.Connection, limit: int = 100) -> dict:
    """Vraća poslednje high/critical composite alarme + status kalibracije."""
    cursor = conn.cursor()

    cursor.execute("""
        SELECT table_name, source_id, composite_score, detectors_fired, severity,
               autoencoder_z, autoencoder_meta_z,
               temporal_z, temporal_meta_z,
               cross_table_z, cross_table_meta_z,
               feature_culprit_pct, feature_meta_z,
               reasons_json, created_at
        FROM ensemble_scores
        WHERE severity IN ('high', 'critical')
        ORDER BY composite_score DESC, id DESC
        LIMIT ?
    """, (limit,))

    alerts = []
    for row in cursor.fetchall():
        alerts.append({
            "table": row[0],
            "source_id": row[1],
            "composite_score": row[2],
            "detectors_fired": row[3],
            "severity": row[4],
            "autoencoder_z": row[5],
            "autoencoder_meta_z": row[6],
            "temporal_z": row[7],
            "temporal_meta_z": row[8],
            "cross_table_z": row[9],
            "cross_table_meta_z": row[10],
            "feature_culprit_pct": row[11],
            "feature_meta_z": row[12],
            "reasons": json.loads(row[13]) if row[13] else [],
            "created_at": row[14],
        })

    cursor.execute("""
        SELECT table_name,
               COUNT(*) as total,
               SUM(CASE WHEN severity='critical' THEN 1 ELSE 0 END) as critical_count,
               SUM(CASE WHEN severity='high' THEN 1 ELSE 0 END) as high_count,
               AVG(composite_score) as avg_score,
               MAX(composite_score) as max_score
        FROM ensemble_scores
        GROUP BY table_name
        ORDER BY max_score DESC
    """)
    stats = []
    for row in cursor.fetchall():
        stats.append({
            "table": row[0],
            "total_alerts": row[1],
            "critical": row[2],
            "high": row[3],
            "avg_score": round(row[4] or 0, 3),
            "max_score": round(row[5] or 0, 3),
        })

    calibration = get_calibration_status(conn)
    calibrated_count = sum(1 for c in calibration if c["calibrated"])

    return {
        "description": "Ensemble scorer sa naučenim pragovima — bez ijedne ručne vrednosti",
        "meta_z_threshold": META_Z_THRESHOLD,
        "ema_alpha": EMA_ALPHA,
        "min_calibration_samples": MIN_CALIBRATION_SAMPLES,
        "calibration_progress": {
            "total_detector_slots": len(calibration),
            "calibrated": calibrated_count,
            "still_learning": len(calibration) - calibrated_count,
        },
        "calibration_detail": calibration,
        "top_alerts": alerts,
        "table_stats": stats,
    }