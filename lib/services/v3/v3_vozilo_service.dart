import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/v3_vozilo.dart';
import '../../utils/v3_belgrade_time.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_vozilo_repository.dart';

/// Service for V3 vehicles (`v3_vozila`).
class V3VoziloService {
  V3VoziloService._();
  static final V3VoziloRepository _repo = V3VoziloRepository();
  static const Uuid _uuid = Uuid();

  static List<V3Vozilo> getAllVozila() {
    final cache = V3MasterRealtimeManager.instance.vozilaCache.values;
    return cache.map((r) => V3Vozilo.fromJson(r)).toList()..sort((a, b) => a.naziv.compareTo(b.naziv));
  }

  static Stream<List<V3Vozilo>> streamVozila() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_vozila'],
        build: () => getAllVozila(),
      );

  static V3Vozilo? getVoziloById(String id) {
    final data = V3MasterRealtimeManager.instance.vozilaCache[id];
    return data != null ? V3Vozilo.fromJson(data) : null;
  }

  static Future<void> addUpdateVozilo(V3Vozilo vozilo) async {
    try {
      final data = vozilo.toJson();
      if (vozilo.id.isEmpty) {
        data['id'] = _uuid.v4();
      }
      final row = await _repo.upsertReturning(data);
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozila', row);
    } catch (e) {
      debugPrint('[V3VoziloService] Error: $e');
      rethrow;
    }
  }

  /// Briše vozilo po id.
  static Future<void> deleteVozilo(String id) async {
    try {
      await _repo.deleteById(id);
      V3MasterRealtimeManager.instance.v3RemoveFromCache('v3_vozila', id);
    } catch (e) {
      debugPrint('[V3VoziloService] deleteVozilo error: $e');
      rethrow;
    }
  }

  /// Ažurira kolsku knjigu vozila (samo proslijeđena polja).
  static Future<void> updateKolskaKnjiga(String voziloId, Map<String, dynamic> data) async {
    try {
      final row = await _repo.updateByIdReturning(voziloId, data);
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_vozila', row);
    } catch (e) {
      debugPrint('[V3VoziloService] updateKolskaKnjiga error: $e');
      rethrow;
    }
  }

  /// Upisuje stavku u istoriju servisa (v3_servis_istorija).
  /// Ne baca grešku — istorija je pomoćna i ne sme da blokira čuvanje servisa.
  static Future<void> logServisIstorija({
    required String voziloId,
    required String tip,
    required DateTime? datum,
    required int? km,
  }) async {
    if (datum == null) return;
    try {
      await _repo.insertServisIstorija({
        'vozilo_id': voziloId,
        'tip': tip,
        'datum': V3BelgradeTime.toIsoDate(datum),
        if (km != null) 'km': km,
      });
    } catch (e) {
      debugPrint('[V3VoziloService] logServisIstorija error: $e');
    }
  }

  /// Ispravlja poslednji zabeleženi unos u istoriji servisa.
  /// Red sa starim datumom se ažurira; ako ne postoji (npr. podatak je stariji
  /// od istorije), upisuje se novi red da istorija prati stvarno stanje.
  /// Ne baca grešku — istorija je pomoćna i ne sme da blokira čuvanje servisa.
  static Future<void> ispraviServisIstorija({
    required String voziloId,
    required String tip,
    required DateTime? stariDatum,
    required DateTime? noviDatum,
    required int? km,
  }) async {
    if (stariDatum == null || noviDatum == null) return;
    try {
      final updated = await _repo.updateServisIstorija(
        voziloId,
        tip,
        V3BelgradeTime.toIsoDate(stariDatum),
        {'datum': V3BelgradeTime.toIsoDate(noviDatum), 'km': km},
      );
      if (!updated) {
        await _repo.insertServisIstorija({
          'vozilo_id': voziloId,
          'tip': tip,
          'datum': V3BelgradeTime.toIsoDate(noviDatum),
          if (km != null) 'km': km,
        });
      }
    } catch (e) {
      debugPrint('[V3VoziloService] ispraviServisIstorija error: $e');
    }
  }

  /// Računa prosečan interval servisa (u danima i km) iz v3_servis_istorija,
  /// plus proteklo vreme/km od poslednjeg servisa.
  static Future<V3ServisProsek?> getServisProsek(String voziloId, String tip, {double? trenutnaKm}) async {
    try {
      final rows = await _repo.fetchServisIstorija(voziloId, tip);
      final entries = <({DateTime datum, int? km})>[];
      for (final r in rows) {
        final d = V3BelgradeTime.parseDatum(r['datum']?.toString());
        if (d == null) continue;
        // UTC ponoć za kalendarski dan — tačan broj dana bez DST/tz pomaka.
        final du = DateTime.utc(d.year, d.month, d.day);
        final km = (r['km'] as num?)?.toInt();
        if (entries.isEmpty || entries.last.datum != du || entries.last.km != km) {
          entries.add((datum: du, km: km));
        }
      }
      if (entries.isEmpty) return null;

      final n = V3BelgradeTime.now();
      final last = entries.last;
      final danaOd = DateTime.utc(n.year, n.month, n.day).difference(last.datum).inDays;
      final kmOd =
          (trenutnaKm != null && last.km != null) ? (trenutnaKm - last.km!).round() : null;

      final dani = <int>[];
      final kilometri = <int>[];
      for (var i = 1; i < entries.length; i++) {
        final dd = entries[i].datum.difference(entries[i - 1].datum).inDays;
        if (dd <= 0) continue;
        dani.add(dd);
        final a = entries[i - 1].km;
        final b = entries[i].km;
        if (a != null && b != null && b > a) kilometri.add(b - a);
      }

      return V3ServisProsek(
        prosekDana: dani.isEmpty ? null : (dani.reduce((a, b) => a + b) / dani.length).round(),
        prosekKm: kilometri.isEmpty ? null : (kilometri.reduce((a, b) => a + b) / kilometri.length).round(),
        danaOdPoslednjeg: danaOd >= 0 ? danaOd : null,
        kmOdPoslednjeg: kmOd != null && kmOd >= 0 ? kmOd : null,
      );
    } catch (e) {
      debugPrint('[V3VoziloService] getServisProsek error: $e');
      return null;
    }
  }
}
