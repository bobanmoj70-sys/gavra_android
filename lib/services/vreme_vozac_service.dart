import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../utils/grad_adresa_validator.dart';
import '../utils/vozac_cache.dart';

/// 🚐 VREME VOZAC SERVICE
/// Servis za dodeljivanje vozača:
///   1. Ceo termin: grad + vreme + dan → vozac (putnik_id IS NULL)
///   2. Individualni putnik: putnik_id + dan → vozac (putnik_id IS NOT NULL)
class VremeVozacService {
  // Singleton pattern
  static final VremeVozacService _instance = VremeVozacService._internal();
  factory VremeVozacService() => _instance;
  VremeVozacService._internal();

  // Supabase client
  SupabaseClient get _supabase => supabase;

  // Cache za sync pristup - TERMIN dodele: 'grad|vreme|dan' -> vozac_ime
  final Map<String, String> _cache = {};

  // Cache za vozac_id (grad|vreme|dan -> uuid)
  final Map<String, String> _uuidCache = {};

  // Cache za INDIVIDUALNE dodele: 'putnikId|dan|grad|vreme' -> vozac_ime
  // Specijalna vrednost 'Nedodeljen' znači da je eksplicitno uklonjen sa svih vozača
  final Map<String, String> _putnikCache = {};

  // Stream controller za obaveštavanje o promenama
  final _changesController = StreamController<void>.broadcast();
  Stream<void> get onChanges => _changesController.stream;

  // Realtime subscription
  RealtimeChannel? _realtimeChannel;

  /// 🔍 Dobij vozača za specifično vreme
  /// [grad] - 'Bela Crkva' ili 'Vrsac'
  /// [vreme] - '18:00', '5:00', itd.
  /// [dan] - 'pon', 'uto', 'sre', 'cet', 'pet'
  /// Vraća ime vozača ili null ako nije dodeljen
  Future<String?> getVozacZaVreme(String grad, String vreme, String dan) async {
    final normalizedVreme = _normalizeTime(vreme);
    if (normalizedVreme == null) return null;

    try {
      final response = await _supabase
          .from('vreme_vozac')
          .select('vozac_ime, vozac_id')
          .eq('grad', grad)
          .eq('vreme', normalizedVreme)
          .eq('dan', dan)
          .maybeSingle();

      final vozacIme = response?['vozac_ime'] as String?;
      return vozacIme;
    } catch (e) {
      return null;
    }
  }

