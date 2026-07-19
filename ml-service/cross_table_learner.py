"""Modul za učenje veza između tabela (foreign keys) i cross-table anomalije.

Učenje:
- Automatski detektuj veze (kolona X u tabeli A ima iste vrednosti kao id u tabeli B)
- Za svaku vrednost, nauči: "U DRUGIM tabelama, gde se OVA vrednost pojavljuje?"
- Ako se neka vrednost pojavi u "neobičnoj" tabeli → ANOMALIJA

Primer:
  Red: {driver_id: 777}
  Sistem detektuje: driver_id je FK na drivers.id
  Detektuje: drivers.id=777 ima status='banned'
  Zaključak: "Banned driver je napravio akciju → ANOMALIJA"
"""

import json
import sqlite3
from datetime import datetime
from collections import defaultdict

import numpy as np

# --- HIPERPARAMETRI ---
CORRELATION_THRESHOLD = 0.8  # % redaka gde se kolone "poklapaju" = FK
MIN_DISTINCT_FOR_FK = 10     # Najmanje distinktnih vrednosti za FK detekciju
MIN_SAMPLES_FOR_CROSS_ANOMALY = 50

_IGNORED_KEYS = {"id", "created_at", "updated_at", "embedding"}


def init_schema(conn: sqlite3.Connection):
    """Kreira tabele za cross-table učenje."""
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS detected_foreign_keys (
            table_name TEXT NOT NULL,
            column_name TEXT NOT NULL,
            referenced_table TEXT NOT NULL,
            referenced_column TEXT NOT NULL,
            confidence REAL,
            samples_checked INTEGER,
            updated_at TEXT,
            PRIMARY KEY (table_name, column_name, referenced_table, referenced_column)
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cross_table_context (
            table_name TEXT NOT NULL,
            value TEXT NOT NULL,
            context_table TEXT NOT NULL,
            context_column TEXT NOT NULL,
            context_value TEXT NOT NULL,
            co_occurrence_count INTEGER DEFAULT 1,
            updated_at TEXT,
            PRIMARY KEY (table_name, value, context_table, context_column, context_value)
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cross_table_anomalies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            column_name TEXT NOT NULL,
            value TEXT NOT NULL,
            source_id TEXT,
            anomaly_reason TEXT,
            referenced_table TEXT,
            referenced_value TEXT,
            created_at TEXT
        )
    """)
    
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_fk_table ON detected_foreign_keys(table_name)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_cross_table ON cross_table_context(table_name, value)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_cross_anomaly ON cross_table_anomalies(table_name)")
    
    conn.commit()


def reset_brain(conn: sqlite3.Connection):
    """Briše sve naučene cross-table veze."""
    cursor = conn.cursor()
    cursor.execute("DELETE FROM detected_foreign_keys")
    cursor.execute("DELETE FROM cross_table_context")
    cursor.execute("DELETE FROM cross_table_anomalies")
    conn.commit()


def _discover_foreign_keys(conn: sqlite3.Connection, all_tables: list[str], all_rows: dict) -> dict:
    """Detektuje verovatne foreign keys poređenjem distinct vrednosti.
    
    Logika:
    - Ako kolona A u tabeli T ima M distinktnih vrednosti
    - A kolona id u tabeli R ima ista M vrednosti (ili većinu)
    - → A je verovatno FK na R.id
    """
    detected_fks = {}
    
    for table_name in all_tables:
        if table_name not in all_rows or not all_rows[table_name]:
            continue
        
        rows = all_rows[table_name]
        
        # Izvuci distinct vrednosti po koloni
        column_values = defaultdict(set)
        for row in rows:
            for key, value in row.items():
                if key not in _IGNORED_KEYS and value is not None:
                    column_values[key].add(str(value))
        
        # Za svaku kolonu, proveri da li se poklapaju sa id kolonama drugih tabela
        for col_name, distinct_values in column_values.items():
            if len(distinct_values) < MIN_DISTINCT_FOR_FK:
                continue
            
            for other_table in all_tables:
                if other_table == table_name or other_table not in all_rows:
                    continue
                
                other_rows = all_rows[other_table]
                other_ids = set()
                for row in other_rows:
                    rid = row.get("id")
                    if rid is not None:
                        other_ids.add(str(rid))
                
                if len(other_ids) < MIN_DISTINCT_FOR_FK:
                    continue
                
                # Koliko se poklapaju?
                overlap = len(distinct_values & other_ids)
                if overlap == 0:
                    continue
                
                correlation = overlap / max(len(distinct_values), len(other_ids))
                
                if correlation >= CORRELATION_THRESHOLD:
                    key = (table_name, col_name, other_table)
                    if key not in detected_fks or detected_fks[key]["confidence"] < correlation:
                        detected_fks[key] = {
                            "confidence": correlation,
                            "samples": len(distinct_values),
                        }
    
    return detected_fks


def learn_foreign_keys(conn: sqlite3.Connection, all_tables: list[str], all_rows: dict):
    """Detektuje i sprema FK veze u bazu."""
    fks = _discover_foreign_keys(conn, all_tables, all_rows)
    
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    for (table_name, col_name, ref_table), data in fks.items():
        cursor.execute("""
            INSERT INTO detected_foreign_keys 
            (table_name, column_name, referenced_table, referenced_column, confidence, samples_checked, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT DO UPDATE SET
                confidence=excluded.confidence,
                samples_checked=excluded.samples_checked,
                updated_at=excluded.updated_at
        """, (table_name, col_name, ref_table, "id", data["confidence"], data["samples"], now))
    
    conn.commit()


def learn_cross_table_context(conn: sqlite3.Connection, table_name: str, row: dict, fk_map: dict):
    """Uči kontekst: ako je vrednost X u koloni A FK na drugu tabelu,
    nauči: "Gde se vrednost X pojavljuje u drugoj tabeli?"
    
    fk_map: {(table, col): referenced_table}
    """
    if not fk_map or not row:
        return
    
    cursor = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    for key, value in row.items():
        if key in _IGNORED_KEYS or value is None:
            continue
        
        fk_key = (table_name, key)
        if fk_key not in fk_map:
            continue
        
        ref_table = fk_map[fk_key]
        value_str = str(value)
        
        # Dohvati sve kolone iz referenced tabele za tu vrednost (id)
        try:
            ref_rows = cursor.execute(
                f"SELECT * FROM {ref_table} WHERE id = ?",
                (value_str,)
            ).fetchall()
            
            if ref_rows and len(ref_rows) > 0:
                ref_row = ref_rows[0]
                ref_dict = dict(ref_row)
                
                # Spremi kontekst: vrednost value_str pojavljuje se sa ovim vrednostima
                for ctx_col, ctx_val in ref_dict.items():
                    if ctx_col not in _IGNORED_KEYS and ctx_val is not None:
                        ctx_val_str = str(ctx_val)
                        
                        cursor.execute("""
                            INSERT INTO cross_table_context
                            (table_name, value, context_table, context_column, context_value, co_occurrence_count, updated_at)
                            VALUES (?, ?, ?, ?, ?, 1, ?)
                            ON CONFLICT DO UPDATE SET
                                co_occurrence_count = co_occurrence_count + 1,
                                updated_at = excluded.updated_at
                        """, (table_name, value_str, ref_table, ctx_col, ctx_val_str, now))
        except Exception:
            pass
    
    conn.commit()


def detect_cross_table_anomaly(conn: sqlite3.Connection, table_name: str, row: dict, source_id: str) -> dict | None:
    """Detektuje anomalije kroz cross-table kontekst.
    
    Primer:
    - driver_id=777 je FK na drivers.id
    - drivers.id=777 ima status='banned'
    - drivers.status se nikada nije pojavljuje sa 'banned' kod drugih redaka
    → ANOMALIJA: "Banned driver radi nešto neobično"
    """
    cursor = conn.cursor()
    
    # Dohvati sve FK-ove
    cursor.execute("SELECT table_name, column_name, referenced_table FROM detected_foreign_keys WHERE table_name=?", (table_name,))
    fks = cursor.fetchall()
    
    if not fks:
        return None
    
    fk_map = {(row[0], row[1]): row[2] for row in fks}
    
    for key, value in row.items():
        if key not in fk_map or value is None:
            continue
        
        value_str = str(value)
        ref_table = fk_map[(table_name, key)]
        
        # Dohvati kontekst za ovu vrednost
        cursor.execute("""
            SELECT context_column, context_value, co_occurrence_count
            FROM cross_table_context
            WHERE table_name=? AND value=?
            ORDER BY co_occurrence_count DESC
        """, (table_name, value_str))
        
        contexts = cursor.fetchall()
        
        if not contexts:
            continue
        
        # Proveri da li je bilo šta čudno
        anomalies = []
        for ctx_col, ctx_val, count in contexts:
            # Ako se neka vrednost pojavljuje VRLO retko sa ovim ID-om
            if count < 3:  # Arbitrarna granica
                # Ovo je potencijalno čudno
                cursor.execute("""
                    SELECT COUNT(DISTINCT value)
                    FROM cross_table_context
                    WHERE table_name=? AND context_table=? AND context_column=? AND context_value=?
                """, (table_name, ref_table, ctx_col, ctx_val))
                
                total_with_context = cursor.fetchone()[0]
                
                if total_with_context > MIN_SAMPLES_FOR_CROSS_ANOMALY:
                    # Ova vrednost je RETKA sa ovim kontekstom
                    anomalies.append({
                        "context": f"{ref_table}.{ctx_col}='{ctx_val}'",
                        "rarity": total_with_context,
                    })
        
        if anomalies:
            detail = f"Red ima {key}={value_str} koje se retko pojavljuje sa kontekstom: " + ", ".join(
                [f"{a['context']}" for a in anomalies[:3]]
            )
            
            cursor.execute("""
                INSERT INTO cross_table_anomalies
                (table_name, column_name, value, source_id, anomaly_reason, referenced_table, referenced_value, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (table_name, key, value_str, source_id, detail, ref_table, value_str, datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
            
            conn.commit()
            
            return {
                "table": table_name,
                "column": key,
                "value": value_str,
                "source_id": source_id,
                "detail": detail,
                "anomaly_type": "cross_table_context",
            }
    
    return None


def get_cross_table_report(conn: sqlite3.Connection) -> dict:
    """Vraća izveštaj o cross-table vezama."""
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT table_name, column_name, referenced_table, referenced_column, confidence, samples_checked, updated_at
        FROM detected_foreign_keys ORDER BY table_name, column_name
    """)
    
    fks = []
    for row in cursor.fetchall():
        fks.append({
            "table": row[0],
            "column": row[1],
            "references": f"{row[2]}.{row[3]}",
            "confidence": round(row[4], 2),
            "samples": row[5],
            "updated_at": row[6],
        })
    
    cursor.execute("""
        SELECT table_name, column_name, value, anomaly_reason, referenced_table, created_at
        FROM cross_table_anomalies ORDER BY id DESC LIMIT 50
    """)
    
    anomalies = []
    for row in cursor.fetchall():
        anomalies.append({
            "table": row[0],
            "column": row[1],
            "value": row[2],
            "reason": row[3],
            "ref_table": row[4],
            "created_at": row[5],
        })
    
    return {
        "discovered_foreign_keys": fks,
        "cross_table_anomalies": anomalies,
    }
