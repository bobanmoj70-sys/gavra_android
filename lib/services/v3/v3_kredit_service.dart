import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/v3_kredit.dart';
import '../../models/v3_kredit_uplata.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_kredit_repository.dart';

class V3KreditService {
  V3KreditService._();

  static final V3KreditRepository _repo = V3KreditRepository();
  static const Uuid _uuid = Uuid();

  /// Vraca sve kredite iz cache-a, sortirane po nazivu.
  static List<V3Kredit> getKrediti() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_krediti').values;
    final result = cache.map((row) => V3Kredit.fromJson(row)).toList();
    result.sort((a, b) => a.naziv.toLowerCase().compareTo(b.naziv.toLowerCase()));
    return result;
  }

  /// Ukupan preostali iznos svih kredita.
  static double getUkupnoPreostalo() {
    return getKrediti().fold(0.0, (sum, k) => sum + (k.preostalo > 0 ? k.preostalo : 0));
  }

  /// Stream koji se okida pri promeni v3_krediti ili bilo koje druge tabele
  /// ako je potrebno. Trenutno prati samo v3_krediti.
  static Stream<List<V3Kredit>> streamKrediti() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: const ['v3_krediti'],
        build: () => getKrediti(),
      );

  /// Dodaje novi kredit.
  static Future<V3Kredit> dodaj({
    required String naziv,
    required double ukupanIznos,
    String? napomena,
    DateTime? krajKredita,
  }) async {
    final safeNaziv = naziv.trim();
    if (safeNaziv.isEmpty) {
      throw ArgumentError('Naziv kredita je obavezan.');
    }
    if (ukupanIznos < 0) {
      throw ArgumentError('Ukupan iznos ne može biti negativan.');
    }

    final row = await _repo.insertReturning({
      'naziv': safeNaziv,
      'ukupan_iznos': ukupanIznos,
      'uplaceno': 0.0,
      'uplate_json': <Map<String, dynamic>>[],
      if (napomena != null && napomena.trim().isNotEmpty) 'napomena': napomena.trim(),
      if (krajKredita != null) 'kraj_kredita': krajKredita.toIso8601String().substring(0, 10),
    });

    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_krediti', row);
    return V3Kredit.fromJson(row);
  }

  /// Azurira osnovne podatke kredita.
  static Future<V3Kredit> izmeni({
    required String id,
    required String naziv,
    required double ukupanIznos,
    String? napomena,
    DateTime? krajKredita,
  }) async {
    final safeId = id.trim();
    if (safeId.isEmpty) throw ArgumentError('ID kredita je obavezan.');

    final safeNaziv = naziv.trim();
    if (safeNaziv.isEmpty) throw ArgumentError('Naziv kredita je obavezan.');
    if (ukupanIznos < 0) throw ArgumentError('Ukupan iznos ne može biti negativan.');

    final row = await _repo.updateByIdReturning(safeId, {
      'naziv': safeNaziv,
      'ukupan_iznos': ukupanIznos,
      if (napomena != null && napomena.trim().isNotEmpty) 'napomena': napomena.trim(),
      if (krajKredita != null) 'kraj_kredita': krajKredita.toIso8601String().substring(0, 10) else 'kraj_kredita': null,
      'updated_at': DateTime.now().toIso8601String(),
    });

    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_krediti', row);
    return V3Kredit.fromJson(row);
  }

  /// Uplacuje iznos na kredit i smanjuje preostali dug.
  static Future<V3Kredit> uplati({
    required String id,
    required double iznos,
    String? napomena,
  }) async {
    if (iznos <= 0) throw ArgumentError('Iznos uplate mora biti veći od nule.');

    final kredit = getKrediti().firstWhere(
      (k) => k.id == id,
      orElse: () => throw StateError('Kredit sa ID $id nije pronađen.'),
    );

    final novaUplata = V3KreditUplata(
      uplataId: 'kupl:${_uuid.v4()}',
      datum: DateTime.now(),
      iznos: iznos,
      napomena: napomena?.trim().isEmpty ?? true ? null : napomena!.trim(),
    );

    final updatedUplate = List<V3KreditUplata>.from(kredit.uplate)..add(novaUplata);

    final row = await _repo.updateByIdReturning(id, {
      'uplaceno': kredit.uplaceno + iznos,
      'uplate_json': updatedUplate.map((u) => u.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_krediti', row);
    return V3Kredit.fromJson(row);
  }

  /// Brise kredit.
  static Future<void> obrisi(String id) async {
    final safeId = id.trim();
    if (safeId.isEmpty) throw ArgumentError('ID kredita je obavezan.');

    await _repo.deleteById(safeId);
    V3MasterRealtimeManager.instance.v3RemoveFromCache('v3_krediti', safeId);
  }

  /// Rucno osvezi cache iz baze. Koristi se pri prvom otvaranju ekrana
  /// ako realtime jos nije inicijalizovan za ovu tabelu.
  static Future<void> refreshFromDb() async {
    try {
      final rows = await _repo.list();
      for (final row in rows) {
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_krediti', row);
      }
    } catch (e) {
      debugPrint('[V3KreditService] refreshFromDb error: $e');
      rethrow;
    }
  }

  /// Brise pojedinacnu uplatu iz istorije kredita.
  static Future<V3Kredit> obrisiUplatu({
    required String kreditId,
    required String uplataId,
  }) async {
    final kredit = getKrediti().firstWhere(
      (k) => k.id == kreditId,
      orElse: () => throw StateError('Kredit sa ID $kreditId nije pronađen.'),
    );

    final uplata = kredit.uplate.firstWhere(
      (u) => u.uplataId == uplataId,
      orElse: () => throw StateError('Uplata sa ID $uplataId nije pronađena.'),
    );

    final updatedUplate = kredit.uplate.where((u) => u.uplataId != uplataId).toList();
    final novoUplaceno = kredit.uplaceno - uplata.iznos;

    final row = await _repo.updateByIdReturning(kreditId, {
      'uplaceno': novoUplaceno < 0 ? 0.0 : novoUplaceno,
      'uplate_json': updatedUplate.map((u) => u.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_krediti', row);
    return V3Kredit.fromJson(row);
  }
}
