"""Modul koji čini neuronsku mrežu 'pametnijom' — uči SOPSTVENE vektorske
reprezentacije (embeddinge) za svaku vrednost koju vidi u bazi, isključivo na
osnovu toga SA ČIM se ta vrednost pojavljuje zajedno u istom redu. Ovo je isti
princip na kom rade i pravi jezički modeli (word2vec/skip-gram stil), samo
treniran od nule, isključivo na tvojim podacima — bez ijednog gotovog modela
i bez ijedne poslovne pretpostavke o značenju bilo koje kolone.

Zašto je ovo 'pametnije' od proste detekcije anomalija:
- Anomaly-autoenkoder (neural_brain.py) samo ocenjuje "da li mi je ovaj red čudan".
- OVAJ modul aktivno GRADI mapu odnosa: koje vrednosti/entiteti se često pojavljuju
  zajedno (pa im mreža SAMA daje bliske vektore u prostoru), i uči da PREDVIDI
  vrednost numeričke kolone iz konteksta ostatka reda (regresija).
- Rezultat: mreža može da odgovori "koje vrednosti su slične/povezane sa X" i
  "šta bih očekivala da bude vrednost kolone Y u ovom redu" — a da nikad nije
  eksplicitno programirana da zna šta je "vozač", "gorivo" ili "grad". Sve veze
  koje otkrije su isključivo posledica statistike ko-pojavljivanja u TVOJIM
  podacima, ne unapred ugrađenog znanja o svetu.

Tehnika (SGNS — Skip-Gram with Negative Sampling, ista porodica algoritama kao
word2vec, ali treniran online, red-po-red, ovde umesto "prozora reči" koristimo
"isti red" kao kontekst):
- Svaka distinktna vrednost u bazi (npr. `grad=Beograd`, `status=aktivan`, ili
  slot `iznos` za numeričke kolone) dobija SVOJ vektor od EMBED_DIM brojeva,
  inicijalno nasumičan.
- Za par tokena koji se pojave U ISTOM REDU, mreža radi jedan SGD korak da im
  vektori budu bliži (veći dot product => slični).
- Za nasumično izabrane tokene koji se NISU pojavili u tom redu ("negativni
  uzorci"), radi korak da im vektori budu dalji.
- Posle dovoljno redova, tokeni koji se često pojavljuju zajedno završe blizu
  jedni drugima u vektorskom prostoru — to je jedini oblik "logičkog povezivanja"
  koji je moguć bez unapred ugrađenog znanja o jeziku/svetu.
"""
import hashlib
import json
import sqlite3
from datetime import datetime

import numpy as np

EMBED_DIM = 16
LEARNING_RATE = 0.05
NEGATIVE_SAMPLES = 4
CLIP_VALUE = 5.0
MAX_VOCAB_PER_TABLE = 5000   # bezbednosna kapa da vokabular ne raste unedogled

_IGNORED_KEYS = {"id", "created_at", "updated_at", "embedding"}


