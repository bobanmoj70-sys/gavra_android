"""Prava neuronska mreža koja uči OD NULE, bez ijedne poslovne pretpostavke.

Arhitektura: mali autoenkoder (feedforward, ručni backpropagation, samo numpy).
Za SVAKU tabelu se drži potpuno odvojena mreža sa sopstvenim, nasumično
inicijalizovanim težinama — ništa se ne uči unapred niti se preuzima gotov model.

Kako mreža "razume" proizvoljan red bez unapred poznate šeme:
- Svaki red (dict kolona -> vrednost) se pretvara u vektor FIKSNE dužine pomoću
  "feature hashing" trika: ime kolone (i, za tekstualne vrednosti, i sama vrednost)
  se hešira u jedan od FEATURE_DIM "kanala". Ovo je čisto matematička projekcija,
  ne poslovno znanje — radi identično za bilo koju tabelu/kolonu, uključujući one
  koje uopšte ne postoje danas.
- Mreža uči da REKONSTRUIŠE taj vektor (autoenkoder). Kada joj to ne uspe znatno
  lošije nego inače za tu tabelu (visok reconstruction error, meren z-skorom u
  odnosu na sopstvenu istoriju), to je znak da je KOMBINACIJA vrednosti u redu
  neobična — nešto što prosta statistika po jednoj koloni ne bi videla.

Sve težine, statistika normalizacije i statistika greške se čuvaju po tabeli u
SQLite (`neural_state`), tako da mreža nastavlja učenje tamo gde je stala i posle
restarta servera.
"""
import hashlib
import json
import sqlite3
from datetime import datetime

import numpy as np

# --- HIPERPARAMETRI (isključivo tehnički, ne poslovni) ---
FEATURE_DIM = 64        # fiksna dužina ulaznog vektora (feature hashing prostor)
                         # 64 umesto 24 → drastično manje hash kolizija za tabele sa >10 kolona
HIDDEN_DIM = 16          # veličina "usko grlo" (bottleneck) sloja autoenkodera
LEARNING_RATE = 0.05     # početna stopa učenja — smanjuje se kako mreža vidi više redova (adaptive)
CLIP_VALUE = 10.0        # sprečava eksploziju gradijenata/vrednosti
MIN_OBSERVATIONS_FOR_ANOMALY = 50   # povećano: mreža mora da vidi više pre nego što sme da prijavljuje anomalije
ERROR_Z_SCORE_THRESHOLD = 3.0
MAX_ANOMALY_LOG_ROWS = 5000

# EMA (Exponential Moving Average) decay za error statistiku:
# Mreža "zaboravlja" staro normalno ponašanje kako se biznis menja.
# alpha=0.003 → ~333 novih redova "poluvreme zaboravljanja" starog modela.
EMA_ALPHA = 0.003

# Adaptive learning rate: LR se smanjuje sa ∝ 1/sqrt(n) da bi se mreža
# stabilizovala na velikim tabelama, a brzo učila na malim.
MIN_LR = 0.005  # donja granica da učenje nikad ne stane potpuno

_IGNORED_KEYS = {"id", "created_at", "updated_at", "embedding"}


