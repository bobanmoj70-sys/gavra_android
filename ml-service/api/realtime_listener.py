"""
Real-time Supabase Listener za AI Learning
Prati promene u bazi i triggeruje retraining
"""
import asyncio
from supabase import create_client
import config
from datetime import datetime

supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)

class RealtimeListener:
    def __init__(self):
        self.changes_buffer = {}
        self.last_retrain = None

    async def listen_to_changes(self):
        """Prati promene u svim tabelama"""
        tables = ['v3_finansije', 'v3_zahtevi', 'v3_operativna_nedelja', 'v3_vozila', 'v3_gorivo']
        
        for table in tables:
            # Real-time subscription
            supabase.table(table).on('INSERT', self._handle_insert).subscribe()
            supabase.table(table).on('UPDATE', self._handle_update).subscribe()
            supabase.table(table).on('DELETE', self._handle_delete).subscribe()

    def _handle_insert(self, payload):
        """Novi podaci - buffer za retraining"""
        table = payload['table']
        self.changes_buffer[table] = self.changes_buffer.get(table, 0) + 1
        print(f"[Realtime] INSERT in {table}: {payload['record']}")
        
        # Trigger retraining ako ima dovoljno promena
        if self._should_retrain():
            self._trigger_retraining()

    def _handle_update(self, payload):
        """Update podaci - buffer za retraining"""
        table = payload['table']
        self.changes_buffer[table] = self.changes_buffer.get(table, 0) + 1
        print(f"[Realtime] UPDATE in {table}: {payload['record']}")
        
        if self._should_retrain():
            self._trigger_retraining()

    def _handle_delete(self, payload):
        """Delete podaci - buffer za retraining"""
        table = payload['table']
        self.changes_buffer[table] = self.changes_buffer.get(table, 0) + 1
        print(f"[Realtime] DELETE in {table}: {payload['old_record']}")
        
        if self._should_retrain():
            self._trigger_retraining()

    def _should_retrain(self) -> bool:
        """Da li treba da trenira model"""
        total_changes = sum(self.changes_buffer.values())
        
        # Retraining ako je > 10 promena ili je prošlo > 1 sat od poslednjeg
        if total_changes > 10:
            return True
        
        if self.last_retrain:
            hours_since = (datetime.now() - self.last_retrain).total_seconds() / 3600
            if hours_since > 1 and total_changes > 0:
                return True
        
        return False

    def _trigger_retraining(self):
        """Triggeruje retraining svih modela"""
        print(f"[Realtime] Triggering retraining with {self.changes_buffer}")
        
        # Ovde bi pozvao retraining funkcije
        # from api.main import retrain_all_models
        # retrain_all_models()
        
        self.changes_buffer = {}
        self.last_retrain = datetime.now()

if __name__ == "__main__":
    listener = RealtimeListener()
    asyncio.run(listener.listen_to_changes())