def init_schema(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS entity_embeddings (
            table_name TEXT NOT NULL,
            token TEXT NOT NULL,
            vector_json TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT,
            PRIMARY KEY (table_name, token)
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS numeric_predictors (
            table_name TEXT NOT NULL,
            column_name TEXT NOT NULL,
            weight_json TEXT NOT NULL,
            bias REAL NOT NULL DEFAULT 0,
            n INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT,
            PRIMARY KEY (table_name, column_name)
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_entity_emb_table ON entity_embeddings(table_name)")
    conn.commit()


def reset_brain(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("DELETE FROM entity_embeddings")
    cursor.execute("DELETE FROM numeric_predictors")
    conn.commit()


def _rng_vector() -> np.ndarray:
    rng = np.random.default_rng()
    return rng.uniform(-0.5, 0.5, EMBED_DIM)


def _row_to_tokens(row: dict) -> tuple[list[str], dict[str, float]]:
    """Pretvara red u listu simboličkih 'tokena' (za embeddinge) i posebno
    izdvaja skalirane numeričke vrednosti (za regresiju). Ne postoji nikakva
    pretpostavka o imenu kolone — svaka (kolona, vrednost) kombinacija postaje
    token na identičan način za bilo koju tabelu."""
    tokens = []
    numeric_values: dict[str, float] = {}

    for key, value in row.items():
        if key in _IGNORED_KEYS or value is None:
            continue
        key_str = str(key)

        if isinstance(value, bool):
            tokens.append(f"{key_str}={value}")
            continue

        if isinstance(value, (int, float)):
            v = float(value)
            scaled = float(np.sign(v) * np.log1p(abs(v)))
            numeric_values[key_str] = scaled
            # Numerička kolona i dalje učestvuje kao token u ko-pojavljivanju
            # (npr. da mreža poveže "postojanje vrednosti u koloni iznos" sa
            # drugim tokenima u redu), ali BEZ konkretne vrednosti u tokenu.
            tokens.append(key_str)
            continue

        if isinstance(value, (list, dict)):
            try:
                if len(value) > 0:
                    tokens.append(f"{key_str}:neprazno")
            except TypeError:
                pass
            continue

        # Kategorijske/tekstualne vrednosti — token je (kolona, vrednost) par
        tokens.append(f"{key_str}={value}")

    # Dedup uz očuvanje redosleda
    seen = set()
    unique_tokens = []
    for t in tokens:
        if t not in seen:
            seen.add(t)
            unique_tokens.append(t)

    return unique_tokens, numeric_values


def _load_vocab(conn: sqlite3.Connection, table_name: str, tokens: list[str]) -> dict[str, np.ndarray]:
    """Učitava embeddinge za dati skup tokena (kreira nove nasumične ako ne postoje)."""
    cursor = conn.cursor()
    vocab: dict[str, np.ndarray] = {}
    placeholders = ",".join("?" * len(tokens))
    if tokens:
        cursor.execute(
            f"SELECT token, vector_json FROM entity_embeddings WHERE table_name=? AND token IN ({placeholders})",
            (table_name, *tokens),
        )
        for token, vector_json in cursor.fetchall():
            vocab[token] = np.array(json.loads(vector_json), dtype=np.float64)

    for t in tokens:
        if t not in vocab:
            vocab[t] = _rng_vector()

    return vocab


def _sample_negatives(conn: sqlite3.Connection, table_name: str, exclude: set[str], k: int) -> list[tuple[str, np.ndarray]]:
    """Bira k nasumičnih tokena IZ POSTOJEĆEG VOKABULARA te tabele koji se NISU
    pojavili u trenutnom redu (za negative sampling). Ako vokabular još nije
    dovoljno bogat, vraća manje/nijedan negativni uzorak — to je u redu, prvi
    redovi po tabeli jednostavno grade vokabular."""
    cursor = conn.cursor()
    cursor.execute(
        "SELECT token, vector_json FROM entity_embeddings WHERE table_name=? ORDER BY RANDOM() LIMIT ?",
        (table_name, k + len(exclude)),
    )
    negatives = []
    for token, vector_json in cursor.fetchall():
        if token in exclude:
            continue
        negatives.append((token, np.array(json.loads(vector_json), dtype=np.float64)))
        if len(negatives) >= k:
            break
    return negatives


def _sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(x, -30, 30)))


def _save_vocab(conn: sqlite3.Connection, table_name: str, vocab: dict[str, np.ndarray], touched: set[str], counts_delta: dict[str, int]):
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    for token in touched:
        vector = vocab[token]
        np.clip(vector, -CLIP_VALUE, CLIP_VALUE, out=vector)
        delta = counts_delta.get(token, 0)
        cursor.execute("""
            INSERT INTO entity_embeddings (table_name, token, vector_json, count, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(table_name, token) DO UPDATE SET
                vector_json=excluded.vector_json,
                count=count + ?,
                updated_at=excluded.updated_at
        """, (table_name, token, json.dumps(vector.tolist()), delta, now, delta))
    conn.commit()


def _vocab_size(conn: sqlite3.Connection, table_name: str) -> int:
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM entity_embeddings WHERE table_name=?", (table_name,))
    return cursor.fetchone()[0]


def _load_predictor(conn: sqlite3.Connection, table_name: str, column: str) -> dict:
    cursor = conn.cursor()
    cursor.execute(
        "SELECT weight_json, bias, n FROM numeric_predictors WHERE table_name=? AND column_name=?",
        (table_name, column),
    )
    row = cursor.fetchone()
    if row is None:
        rng = np.random.default_rng()
        return {"weight": rng.uniform(-0.1, 0.1, EMBED_DIM), "bias": 0.0, "n": 0}
    weight_json, bias, n = row
    return {"weight": np.array(json.loads(weight_json), dtype=np.float64), "bias": bias, "n": n}


def _save_predictor(conn: sqlite3.Connection, table_name: str, column: str, predictor: dict):
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cursor.execute("""
        INSERT INTO numeric_predictors (table_name, column_name, weight_json, bias, n, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(table_name, column_name) DO UPDATE SET
            weight_json=excluded.weight_json,
            bias=excluded.bias,
            n=excluded.n,
            updated_at=excluded.updated_at
    """, (table_name, column, json.dumps(predictor["weight"].tolist()), predictor["bias"], predictor["n"], now))
    conn.commit()


def observe_and_relate(conn: sqlite3.Connection, table_name: str, row: dict, source_id: str) -> dict | None:
    """Glavna ulazna tačka za 'pametniji' deo mreže. Za jedan red:
    1) trenira skip-gram embeddinge (svi tokeni u redu se međusobno približavaju,
       nasumični tokeni iz ostatka vokabulara se udaljavaju),
    2) trenira po jedan regresioni korak za svaku numeričku kolonu (predvidi
       njenu vrednost iz proseka embeddinga OSTALIH tokena u redu).
    Vraća sažetak (za prikaz u UI-ju): koliko je tokena bilo u redu, i za svaku
    numeričku kolonu predviđenu-vs-stvarnu vrednost — čisto informativno, BEZ
    koncepta anomalije."""
    if not row or table_name is None:
        return None

    tokens, numeric_values = _row_to_tokens(row)
    if len(tokens) < 2:
        return None  # nema dovoljno konteksta u ovom redu da bi bilo šta naučila

    if _vocab_size(conn, table_name) >= MAX_VOCAB_PER_TABLE:
        # Bezbednosna kapa — i dalje dozvoljavamo regresiju/ažuriranje postojećih,
        # samo ne dodajemo NOVE tokene u vokabular ove tabele.
        vocab = _load_vocab(conn, table_name, [t for t in tokens])
    else:
        vocab = _load_vocab(conn, table_name, tokens)

    touched: set[str] = set()
    counts_delta: dict[str, int] = {}
    token_set = set(tokens)

    # --- Skip-gram korak: svaki token je "centar" jednom, kontekst su svi ostali u redu ---
    for i, center in enumerate(tokens):
        center_vec = vocab[center]
        context_tokens = tokens[:i] + tokens[i + 1:]

        for context in context_tokens:
            context_vec = vocab[context]

            # Pozitivan par: maksimizuj sigmoid(dot(center, context))
            score = _sigmoid(np.dot(center_vec, context_vec))
            grad = (1.0 - score) * LEARNING_RATE
            center_vec_new = center_vec + grad * context_vec
            context_vec_new = context_vec + grad * center_vec
            center_vec, context_vec = center_vec_new, context_vec_new
            vocab[context] = context_vec
            touched.add(context)

        vocab[center] = center_vec
        touched.add(center)
        counts_delta[center] = counts_delta.get(center, 0) + 1

        # Negativni uzorci: minimizuj sigmoid(dot(center, negative))
        negatives = _sample_negatives(conn, table_name, token_set, NEGATIVE_SAMPLES)
        for neg_token, neg_vec in negatives:
            score = _sigmoid(np.dot(center_vec, neg_vec))
            grad = -score * LEARNING_RATE
            center_vec = center_vec + grad * neg_vec
            neg_vec_new = neg_vec + grad * vocab[center]
            vocab[neg_token] = neg_vec_new
            touched.add(neg_token)
        vocab[center] = center_vec

    for t in touched:
        np.clip(vocab[t], -CLIP_VALUE, CLIP_VALUE, out=vocab[t])

    _save_vocab(conn, table_name, vocab, touched, counts_delta)

    # --- Regresija: predvidi svaku numeričku kolonu iz konteksta ostatka reda ---
    predictions = []
    if numeric_values:
        for column, actual_scaled in numeric_values.items():
            other_tokens = [t for t in tokens if t != column]
            if not other_tokens:
                continue
            context_vec = np.mean([vocab[t] for t in other_tokens], axis=0)

            predictor = _load_predictor(conn, table_name, column)
            predicted_scaled = float(np.dot(predictor["weight"], context_vec) + predictor["bias"])

            error = predicted_scaled - actual_scaled
            predictor["weight"] -= LEARNING_RATE * error * context_vec
            predictor["bias"] -= LEARNING_RATE * error
            predictor["n"] += 1
            _save_predictor(conn, table_name, column, predictor)

            # Vrati vrednosti u čitljiviju (delimično de-skaliranu) formu radi prikaza
            actual_real = float(np.sign(actual_scaled) * (np.expm1(abs(actual_scaled))))
            predicted_real = float(np.sign(predicted_scaled) * (np.expm1(abs(predicted_scaled))))

            predictions.append({
                "column": column,
                "actual": round(actual_real, 2),
                "predicted": round(predicted_real, 2),
                "confidence_samples": predictor["n"],
            })

    return {
        "table": table_name,
        "source_id": source_id,
        "tokens_seen": len(tokens),
        "vocab_size": _vocab_size(conn, table_name),
        "predictions": predictions,
    }


def _cosine(a: np.ndarray, b: np.ndarray) -> float:
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    if na < 1e-9 or nb < 1e-9:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def find_similar(conn: sqlite3.Connection, table_name: str, token: str, top_n: int = 8) -> list[dict]:
    """Vraća tokene koje je mreža SAMA naučila da su najsličniji datom tokenu
    (najbliži u naučenom vektorskom prostoru) — ovo je konkretan, proverljiv
    dokaz da mreža otkriva veze/obrasce ko-pojavljivanja u tvojim podacima."""
    cursor = conn.cursor()
    cursor.execute("SELECT vector_json FROM entity_embeddings WHERE table_name=? AND token=?", (table_name, token))
    row = cursor.fetchone()
    if row is None:
        return []
    target_vec = np.array(json.loads(row[0]), dtype=np.float64)

    cursor.execute("SELECT token, vector_json, count FROM entity_embeddings WHERE table_name=?", (table_name,))
    similarities = []
    for other_token, vector_json, count in cursor.fetchall():
        if other_token == token:
            continue
        other_vec = np.array(json.loads(vector_json), dtype=np.float64)
        sim = _cosine(target_vec, other_vec)
        similarities.append({"token": other_token, "similarity": round(sim, 4), "count": count})

    similarities.sort(key=lambda x: x["similarity"], reverse=True)
    return similarities[:top_n]


def get_report(conn: sqlite3.Connection) -> dict:
    """Izveštaj o naučenim entitetima i predviđanjima po tabeli."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT table_name, COUNT(*) as vocab_size, SUM(count) as total_observations
        FROM entity_embeddings GROUP BY table_name ORDER BY table_name ASC
    """)
    tables = []
    for table_name, vocab_size, total_observations in cursor.fetchall():
        cursor.execute("""
            SELECT token, count FROM entity_embeddings
            WHERE table_name=? ORDER BY count DESC LIMIT 10
        """, (table_name,))
        top_tokens = [{"token": t, "count": c} for t, c in cursor.fetchall()]

        cursor.execute("""
            SELECT column_name, n FROM numeric_predictors WHERE table_name=?
        """, (table_name,))
        predictors = [{"column": col, "trained_on": n} for col, n in cursor.fetchall()]

        tables.append({
            "table": table_name,
            "vocab_size": vocab_size,
            "total_observations": int(total_observations or 0),
            "top_tokens": top_tokens,
            "numeric_predictors": predictors,
        })

    return {
        "method": "Skip-gram embeddings (SGNS, word2vec stil) + online regresija, treniran isključivo iz tvojih podataka",
        "embedding_dim": EMBED_DIM,
        "tables": tables,
    }
