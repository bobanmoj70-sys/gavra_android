import '../../../globals.dart';

class V3KapacitetSlotsRepository {
  Future<Map<String, dynamic>?> getSlotByGradDatumVreme({
    required String grad,
    required String datum,
    required String vreme,
  }) {
    return supabase
        .from('v3_kapacitet_slots')
        .select('max_mesta')
        .eq('grad', grad)
        .eq('datum', datum)
        .eq('vreme', vreme)
        .maybeSingle();
  }

  Future<Map<String, dynamic>> upsertSlot({
    required String grad,
    required String vreme,
    required String datumIso,
    required int maxMesta,
    String? id,
  }) {
    return supabase
        .from('v3_kapacitet_slots')
        .upsert(
          {
            if (id != null && id.isNotEmpty) 'id': id,
            'grad': grad,
            'vreme': vreme,
            'datum': datumIso,
            'max_mesta': maxMesta,
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'grad,vreme,datum',
        )
        .select()
        .single();
  }
}
