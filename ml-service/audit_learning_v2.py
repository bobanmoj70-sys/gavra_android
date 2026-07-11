import os
import asyncio
import json
from dotenv import load_dotenv
from supabase._async.client import create_client
import sqlite3

load_dotenv()
url = os.environ.get('SUPABASE_URL')
key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
DB_FILE = os.path.join(os.path.dirname(__file__), "gavra_ai.db")

TABLES_TO_SYNC = [
    "v3_adrese", "v3_auth", "v3_vozila", "v3_zahtevi",
    "v3_gorivo", "v3_finansije", "v3_racuni",
    "v3_trenutna_dodela", "v3_trenutna_dodela_slot",
    "v3_operativna_nedelja", "v3_kapacitet_slots", "v3_app_settings"
]

TECHNICAL_COLS = {"id", "created_at", "updated_at"}


def extract_leaf_values(value):
    """Rekurzivno izvlači sve primitivne vrednosti iz dict/list."""
    leaves = []
    if isinstance(value, dict):
        for v in value.values():
            leaves.extend(extract_leaf_values(v))
    elif isinstance(value, list):
        for item in value:
            leaves.extend(extract_leaf_values(item))
    elif value is not None and value != "":
        leaves.append(value)
    return leaves


def normalize_value(value):
    """Convert value to searchable string forms."""
    if value is None:
        return []
    if isinstance(value, bool):
        forms = [str(value).lower()]
        # Dodaj i lokalizovane/oblikovane varijante
        if value:
            forms.extend(["da", "yes", "enabled", "true"])
        else:
            forms.extend(["ne", "no", "disabled", "false"])
        return forms
    if isinstance(value, (int, float)):
        return [str(value), str(int(value)) if float(value).is_integer() else str(value)]
    if isinstance(value, (dict, list)):
        # Pored kanoničkog JSON-a, proveri i sve listove
        forms = []
        try:
            forms.append(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')))
            forms.append(json.dumps(value, ensure_ascii=False, sort_keys=True))
        except (TypeError, ValueError):
            pass
        for leaf in extract_leaf_values(value):
            leaf_forms = normalize_value(leaf)
            # Za listove vremena/datumâ, dodaj i string reprezentaciju
            forms.extend(leaf_forms)
        return list(dict.fromkeys(forms))
    s = str(value).strip()
    if not s:
        return []
    forms = [s]
    # For ISO timestamps, also add just the date part
    if "T" in s and len(s) >= 10:
        forms.append(s[:10])
    return forms


def value_found(content, value):
    content_lower = content.lower()
    for form in normalize_value(value):
        if form.lower() in content_lower:
            return True
    return False


async def main():
    supabase = await create_client(url, key)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    print("=== AUDIT: AI LEARNING COVERAGE (data-based) ===\n")

    overall_total_values = 0
    overall_found_values = 0

    for table in TABLES_TO_SYNC:
        try:
            resp = await supabase.table(table).select('*', count='exact').limit(1000).execute()
            rows = resp.data or []
            supabase_count = resp.count if hasattr(resp, 'count') else len(rows)

            c.execute("SELECT COUNT(*) FROM ai_knowledge_base WHERE source_table=?", (table,))
            local_count = c.fetchone()[0]

            c.execute("SELECT source_id, content FROM ai_knowledge_base WHERE source_table=?", (table,))
            kb_by_id = {row[0]: row[1] for row in c.fetchall()}

            status = "OK" if local_count == supabase_count else f"MISMATCH ({local_count}/{supabase_count})"
            print(f"{table}:")
            print(f"  Supabase rows: {supabase_count}")
            print(f"  Local KB rows: {local_count}")
            print(f"  Status: {status}")

            if not rows:
                print()
                continue

            cols = [col for col in rows[0].keys() if col not in TECHNICAL_COLS]
            col_total = {col: 0 for col in cols}
            col_found = {col: 0 for col in cols}
            row_coverage = []

            for row in rows:
                source_id = str(row.get("id", ""))
                content = kb_by_id.get(source_id, "")
                if not content:
                    continue

                row_total = 0
                row_found = 0
                for col in cols:
                    val = row.get(col)
                    if val is None or val == "" or val == [] or val == {}:
                        continue
                    col_total[col] += 1
                    row_total += 1
                    if value_found(content, val):
                        col_found[col] += 1
                        row_found += 1

                if row_total > 0:
                    row_coverage.append(row_found / row_total)

            table_total = sum(col_total.values())
            table_found = sum(col_found.values())
            overall_total_values += table_total
            overall_found_values += table_found

            if table_total > 0:
                pct = (table_found / table_total) * 100
                avg_row = sum(row_coverage) / len(row_coverage) * 100 if row_coverage else 0
                print(f"  Data value coverage: {table_found}/{table_total} ({pct:.1f}%)")
                print(f"  Avg row coverage: {avg_row:.1f}%")

                low_cols = [col for col in cols if col_total[col] > 0 and col_found[col] / col_total[col] < 0.5]
                if low_cols:
                    print(f"  Columns with <50% value coverage: {', '.join(low_cols)}")

                zero_cols = [col for col in cols if col_total[col] > 0 and col_found[col] == 0]
                if zero_cols:
                    print(f"  Columns with 0% value coverage: {', '.join(zero_cols)}")
            else:
                print("  No non-null data values to check")

            print()
        except Exception as e:
            print(f"{table}: ERROR - {e}\n")

    if overall_total_values > 0:
        overall_pct = (overall_found_values / overall_total_values) * 100
        print(f"=== OVERALL DATA COVERAGE: {overall_found_values}/{overall_total_values} ({overall_pct:.1f}%) ===")
    else:
        print("=== OVERALL DATA COVERAGE: N/A ===")

    conn.close()


asyncio.run(main())
