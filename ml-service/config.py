import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://gjtabtwudbrmfeyjiicu.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASEKEY", os.getenv("SUPABASE_KEY", ""))

API_HOST = os.getenv("API_HOST", "0.0.0.0")
API_PORT = int(os.getenv("PORT", os.getenv("API_PORT", "8000")))

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
MODEL_DIR = "models/saved"
