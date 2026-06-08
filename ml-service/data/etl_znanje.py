"""
ETL Pipeline - Extract ALL data for AI Knowledge Base
Agregira podatke iz svih tabela za AI asistenta
"""
import pandas as pd
from supabase import create_client
import config

supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)


def extract_all_tables() -> dict:
    """Extract key data from all tables for AI context"""
    data = {}

    # Auth / Users
    try:
        r = supabase.table("v3_auth").select("id, ime, created_at").limit(100).execute()
        data['users'] = pd.DataFrame(r.data)
        print(f"[Znanje] Users: {len(data['users'])}")
    except Exception as e:
        print(f"[Znanje] Users error: {e}")
        data['users'] = pd.DataFrame()

    # Zahtevi
    try:
        r = supabase.table("v3_zahtevi").select("*").order("created_at", desc=True).limit(200).execute()
        data['zahtevi'] = pd.DataFrame(r.data)
        print(f"[Znanje] Zahtevi: {len(data['zahtevi'])}")
    except Exception as e:
        print(f"[Znanje] Zahtevi error: {e}")
        data['zahtevi'] = pd.DataFrame()

    # Operativna nedelja
    try:
        r = supabase.table("v3_operativna_nedelja").select("*").order("datum", desc=True).limit(200).execute()
        data['operativna'] = pd.DataFrame(r.data)
        print(f"[Znanje] Operativna: {len(data['operativna'])}")
    except Exception as e:
        print(f"[Znanje] Operativna error: {e}")
        data['operativna'] = pd.DataFrame()

    # Finansije
    try:
        r = supabase.table("v3_finansije").select("*").order("created_at", desc=True).limit(200).execute()
        data['finansije'] = pd.DataFrame(r.data)
        print(f"[Znanje] Finansije: {len(data['finansije'])}")
    except Exception as e:
        print(f"[Znanje] Finansije error: {e}")
        data['finansije'] = pd.DataFrame()

    # Vozila
    try:
        r = supabase.table("v3_vozila").select("*").execute()
        data['vozila'] = pd.DataFrame(r.data)
        print(f"[Znanje] Vozila: {len(data['vozila'])}")
    except Exception as e:
        print(f"[Znanje] Vozila error: {e}")
        data['vozila'] = pd.DataFrame()

    # Gorivo
    try:
        r = supabase.table("v3_gorivo").select("*").execute()
        data['gorivo'] = pd.DataFrame(r.data)
        print(f"[Znanje] Gorivo: {len(data['gorivo'])}")
    except Exception as e:
        print(f"[Znanje] Gorivo error: {e}")
        data['gorivo'] = pd.DataFrame()

    # AI Znanje (FAQ articles)
    try:
        r = supabase.table("ai_znanje").select("*").execute()
        data['ai_znanje'] = pd.DataFrame(r.data)
        print(f"[Znanje] AI Znanje: {len(data['ai_znanje'])}")
    except Exception as e:
        print(f"[Znanje] AI Znanje error: {e}")
        data['ai_znanje'] = pd.DataFrame()

    return data


def get_database_schema() -> dict:
    """Get table schema for AI understanding"""
    schema = {
        'v3_auth': ['id', 'ime', 'prezime', 'email', 'role', 'created_at'],
        'v3_zahtevi': ['id', 'status', 'grad', 'datum', 'polazak_at', 'trazeni_polazak_at', 'created_by', 'created_at'],
        'v3_operativna_nedelja': ['id', 'datum', 'grad', 'polazak_at', 'status', 'created_by', 'otkazano_at', 'pokupljen_at'],
        'v3_finansije': ['id', 'putnik_v3_auth_id', 'iznos', 'tip', 'kategorija', 'created_at'],
        'v3_vozila': ['id', 'marka', 'model', 'registracija', 'trenutna_km', 'godina_proizvodnje'],
        'v3_gorivo': ['id', 'vozilo_id', 'trenutno_stanje_litri', 'kapacitet_litri', 'cena_po_litru'],
        'v3_trenutna_dodela': ['id', 'termin_id', 'putnik_v3_auth_id', 'vozac_v3_auth_id', 'status'],
        'v3_trenutna_dodela_slot': ['id', 'datum', 'grad', 'vreme', 'vozac_v3_auth_id', 'status']
    }
    return schema