  /// ✏️ Dodeli vozača celom vremenu
  /// [grad] - 'Bela Crkva' ili 'Vrsac'
  /// [vreme] - '18:00', '5:00', itd.
  /// [dan] - 'pon', 'uto', 'sre', 'cet', 'pet'
  /// [vozacIme] - 'Voja', 'Bilevski', 'Goran'
  Future<void> setVozacZaVreme(String grad, String vreme, String dan, String vozacIme) async {
    // Normalize vreme to ensure consistent HH:MM format
    final normalizedVreme = _normalizeTime(vreme);
    if (normalizedVreme == null) {
      throw Exception('Nevalidan format vremena: "$vreme"');
    }

    // Validacija
    if (!VozacCache.isValidIme(vozacIme)) {
      final validDrivers = VozacCache.imenaVozaca;
      throw Exception('Nevalidan vozač: "$vozacIme". Dozvoljeni: ${validDrivers.join(", ")}');
    }

    final vozacId = VozacCache.getUuidByIme(vozacIme);

    try {
      // Update postojećeg reda, ili insert ako ne postoji
      // Koristimo upsert na primary key (id) putem select+update/insert
      final existing = await supabase
          .from('vreme_vozac')
          .select('id')
          .eq('grad', grad)
          .eq('vreme', normalizedVreme)
          .eq('dan', dan)
          .isFilter('putnik_id', null)
          .maybeSingle();

      if (existing != null) {
        await supabase.from('vreme_vozac').update({
          'vozac_ime': vozacIme,
          'vozac_id': vozacId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await supabase.from('vreme_vozac').insert({
          'grad': grad,
          'vreme': normalizedVreme,
          'dan': dan,
          'vozac_ime': vozacIme,
          'vozac_id': vozacId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      // Ažuriraj cache
      final key = '$grad|$normalizedVreme|$dan';
      _cache[key] = vozacIme;
      if (vozacId != null) _uuidCache[key] = vozacId;

      // Obavesti listenere
      _changesController.add(null);
    } catch (e) {
      throw Exception('Greška pri dodeljivanju vozača vremenu: $e');
    }
  }

  /// 🗑️ Ukloni vozača sa vremena
  Future<void> removeVozacZaVreme(String grad, String vreme, String dan) async {
    final normalizedVreme = _normalizeTime(vreme);
    if (normalizedVreme == null) {
      throw Exception('Nevalidan format vremena: "$vreme"');
    }

    try {
      await supabase.from('vreme_vozac').delete().eq('grad', grad).eq('vreme', normalizedVreme).eq('dan', dan);

      // Ažuriraj cache
      final key = '$grad|$normalizedVreme|$dan';
      _cache.remove(key);
      _uuidCache.remove(key);

      // Obavesti listenere
      _changesController.add(null);
    } catch (e) {
      throw Exception('Greška pri uklanjanju vozača sa vremena: $e');
    }
  }

  /// 🔍 Dobij vozača za specifično vreme (SYNC verzija)
  /// [grad] - 'Bela Crkva' ili 'Vrsac'
  /// [vreme] - '18:00', '5:00', itd.
  /// [dan] - 'pon', 'uto', 'sre', 'cet', 'pet'
  /// Vraća ime vozača ili null ako nije dodeljen
  String? getVozacZaVremeSync(String grad, String vreme, String dan) {
    final normalizedVreme = _normalizeTime(vreme);
    if (normalizedVreme == null) return null;

    final key = '$grad|$normalizedVreme|$dan';
    return _cache[key];
  }

  /// Dobij UUID vozača za specifično vreme (SYNC verzija)
  String? getVozacIdZaVremeSync(String grad, String vreme, String dan) {
    final normalizedVreme = _normalizeTime(vreme);
    if (normalizedVreme == null) return null;

    final key = '$grad|$normalizedVreme|$dan';
    return _uuidCache[key] ?? VozacCache.getUuidByIme(_cache[key]);
  }

  /// 🔍 Dobij vozače za ceo dan (SYNC verzija)
  /// [dan] - 'pon', 'uto', 'sre', 'cet', 'pet'
  /// Vraća mapu 'grad|vreme' -> vozac_ime
  Map<String, String> getVozaciZaDanSync(String dan) {
    final result = <String, String>{};
    _cache.forEach((key, vozac) {
      final parts = key.split('|');
      if (parts.length == 3 && parts[2] == dan) {
        final gradVreme = '${parts[0]}|${parts[1]}';
        result[gradVreme] = vozac;
      }
    });
    return result;
  }

  /// 🔄 Učitaj sve vreme-vozač mapiranja (SYNC verzija)
  Future<void> loadAllVremeVozac() async {
    try {
      // Učitaj termin dodele (putnik_id IS NULL)
      final response = await _supabase
          .from('vreme_vozac')
          .select('grad, vreme, dan, vozac_ime, vozac_id')
          .isFilter('putnik_id', null);
      _cache.clear();
      _uuidCache.clear();
      for (final row in response) {
        final gradRaw = row['grad'] as String;
        final grad = GradAdresaValidator.isVrsac(gradRaw) ? 'Vrsac' : 'Bela Crkva';
        final vreme = row['vreme'] as String;
        final dan = row['dan'] as String;
        final vozacIme = row['vozac_ime'] as String?;
        final vozacId = row['vozac_id'] as String?;
        final key = '$grad|$vreme|$dan';
        if (vozacIme != null) _cache[key] = vozacIme;
        if (vozacId != null) _uuidCache[key] = vozacId;
      }
      if (_realtimeChannel == null) {
        _setupRealtimeListener();
      }
    } catch (e) {
      // ignore
    }
  }

  // ─────────────────────────────────────────────────────────────
  // INDIVIDUALNE DODELE PO PUTNIKU
  // ─────────────────────────────────────────────────────────────

  /// 👤 Dodeli vozača konkretnom putniku za određeni dan
  /// [grad] i [vreme] čuvamo za referencu (isti termin)
  Future<void> dodelVozacaPutniku({
    required String putnikId,
    required String dan, // kratica: 'pon', 'uto', 'sre', 'cet', 'pet'
    required String grad,
    required String vreme,
    required String vozacIme, // 'Nedodeljen' = eksplicitno ukloni
    String? vozacId,
  }) async {
    final normalizedVreme = _normalizeTime(vreme) ?? vreme;
    // Uvek normalizuj grad u 'BC'/'VS' — konzistentno sa DB i loadPutnikDodele cache ključem
    final normalizedGrad = GradAdresaValidator.normalizeGrad(grad);
    final normalizedDan = dan.toLowerCase();
    final vozacIdFinal = vozacIme == 'Nedodeljen' ? null : (vozacId ?? VozacCache.getUuidByIme(vozacIme));

    try {
      final existing = await _supabase
          .from('vreme_vozac')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('dan', normalizedDan)
          .eq('grad', normalizedGrad)
          .eq('vreme', normalizedVreme)
          .maybeSingle();

      if (existing != null) {
        await _supabase.from('vreme_vozac').update({
          'vozac_ime': vozacIme,
          'vozac_id': vozacIdFinal,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await _supabase.from('vreme_vozac').insert({
          'putnik_id': putnikId,
          'dan': normalizedDan,
          'grad': normalizedGrad,
          'vreme': normalizedVreme,
          'vozac_ime': vozacIme,
          'vozac_id': vozacIdFinal,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      // Ažuriraj cache odmah — ključ uključuje grad i vreme da bi BC i VS bili odvojeni
      final key = '$putnikId|$normalizedDan|$normalizedGrad|$normalizedVreme';
      _putnikCache[key] = vozacIme;

      _changesController.add(null);
    } catch (e) {
      throw Exception('Greška pri individualnoj dodeli vozača: $e');
    }
  }

  /// 👤 Ukloni individualnu dodelu vozača za putnika (briše red iz tabele)
  Future<void> ukloniDodelaPutnika({
    required String putnikId,
    required String dan,
    String? grad,
    String? vreme,
  }) async {
    final normalizedGrad = grad != null ? GradAdresaValidator.normalizeGrad(grad) : null;
    final normalizedDan = dan.toLowerCase();
    try {
      var query = _supabase.from('vreme_vozac').delete().eq('putnik_id', putnikId).eq('dan', normalizedDan);
      if (normalizedGrad != null) query = query.eq('grad', normalizedGrad);
      if (vreme != null) {
        final normalizedVreme = _normalizeTime(vreme) ?? vreme;
        query = query.eq('vreme', normalizedVreme);
      }
      await query;

      // Ukloni iz cache-a — ako je dat grad/vreme, ukloni tačan ključ, inače sve za taj dan
      if (normalizedGrad != null && vreme != null) {
        final normalizedVreme = _normalizeTime(vreme) ?? vreme;
        _putnikCache.remove('$putnikId|$normalizedDan|$normalizedGrad|$normalizedVreme');
      } else {
        _putnikCache.removeWhere((key, _) => key.startsWith('$putnikId|$normalizedDan'));
      }

      _changesController.add(null);
    } catch (e) {
      throw Exception('Greška pri uklanjanju individualne dodele: $e');
    }
  }

  /// 👤 Dobij dodeljenog vozača za konkretnog putnika (SYNC iz cache-a)
  /// [grad] i [vreme] su obavezni da bi se razlikovale dodele za BC 7:00 vs VS 10:00
  /// Vraća ime vozača, 'Nedodeljen' ili null (nema unosa)
  String? getVozacZaPutnikSync(String putnikId, String dan, {String? grad, String? vreme}) {
    final normalizedDan = dan.toLowerCase();
    if (grad != null && vreme != null) {
      final normalizedVreme = _normalizeTime(vreme) ?? vreme;
      final normalizedGrad = GradAdresaValidator.normalizeGrad(grad);
      final key = '$putnikId|$normalizedDan|$normalizedGrad|$normalizedVreme';
      return _putnikCache[key];
    }
    // Fallback: pretrazi cache po putnikId|dan
    return _putnikCache['$putnikId|$normalizedDan'];
  }

  /// 🔄 Učitaj individualne dodele za određeni datum u cache
  Future<void> loadPutnikDodele(String datum) async {
    try {
      final response = await _supabase
          .from('vreme_vozac')
          .select('putnik_id, vozac_ime, grad, vreme')
          .eq('datum', datum)
          .not('putnik_id', 'is', null);

      // Ukloni stare unose za taj datum iz cache-a (svi ključi koji sadrže |datum|)
      _putnikCache.removeWhere((key, _) => key.contains('|$datum|') || key.endsWith('|$datum'));

      for (final row in response) {
        final pId = row['putnik_id']?.toString();
        final ime = row['vozac_ime']?.toString() ?? '';
        final grad = row['grad']?.toString() ?? '';
        final vremeRaw = row['vreme']?.toString() ?? '';
        final vreme = _normalizeTime(vremeRaw) ?? vremeRaw;
        if (pId != null && ime.isNotEmpty && grad.isNotEmpty && vreme.isNotEmpty) {
          _putnikCache['$pId|$datum|$grad|$vreme'] = ime;
        }
      }
    } catch (e) {
      // ignore
    }
  }

  /// 📡 Postavi realtime listener na vreme_vozac tabelu
  void _setupRealtimeListener() {
    _realtimeChannel = _supabase.channel('public:vreme_vozac');

    _realtimeChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vreme_vozac',
          callback: (payload) async {
            // Refresh cache kada se bilo šta promijeni u tabeli
            print('📡 VremeVozacService: Detektovana promjena, osvežavam cache...');
            // NE pozivaj loadAllVremeVozac() jer bi to pokrenulo listener ponovo
            await refreshCacheFromDatabase();
            // Obavesti slušaoce o promjeni
            _changesController.add(null);
          },
        )
        .subscribe();
  }

  /// 🔄 Osvěži cache iz baze bez pokretanja novog listener-a
  Future<void> refreshCacheFromDatabase() async {
    try {
      // Termin dodele
      final response = await _supabase
          .from('vreme_vozac')
          .select('grad, vreme, dan, vozac_ime, vozac_id')
          .isFilter('putnik_id', null);
      _cache.clear();
      _uuidCache.clear();
      for (final row in response) {
        final gradRaw = row['grad'] as String;
        final grad = GradAdresaValidator.isVrsac(gradRaw) ? 'Vrsac' : 'Bela Crkva';
        final vreme = row['vreme'] as String;
        final dan = row['dan'] as String;
        final vozacIme = row['vozac_ime'] as String?;
        final vozacId = row['vozac_id'] as String?;
        final key = '$grad|$vreme|$dan';
        if (vozacIme != null) _cache[key] = vozacIme;
        if (vozacId != null) _uuidCache[key] = vozacId;
      }

      // Individualne dodele - osvezi za danas, sutra i sva radna dana
      final now = DateTime.now();
      final todayWd = now.weekday; // 1=Mon...7=Sun
      // Radni dani koji su danas, sutra, ili naredni ponedeljak (vikendom)
      final dansToLoad = <String>{};
      for (int i = 0; i < 2; i++) {
        final d = now.add(Duration(days: i));
        if (d.weekday <= 5) {
          // pon-pet
          const abbrs = ['pon', 'uto', 'sre', 'cet', 'pet'];
          dansToLoad.add(abbrs[d.weekday - 1]);
        }
      }
      // Vikendom: dodaj naredni ponedeljak
      if (todayWd >= 6) dansToLoad.add('pon');
      await Future.wait(dansToLoad.map((d) => loadPutnikDodele(d)));
    } catch (e) {
      // ignore
    }
  }

  /// 🛑 Zatvori realtime listener
  void dispose() {
    if (_realtimeChannel != null) {
      _supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
    _changesController.close();
  }

  /// 🕒 Helper: Normalize time to HH:MM format
  String? _normalizeTime(String time) {
    // Simple normalization: ensure HH:MM format
    final parts = time.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
    }
    return null;
  }
}
