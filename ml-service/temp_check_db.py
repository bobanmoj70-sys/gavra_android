import sqlite3, os
DB = r"C:\Users\Bojan\gavra_android\ml-service\gavra_ai.db"
conn = sqlite3.connect(DB)
c = conn.cursor()
print("=== TABELE ===")
c.execute("SELECT name FROM sqlite_master WHERE type='table'")
for row in c.fetchall(): print(row[0])
print("\n=== BROJ REDOVA PO TABELAMA ===")
for tbl in ['ai_knowledge_base','vec_knowledge_base','ai_insights','sync_status']:
    try:
        c.execute(f"SELECT COUNT(*) FROM {tbl}")
        print(f"{tbl}: {c.fetchone()[0]}")
    except Exception as e:
        print(f"{tbl}: greska {e}")
print("\n=== SADRZAJ sync_status ===")
c.execute("SELECT * FROM sync_status")
for row in c.fetchall(): print(row)
print("\n=== REDOVA PO IZVORNOJ TABELI ===")
c.execute("SELECT source_table, COUNT(*) FROM ai_knowledge_base GROUP BY source_table ORDER BY COUNT(*) DESC")
for row in c.fetchall(): print(f"{row[0]}: {row[1]}")
print("\n=== VELICINA BAZE ===")
print(f"{os.path.getsize(DB) / 1024 / 1024:.2f} MB")
conn.close()