def init_schema(conn: sqlite3.Connection):
    """Kreira tabele potrebne neuronskoj mreži (poziva se jednom pri startu)."""
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS neural_state (
            table_name TEXT PRIMARY KEY,
            weights_json TEXT NOT NULL,
            feature_mean_json TEXT NOT NULL,
            feature_m2_json TEXT NOT NULL,
            feature_n INTEGER NOT NULL DEFAULT 0,
            error_mean REAL NOT NULL DEFAULT 0,
            error_m2 REAL NOT NULL DEFAULT 0,
            error_n INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS neural_anomaly_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            source_id TEXT,
            detail TEXT NOT NULL,
            error_value REAL,
            error_z_score REAL,
            created_at TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_neural_anomaly_table ON neural_anomaly_log(table_name)")
    conn.commit()


def reset_brain(conn: sqlite3.Connection):
    """Briše SVE naučene težine i statistiku — mreža se ponovo rađa nasumično inicijalizovana."""
    cursor = conn.cursor()
    cursor.execute("DELETE FROM neural_state")
    cursor.execute("DELETE FROM neural_anomaly_log")
    conn.commit()


def _stable_hash(text: str) -> int:
    """Deterministički heš (nezavisan od PYTHONHASHSEED, za razliku od ugrađenog hash())."""
    return int(hashlib.md5(text.encode("utf-8")).hexdigest(), 16)


def _bucket(text: str, dim: int) -> int:
    return _stable_hash(text) % dim


def _row_to_features(row: dict) -> np.ndarray:
    """Pretvara proizvoljan red (bilo koje tabele, bilo koje šeme) u fiksni vektor
    dužine FEATURE_DIM koristeći feature hashing. Nema nikakve pretpostavke o
    imenima kolona niti o tipu tabele — radi identično za svaku tabelu."""
    features = np.zeros(FEATURE_DIM, dtype=np.float64)

    for key, value in row.items():
        if key in _IGNORED_KEYS or value is None:
            continue

        key_str = str(key)

        if isinstance(value, bool):
            idx = _bucket(key_str, FEATURE_DIM)
            features[idx] += 1.0 if value else -1.0
            continue

        if isinstance(value, (int, float)):
            idx = _bucket(key_str, FEATURE_DIM)
            # Simetrični log-skaliranje da bi velike i male vrednosti (npr. 5 i 500000)
            # ostale u razumnom numeričkom opsegu za mrežu, bez ijedne poslovne pretpostavke
            # o tome šta je "normalna" vrednost za tu kolonu.
            v = float(value)
            scaled = np.sign(v) * np.log1p(abs(v))
            features[idx] += scaled
            continue

        if isinstance(value, (list, dict)):
            # Strukturirane vrednosti (JSON kolone): heš dužine/oblika je jedini signal
            # koji uzimamo — ne ulazimo u poslovnu interpretaciju sadržaja.
            idx = _bucket(key_str + ":len", FEATURE_DIM)
            try:
                features[idx] += np.log1p(len(value))
            except TypeError:
                pass
            continue

        # Sve ostalo (string, kategorijske vrednosti) — heširamo ime kolone + vrednost
        # zajedno u jedan kanal, tako da svaka DISTINKTNA (kolona, vrednost) kombinacija
        # dobija svoj "otisak" u prostoru.
        idx = _bucket(f"{key_str}={value}", FEATURE_DIM)
        features[idx] += 1.0

    np.clip(features, -CLIP_VALUE, CLIP_VALUE, out=features)
    return features


def _new_weights() -> dict:
    """Xavier-nalik nasumična inicijalizacija — mreža kreće apsolutno od nule."""
    rng = np.random.default_rng()
    limit1 = np.sqrt(6.0 / (FEATURE_DIM + HIDDEN_DIM))
    limit2 = np.sqrt(6.0 / (HIDDEN_DIM + FEATURE_DIM))
    return {
        "W1": (rng.uniform(-limit1, limit1, (FEATURE_DIM, HIDDEN_DIM))).tolist(),
        "b1": np.zeros(HIDDEN_DIM).tolist(),
        "W2": (rng.uniform(-limit2, limit2, (HIDDEN_DIM, FEATURE_DIM))).tolist(),
        "b2": np.zeros(FEATURE_DIM).tolist(),
    }


def _load_state(conn: sqlite3.Connection, table_name: str) -> dict:
    cursor = conn.cursor()
    cursor.execute("SELECT weights_json, feature_mean_json, feature_m2_json, feature_n, error_mean, error_m2, error_n FROM neural_state WHERE table_name=?", (table_name,))
    row = cursor.fetchone()

    if row is None:
        state = {
            "weights": _new_weights(),
            "feature_mean": np.zeros(FEATURE_DIM),
            "feature_m2": np.zeros(FEATURE_DIM),
            "feature_n": 0,
            "error_mean": 0.0,
            "error_m2": 0.0,
            "error_n": 0,
        }
        return state

    weights_json, mean_json, m2_json, feature_n, error_mean, error_m2, error_n = row
    return {
        "weights": json.loads(weights_json),
        "feature_mean": np.array(json.loads(mean_json), dtype=np.float64),
        "feature_m2": np.array(json.loads(m2_json), dtype=np.float64),
        "feature_n": feature_n,
        "error_mean": error_mean,
        "error_m2": error_m2,
        "error_n": error_n,
    }


def _save_state(conn: sqlite3.Connection, table_name: str, state: dict):
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cursor.execute("""
        INSERT INTO neural_state (table_name, weights_json, feature_mean_json, feature_m2_json, feature_n, error_mean, error_m2, error_n, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(table_name) DO UPDATE SET
            weights_json=excluded.weights_json,
            feature_mean_json=excluded.feature_mean_json,
            feature_m2_json=excluded.feature_m2_json,
            feature_n=excluded.feature_n,
            error_mean=excluded.error_mean,
            error_m2=excluded.error_m2,
            error_n=excluded.error_n,
            updated_at=excluded.updated_at
    """, (
        table_name,
        json.dumps(state["weights"]),
        json.dumps(state["feature_mean"].tolist()),
        json.dumps(state["feature_m2"].tolist()),
        state["feature_n"],
        state["error_mean"],
        state["error_m2"],
        state["error_n"],
        now,
    ))
    conn.commit()


def _welford_update(mean: float, m2: float, n: int, new_value: float):
    """Jedan korak Welford-ovog online algoritma za srednju vrednost i varijansu."""
    n += 1
    delta = new_value - mean
    mean += delta / n
    delta2 = new_value - mean
    m2 += delta * delta2
    return mean, m2, n


def _forward(x: np.ndarray, weights: dict):
    W1 = np.array(weights["W1"])
    b1 = np.array(weights["b1"])
    W2 = np.array(weights["W2"])
    b2 = np.array(weights["b2"])

    z1 = x @ W1 + b1
    a1 = np.tanh(z1)
    out = a1 @ W2 + b2  # linearni izlazni sloj (rekonstrukcija)
    return out, a1, W1, b1, W2, b2


def _adaptive_lr(n: int) -> float:
    """Stopa učenja se smanjuje sa brojem videnih redova: LR ∝ 1/sqrt(n).
    Tabele sa malo redova uče brzo; tabele sa 50k+ redova su stabilne."""
    if n < 1:
        return LEARNING_RATE
    return max(MIN_LR, LEARNING_RATE / (1.0 + 0.1 * np.sqrt(n)))


def _train_step(x: np.ndarray, weights: dict, n_observations: int = 0) -> float:
    """Jedan korak forward + backward propagacije (online gradient descent).
    Vraća reconstruction error (MSE) IZRAČUNAT PRE ažuriranja težina (tako da
    error odražava koliko je mreža bila 'iznenađena' ovim redom, a ne koliko
    dobro već zna posle učenja iz njega).
    n_observations: broj videnih redova za adaptive learning rate."""
    out, a1, W1, b1, W2, b2 = _forward(x, weights)

    diff = out - x
    error = float(np.mean(diff ** 2))

    lr = _adaptive_lr(n_observations)

    # --- Backpropagation (ručno, bez ijedne biblioteke za automatsku diferencijaciju) ---
    dz2 = (2.0 / FEATURE_DIM) * diff              # (FEATURE_DIM,)
    dW2 = np.outer(a1, dz2)                        # (HIDDEN_DIM, FEATURE_DIM)
    db2 = dz2                                       # (FEATURE_DIM,)

    da1 = dz2 @ W2.T                                # (HIDDEN_DIM,)
    dz1 = da1 * (1.0 - a1 ** 2)                     # tanh izvod
    dW1 = np.outer(x, dz1)                          # (FEATURE_DIM, HIDDEN_DIM)
    db1 = dz1                                       # (HIDDEN_DIM,)

    # Gradient clipping radi numeričke stabilnosti (čisto tehnička mera, ne poslovna)
    for grad in (dW1, db1, dW2, db2):
        np.clip(grad, -CLIP_VALUE, CLIP_VALUE, out=grad)

    W1 -= lr * dW1
    b1 -= lr * db1
    W2 -= lr * dW2
    b2 -= lr * db2

    weights["W1"] = W1.tolist()
    weights["b1"] = b1.tolist()
    weights["W2"] = W2.tolist()
    weights["b2"] = b2.tolist()

    return error


def _trim_anomaly_log(cursor: sqlite3.Cursor):
    cursor.execute("SELECT COUNT(*) FROM neural_anomaly_log")
    count = cursor.fetchone()[0]
    if count > MAX_ANOMALY_LOG_ROWS:
        excess = count - MAX_ANOMALY_LOG_ROWS
        cursor.execute("""
            DELETE FROM neural_anomaly_log WHERE id IN (
                SELECT id FROM neural_anomaly_log ORDER BY id ASC LIMIT ?
            )
        """, (excess,))


def _classify_thought(z: float | None, err_n: int) -> tuple[str, str]:
    """Pretvara z-skor u čitljivu kategoriju 'razmišljanja' mreže. Pragovi su čisto
    tehnički (kvartili z-raspodele), ne poslovni koncept."""
    if err_n < MIN_OBSERVATIONS_FOR_ANOMALY:
        return "uci", "🍼 Još učim ovu tabelu (premalo iskustva da bih sudila)"
    if z is None:
        return "uci", "🍼 Još učim ovu tabelu (premalo iskustva da bih sudila)"
    if z > ERROR_Z_SCORE_THRESHOLD:
        return "anomalija", "🚨 Ovo mi je vrlo neobično — ne liči na ništa što sam do sad videla"
    if z > 1.5:
        return "neuobicajeno", "🤔 Ovo mi je pomalo neobično, ali nije van svake mere"
    if z > 0:
        return "normalno", "✅ Ovo mi je poznato, u okviru je onoga što sam naučila"
    return "vrlo_poznato", "😌 Ovo mi je vrlo poznato, skoro identično prethodnim primerima"


def observe_and_learn(conn: sqlite3.Connection, table_name: str, row: dict, source_id: str) -> dict | None:
    """Glavna ulazna tačka: mreža vidi jedan red, uči jedan korak iz njega, i vraća
    detalje anomalije AKO je reconstruction error neuobičajeno visok u odnosu na
    sopstvenu istoriju za tu tabelu. Vraća None ako nema anomalije ili ako mreža
    još uvek nema dovoljno iskustva (MIN_OBSERVATIONS_FOR_ANOMALY) da bi sudila.
    Za PUN uvid u svaku pojedinačnu odluku (i kad NIJE anomalija), koristi
    observe_and_think() koja vraća 'misao' mreže o svakom redu."""
    thought = observe_and_think(conn, table_name, row, source_id)
    if thought and thought["stage"] == "anomalija":
        return {
            "table": thought["table"],
            "source_id": thought["source_id"],
            "error": thought["error"],
            "z_score": thought["z_score"],
            "detail": thought["detail"],
        }
    return None


def observe_and_think(conn: sqlite3.Connection, table_name: str, row: dict, source_id: str) -> dict | None:
    """Kao observe_and_learn, ali UVEK vraća 'misao' mreže o redu (ne samo kad je
    anomalija) — koristi se za živi prikaz 'šta mreža trenutno misli/uči/zaključuje'
    u UI-ju. Mreža i dalje uči (jedan korak backpropagation-a) iz svakog reda; ovo
    je samo dodatna, čitljivija projekcija istog internog stanja."""
    if not row:
        return None

    features = _row_to_features(row)
    if not np.any(features):
        return None  # red bez ijedne korisne vrednosti (npr. samo id/created_at)

    state = _load_state(conn, table_name)

    # Normalizacija ulaza pomoću tekuće (online) statistike po feature kanalu —
    # čisto tehnička normalizacija, ne poslovna pretpostavka.
    mean = state["feature_mean"]
    m2 = state["feature_m2"]
    n = state["feature_n"]
    std = np.sqrt(m2 / n) if n > 1 else np.ones(FEATURE_DIM)
    std = np.where(std < 1e-6, 1.0, std)
    normalized = (features - mean) / std
    np.clip(normalized, -CLIP_VALUE, CLIP_VALUE, out=normalized)

    error = _train_step(normalized, state["weights"], n_observations=n)

    # Ažuriraj statistiku ulaznih feature-a NAKON treninga (tako mreža uvek trenira
    # na normalizaciji dostupnoj DO ovog trenutka, sprečavajući curenje informacija iz budućnosti)
    for i in range(FEATURE_DIM):
        mean[i], m2[i], _ = _welford_update(mean[i], m2[i], n, features[i])
    state["feature_n"] = n + 1
    state["feature_mean"] = mean
    state["feature_m2"] = m2

    # Ažuriraj statistiku grešaka:
    # Koristimo EMA (Exponential Moving Average) umesto čistog Welford-a za error_mean,
    # tako da mreža "zaboravlja" staro normalno ponašanje ako se biznis promeni.
    # Za varijansu (m2) i dalje koristimo Welford — samo mean se EMA-uje.
    err_n = state["error_n"] + 1
    if state["error_n"] < MIN_OBSERVATIONS_FOR_ANOMALY:
        # U ranoj fazi: čisti Welford da se brzo nauči osnovna distribucija
        err_mean, err_m2, _ = _welford_update(state["error_mean"], state["error_m2"], state["error_n"], error)
    else:
        # Posle dovoljno uzoraka: EMA decay za mean (adaptivno), Welford za varijansu
        err_mean = (1.0 - EMA_ALPHA) * state["error_mean"] + EMA_ALPHA * error
        _, err_m2, _ = _welford_update(state["error_mean"], state["error_m2"], state["error_n"], error)
    state["error_mean"] = err_mean
    state["error_m2"] = err_m2
    state["error_n"] = err_n

    z = None
    err_std = np.sqrt(err_m2 / err_n) if err_n > 1 else 0.0
    if err_n > 1 and err_std > 1e-9:
        z = float((error - err_mean) / err_std)

    stage, thought_text = _classify_thought(z, err_n)

    detail = (
        f"Red iz '{table_name}' (id={source_id}): reconstruction error={error:.4f}"
        + (f", {z:.1f} standardnih devijacija u odnosu na prosek." if z is not None else " (još gradim osećaj za normalu ove tabele.)")
    )

    thought = {
        "table": table_name,
        "source_id": source_id,
        "error": float(error),
        "z_score": z,
        "stage": stage,
        "thought": thought_text,
        "detail": detail,
        "observations_seen": int(err_n),
    }

    if stage == "anomalija":
        thought["detail"] = (
            f"Neuronska mreža nije uspela da rekonstruiše red iz '{table_name}' "
            f"(id={source_id}): reconstruction error={error:.4f}, što je {z:.1f} standardnih "
            f"devijacija iznad proseka za ovu tabelu. Kombinacija vrednosti u ovom redu je "
            f"neobična u odnosu na sve što je mreža do sada naučila."
        )
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO neural_anomaly_log (table_name, source_id, detail, error_value, error_z_score, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (table_name, source_id, thought["detail"], error, float(z), datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        _trim_anomaly_log(cursor)
        conn.commit()

    _save_state(conn, table_name, state)
    return thought


def get_report(conn: sqlite3.Connection) -> dict:
    """Vraća čitljiv izveštaj o stanju neuronske mreže za sve tabele koje je do sada videla."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT table_name, feature_n, error_mean, error_n, updated_at
        FROM neural_state ORDER BY table_name ASC
    """)
    tables = []
    for table_name, feature_n, error_mean, error_n, updated_at in cursor.fetchall():
        tables.append({
            "table": table_name,
            "observations": feature_n,
            "avg_reconstruction_error": round(error_mean, 5) if error_mean else 0,
            "error_samples": error_n,
            "updated_at": updated_at,
            "ready_for_anomaly_detection": error_n >= MIN_OBSERVATIONS_FOR_ANOMALY,
        })

    cursor.execute("""
        SELECT table_name, source_id, detail, error_value, error_z_score, created_at
        FROM neural_anomaly_log ORDER BY id DESC LIMIT 50
    """)
    anomalies = []
    for table_name, source_id, detail, error_value, error_z_score, created_at in cursor.fetchall():
        anomalies.append({
            "table": table_name,
            "source_id": source_id,
            "detail": detail,
            "error": error_value,
            "z_score": error_z_score,
            "created_at": created_at,
        })

    return {
        "architecture": f"autoencoder {FEATURE_DIM}->{HIDDEN_DIM}->{FEATURE_DIM}, feature hashing, tanh + linear, manual backprop (numpy)",
        "tables": tables,
        "recent_anomalies": anomalies,
    }
