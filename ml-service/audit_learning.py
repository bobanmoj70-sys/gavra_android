import os
import asyncio
import re
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

async def main():
    supabase = await create_client(url, key)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    
    print("=== AUDIT: AI LEARNING COVERAGE ===\n")
    
    for table in TABLES_TO_SYNC:
        try:
            resp = await supabase.table(table).select('*', count='exact').limit(1000).execute()
            supabase_count = resp.count if hasattr(resp, 'count') else len(resp.data)
            
            c.execute("SELECT COUNT(*) FROM ai_knowledge_base WHERE source_table=?", (table,))
            local_count = c.fetchone()[0]
            
            sample_cols = []
            if resp.data:
                sample_cols = list(resp.data[0].keys())
            
            c.execute("SELECT content FROM ai_knowledge_base WHERE source_table=? LIMIT 1", (table,))
            sample_local = c.fetchone()
            
            status = "OK" if local_count == supabase_count else f"MISMATCH ({local_count}/{supabase_count})"
            print(f"{table}:")
            print(f"  Supabase rows: {supabase_count}")
            print(f"  Local KB rows: {local_count}")
            print(f"  Status: {status}")
            print(f"  Columns in Supabase ({len(sample_cols)}): {', '.join(sample_cols[:20])}{'...' if len(sample_cols) > 20 else ''}")
            if sample_local:
                print(f"  Local sample: {sample_local[0][:150]}...")
            print()
        except Exception as e:
            print(f"{table}: ERROR - {e}\n")
    
    # Detailed column coverage check
    print("\n=== COLUMN COVERAGE CHECK ===\n")
    for table in TABLES_TO_SYNC:
        try:
            resp = await supabase.table(table).select('*').limit(1).execute()
            if not resp.data:
                continue
            cols = list(resp.data[0].keys())
            
            # Get all local content for this table
            c.execute("SELECT content FROM ai_knowledge_base WHERE source_table=?", (table,))
            contents = [row[0] for row in c.fetchall()]
            all_content = " ".join(contents).lower()
            
            print(f"{table}:")
            missing_in_content = []
            present_in_content = []
            for col in cols:
                if col.lower() in all_content:
                    present_in_content.append(col)
                else:
                    missing_in_content.append(col)
            
            if present_in_content:
                print(f"  Columns mentioned in KB text: {', '.join(present_in_content[:20])}{'...' if len(present_in_content) > 20 else ''}")
            if missing_in_content:
                print(f"  Columns NOT mentioned in KB text: {', '.join(missing_in_content[:20])}{'...' if len(missing_in_content) > 20 else ''}")
            else:
                print(f"  All columns mentioned in KB text")
            print()
        except Exception as e:
            print(f"{table}: ERROR - {e}\n")
    
    conn.close()

asyncio.run(main())
