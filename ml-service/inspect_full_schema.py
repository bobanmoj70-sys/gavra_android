import os
import asyncio
from dotenv import load_dotenv
from supabase._async.client import create_client

load_dotenv()
url = os.environ.get('SUPABASE_URL')
key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')

async def main():
    supabase = await create_client(url, key)
    
    # Get all tables from information_schema via RPC if available, else use known list
    tables = [
        'v3_adrese', 'v3_auth', 'v3_vozila', 'v3_zahtevi',
        'v3_gorivo', 'v3_finansije', 'v3_racuni',
        'v3_trenutna_dodela', 'v3_trenutna_dodela_slot',
        'v3_operativna_nedelja', 'v3_kapacitet_slots', 'v3_app_settings'
    ]
    
    print('=== AI TABLES_TO_SYNC coverage ===\n')
    for table in tables:
        try:
            resp = await supabase.table(table).select('*').limit(1).execute()
            if resp.data:
                columns = list(resp.data[0].keys())
                print(f'{table}: {len(columns)} columns')
                for col in columns:
                    print(f'  - {col}')
            else:
                print(f'{table}: EMPTY TABLE')
        except Exception as e:
            print(f'{table}: ERROR - {e}')
        print()

asyncio.run(main())
