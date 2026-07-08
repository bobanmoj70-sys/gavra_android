import os
import sys
import sqlite3
import pytest
import numpy as np

# Dodajemo trenutni direktorijum u path da bismo mogli importovati main
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import main


class TestParseRowToText:
    def test_finansije_prihod(self):
        row = {
            "tip": "prihod",
            "naziv": "Test prihod",
            "iznos": 15000,
            "kategorija": "Prevoz",
            "isplata_iz": "pazar",
            "mesec": 7,
            "godina": 2026,
        }
        text = main.parse_row_to_text("v3_finansije", row)
        assert "PRIHOD" in text
        assert "15000" in text
        assert "Test prihod" in text

    def test_gorivo(self):
        row = {
            "vozilo_id": "voz-1",
            "iznos": 8000,
            "litara": 50,
            "km_sat": 12345,
            "kartica": True,
            "kreirano_by": "pera",
        }
        text = main.parse_row_to_text("v3_gorivo", row)
        assert "voz-1" in text
        assert "8000" in text
        assert "50" in text
        assert "12345" in text

    def test_zahtevi(self):
        row = {
            "created_by": "putnik-1",
            "grad": "Beograd",
            "datum": "2026-07-08",
            "trazeni_polazak_at": "08:00",
            "status": "odobren",
            "polazak_at": "08:15",
        }
        text = main.parse_row_to_text("v3_zahtevi", row)
        assert "putnik-1" in text
        assert "Beograd" in text
        assert "ODOBREN" in text


class TestExtractMetadata:
    def test_finansije_metadata(self):
        row = {"tip": "prihod", "iznos": 15000, "kategorija": "Prevoz", "mesec": 7, "godina": 2026}
        meta = main._extract_metadata("v3_finansije", row)
        assert meta["tip"] == "prihod"
        assert meta["iznos"] == 15000.0
        assert meta["kategorija"] == "Prevoz"

    def test_gorivo_metadata(self):
        row = {"vozilo_id": "voz-1", "iznos": 8000, "litara": 50, "km_sat": 12345}
        meta = main._extract_metadata("v3_gorivo", row)
        assert meta["vozilo_id"] == "voz-1"
        assert meta["iznos"] == 8000.0
        assert meta["litara"] == 50.0

    def test_empty_row(self):
        meta = main._extract_metadata("v3_finansije", {})
        assert meta == {}


class TestSearchKnowledgeBase:
    @pytest.fixture(autouse=True)
    def setup_test_db(self, tmp_path):
        self.test_db = str(tmp_path / "test_ai.db")
        main.DB_FILE = self.test_db
        main.init_local_db()

        # Lažni embedder koji daje determinističke vektore
        class FakeEmbedder:
            def encode(self, text):
                import hashlib
                h = hashlib.md5(text.encode()).hexdigest()
                vec = []
                for i in range(main.VECTOR_DIMENSION):
                    idx = (i * 2) % 32
                    vec.append(int(h[idx:idx+2], 16) / 255.0)
                return np.array(vec, dtype=np.float32)

        main.embedder = FakeEmbedder()

        conn = sqlite3.connect(self.test_db)
        conn.enable_load_extension(True)
        import sqlite_vec
        sqlite_vec.load(conn)
        c = conn.cursor()

        content1 = "Finansije (PRIHOD): Transakcija X iznosi 15000 RSD."
        content2 = "Sipanje goriva: U vozilo ID 1 je sipano 50 litara goriva u vrednosti od 8000 RSD."
        emb1 = main.embedder.encode(content1).tolist()
        emb2 = main.embedder.encode(content2).tolist()

        main._upsert_vector(conn, "v3_finansije:1", emb1)
        main._upsert_vector(conn, "v3_gorivo:1", emb2)

        c.execute(
            "INSERT INTO ai_knowledge_base VALUES (?, ?, ?, ?, ?, ?, ?)",
            ("v3_finansije:1", "v3_finansije", "1", content1, "", "{}", ""),
        )
        c.execute(
            "INSERT INTO ai_knowledge_base VALUES (?, ?, ?, ?, ?, ?, ?)",
            ("v3_gorivo:1", "v3_gorivo", "1", content2, "", "{}", ""),
        )
        conn.commit()
        conn.close()

    def test_text_search_finds_gorivo(self):
        result = main._search_knowledge_base_sync("koliko je goriva")
        assert len(result) > 0
        assert any("goriva" in r[0].lower() for r in result)

    def test_text_search_finds_finansije(self):
        result = main._search_knowledge_base_sync("finansije prihod")
        assert len(result) > 0
        assert any("15000" in r[0] for r in result)

    def test_no_results_for_irrelevant_query(self):
        result = main._search_knowledge_base_sync("nebeska mehanika kvantna fizika")
        assert len(result) == 0


class TestSanitizeLogLine:
    def test_mask_email(self):
        line = "Korisnik test@example.com je uneo podatke."
        sanitized = main._sanitize_log_line(line)
        assert "test@example.com" not in sanitized
        assert "***MASKED_EMAIL***" in sanitized

    def test_mask_card(self):
        line = "Plaćeno karticom 1234567890123456."
        sanitized = main._sanitize_log_line(line)
        assert "1234567890123456" not in sanitized
        assert "***MASKED_CARD***" in sanitized

    def test_no_change_for_normal_log(self):
        line = "Sinhronizovano 15 slogova iz tabele v3_gorivo."
        sanitized = main._sanitize_log_line(line)
        assert sanitized == line


class TestChatCache:
    def test_cache_store_and_retrieve(self):
        cache = main._LRUChatCache(maxsize=10)
        cache.set("koliko je goriva", "hash123", "Gorivo iznosi 8000 RSD.")
        assert cache.get("koliko je goriva", "hash123") == "Gorivo iznosi 8000 RSD."

    def test_cache_normalization(self):
        cache = main._LRUChatCache(maxsize=10)
        cache.set("  Koliko   je GORIVA  ", "hash123", "Gorivo iznosi 8000 RSD.")
        # Različito whitespace i velika/mala slova bi trebalo da daju isti ključ
        assert cache.get("koliko je goriva", "hash123") == "Gorivo iznosi 8000 RSD."

    def test_cache_lru_eviction(self):
        cache = main._LRUChatCache(maxsize=2)
        cache.set("pitanje 1", "h", "odgovor 1")
        cache.set("pitanje 2", "h", "odgovor 2")
        cache.set("pitanje 3", "h", "odgovor 3")
        assert cache.get("pitanje 1", "h") is None
        assert cache.get("pitanje 2", "h") == "odgovor 2"
        assert cache.get("pitanje 3", "h") == "odgovor 3"

    def test_cache_disabled(self):
        cache = main._LRUChatCache(maxsize=0)
        cache.set("pitanje", "h", "odgovor")
        assert cache.get("pitanje", "h") is None


class TestHashContext:
    def test_hash_deterministic(self):
        h1 = main._hash_context("context", "conversation")
        h2 = main._hash_context("context", "conversation")
        assert h1 == h2

    def test_hash_different_inputs(self):
        h1 = main._hash_context("context1", "conversation")
        h2 = main._hash_context("context2", "conversation")
        assert h1 != h2
