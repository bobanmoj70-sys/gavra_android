import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/registrovani_putnik.dart';
import '../utils/vozac_cache.dart';
import 'realtime/realtime_manager.dart';
import 'voznje_log_service.dart'; // 🔄 DODATO za istoriju vožnji

/// Servis za upravljanje mesečnim putnicima (normalizovana šema)
class RegistrovaniPutnikService {
  RegistrovaniPutnikService({SupabaseClient? supabaseClient}) : _supabaseOverride = supabaseClient;
  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? supabase;

  // 🔧 SINGLETON PATTERN za realtime stream - koristi RealtimeManager
  static StreamController<List<RegistrovaniPutnik>>? _sharedController;
  static StreamSubscription? _sharedSubscription;
  static RealtimeChannel? _realtimeChannel;
  static List<RegistrovaniPutnik>? _lastValue;

  // 🔧 SINGLETON PATTERN za "SVI PUTNICI" stream (uključujući neaktivne)
  static StreamController<List<RegistrovaniPutnik>>? _sharedSviController;
  static StreamSubscription? _sharedSviSubscription;
  static List<RegistrovaniPutnik>? _lastSviValue;

  /// Dohvata sve mesečne putnike
  Future<List<RegistrovaniPutnik>> getAllRegistrovaniPutnici() async {
    final response = await _supabase.from('registrovani_putnici').select('''
          *
        ''').eq('obrisan', false).eq('is_duplicate', false).order('putnik_ime');

    return response.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
  }

  /// Dohvata putnike kojima treba račun (treba_racun = true)
  Future<List<RegistrovaniPutnik>> getPutniciZaRacun() async {
    final response = await _supabase
        .from('registrovani_putnici')
        .select('*')
        .neq('status', 'neaktivan')
        .eq('obrisan', false)
        .eq('treba_racun', true)
        .eq('is_duplicate', false)
        .order('putnik_ime');

    return response.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
  }

  /// Dohvata mesečnog putnika po ID-u
  Future<RegistrovaniPutnik?> getRegistrovaniPutnikById(String id) async {
    final response = await _supabase.from('registrovani_putnici').select('''
          *
        ''').eq('id', id).single();

    return RegistrovaniPutnik.fromMap(response);
  }

  /// Dohvata mesečnog putnika po imenu (legacy compatibility)
  static Future<RegistrovaniPutnik?> getRegistrovaniPutnikByIme(String ime) async {
    try {
      final response = await supabase
          .from('registrovani_putnici')
          .select()
          .eq('putnik_ime', ime)
          .eq('obrisan', false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return RegistrovaniPutnik.fromMap(response);
    } catch (e) {
      return null;
    }
  }

  /// 🔧 SINGLETON STREAM za mesečne putnike - koristi RealtimeManager
  /// Svi pozivi dele isti controller
  static Stream<List<RegistrovaniPutnik>> streamAktivniRegistrovaniPutnici() {
    // Ako već postoji aktivan controller, koristi ga
    if (_sharedController != null && !_sharedController!.isClosed) {
      // NE POVEĆAVAJ listener count - broadcast stream deli istu pretplatu

      // Emituj poslednju vrednost novom listener-u
      if (_lastValue != null) {
        Future.microtask(() {
          if (_sharedController != null && !_sharedController!.isClosed) {
            _sharedController!.add(_lastValue!);
          }
        });
      }

      return _sharedController!.stream;
    }

    // Kreiraj novi shared controller
    _sharedController = StreamController<List<RegistrovaniPutnik>>.broadcast();

    // Učitaj inicijalne podatke
    _fetchAndEmit(supabase);

    // Kreiraj subscription preko RealtimeManager
    _setupRealtimeSubscription(supabase);

    return _sharedController!.stream;
  }

  /// 🔄 Fetch podatke i emituj u stream
  static Future<void> _fetchAndEmit(SupabaseClient supabase) async {
    try {
      debugPrint('📊 [RegistrovaniPutnik] Osvežavanje liste putnika iz baze...');

      // 🔧 QUERY BEZ FOREIGN KEY LOOKUP - privremeno rešenje dok se ne doda FK u bazu
      final data = await supabase.from('registrovani_putnici').select(
            '*', // Bez join-a sa adresama - fetch-ovaćemo ih posebno ako treba
          );

      // Filtriraj lokalno umesto preko Supabase
      final putnici = data
          .where((json) {
            final status = json['status'] as String? ?? 'aktivan';
            final obrisan = json['obrisan'] as bool? ?? false; // 🛡️ FIX: Default je false (nije obrisan)
            final isDuplicate = json['is_duplicate'] as bool? ?? false;
            return status != 'neaktivan' && !obrisan && !isDuplicate;
          })
          .map((json) => RegistrovaniPutnik.fromMap(json))
          .toList()
        ..sort((a, b) => a.putnikIme.compareTo(b.putnikIme));

      debugPrint('✅ [RegistrovaniPutnik] Učitano ${putnici.length} putnika (nakon filtriranja)');

      _lastValue = putnici;

      if (_sharedController != null && !_sharedController!.isClosed) {
        _sharedController!.add(putnici);
        debugPrint('🔊 [RegistrovaniPutnik] Stream emitovao listu sa ${putnici.length} putnika');
      } else {
        debugPrint('⚠️ [RegistrovaniPutnik] Controller nije dostupan ili je zatvoren');
      }
    } catch (e) {
      debugPrint('🔴 [RegistrovaniPutnik] Error fetching passengers: $e');
    }
  }

  /// 🔌 Setup realtime subscription - Koristi payload za partial updates
  static void _setupRealtimeSubscription(SupabaseClient supabase) {
    _sharedSubscription?.cancel();

    debugPrint('🔗 [RegistrovaniPutnik] Setup realtime subscription...');
    // Koristi centralizovani RealtimeManager
    _sharedSubscription = RealtimeManager.instance.subscribe('registrovani_putnici').listen((payload) {
      debugPrint('🔄 [RegistrovaniPutnik] Payload primljen: ${payload.eventType}');
      unawaited(_handleRealtimeUpdate(payload));
    }, onError: (error) {
      debugPrint('❌ [RegistrovaniPutnik] Stream error: $error');
    });
    debugPrint('✅ [RegistrovaniPutnik] Realtime subscription postavljena');
  }

  /// 🔄 Handle realtime update koristeći payload umesto full refetch
  static Future<void> _handleRealtimeUpdate(PostgresChangePayload payload) async {
    if (_lastValue == null) {
      debugPrint('⚠️ [RegistrovaniPutnik] Nema inicijalne vrednosti, preskačem update');
      return;
    }

    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;

    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        await _handleInsert(newRecord);
        break;
      case PostgresChangeEvent.update:
        await _handleUpdate(newRecord, oldRecord);
        break;
      case PostgresChangeEvent.delete:
        _handleDelete(oldRecord);
        break;
      default:
        debugPrint('⚠️ [RegistrovaniPutnik] Nepoznat event type: ${payload.eventType}');
        break;
    }
  }

  /// 🗑️ Handle DELETE event
  static void _handleDelete(Map<String, dynamic> oldRecord) {
    final putnikId = oldRecord['id'] as String?;
    if (putnikId == null || _lastValue == null) return;

    final updatedList = _lastValue!.where((p) => p.id != putnikId).toList();
    if (updatedList.length != _lastValue!.length) {
      debugPrint('🗑️ [RegistrovaniPutnik] DELETE: Uklonjen putnik $putnikId');
      _lastValue = updatedList;
      _emitUpdate();
    }
  }

  /// ➕ Handle INSERT event
  static Future<void> _handleInsert(Map<String, dynamic> newRecord) async {
    try {
      final putnikId = newRecord['id'] as String?;
      if (putnikId == null) return;

      // Proveri da li zadovoljava filter kriterijume (nije neaktivan, nije obrisan, nije duplikat)
      final status = newRecord['status'] as String? ?? 'aktivan';
      final obrisan = newRecord['obrisan'] as bool? ?? false; // 🛡️ FIX: Default je false
      final isDuplicate = newRecord['is_duplicate'] as bool? ?? false;

      if (status == 'neaktivan' || obrisan || isDuplicate) {
        debugPrint('🔄 [RegistrovaniPutnik] INSERT ignorisan (ne zadovoljava filter)');
        return;
      }

      // Dohvati potpune podatke BEZ JOIN-a (privremeno)
      final fullData = await supabase
          .from('registrovani_putnici')
          .select('*') // Bez foreign key lookup
          .eq('id', putnikId)
          .single();

      final putnik = RegistrovaniPutnik.fromMap(fullData);

      // Dodaj u listu i sortiraj
      _lastValue!.add(putnik);
      _lastValue!.sort((a, b) => a.putnikIme.compareTo(b.putnikIme));

      debugPrint('✅ [RegistrovaniPutnik] INSERT: Dodan ${putnik.putnikIme}');
      _emitUpdate();
    } catch (e) {
      debugPrint('❌ [RegistrovaniPutnik] INSERT error: $e');
    }
  }

  /// 🔄 Handle UPDATE event
  static Future<void> _handleUpdate(Map<String, dynamic> newRecord, Map<String, dynamic>? oldRecord) async {
    try {
      final putnikId = newRecord['id'] as String?;
      if (putnikId == null) return;

      final index = _lastValue!.indexWhere((p) => p.id == putnikId);

      // Proveri da li sada zadovoljava filter kriterijume
      final status = newRecord['status'] as String? ?? 'aktivan';
      final obrisan = newRecord['obrisan'] as bool? ?? false; // 🛡️ FIX: Default je false
      final isDuplicate = newRecord['is_duplicate'] as bool? ?? false;
      final shouldBeIncluded = status != 'neaktivan' && !obrisan && !isDuplicate;

      if (shouldBeIncluded) {
        // Dohvati potpune podatke sa JOIN-om
        final fullData = await supabase
            .from('registrovani_putnici')
            .select('*') // Bez foreign key lookup
            .eq('id', putnikId)
            .single();

        final updatedPutnik = RegistrovaniPutnik.fromMap(fullData);

        if (index == -1) {
          // Možda je bio neaktivan, a sada je aktivan - dodaj
          _lastValue!.add(updatedPutnik);
          debugPrint('✅ [RegistrovaniPutnik] UPDATE: Dodan ${updatedPutnik.putnikIme} (više nije neaktivan)');
        } else {
          // Update postojeći
          _lastValue![index] = updatedPutnik;
          debugPrint('✅ [RegistrovaniPutnik] UPDATE: Ažuriran ${updatedPutnik.putnikIme}');
        }
        _lastValue!.sort((a, b) => a.putnikIme.compareTo(b.putnikIme));
      } else {
        // Ukloni iz liste ako postoji
        if (index != -1) {
          final putnik = _lastValue![index];
          _lastValue!.removeAt(index);
          debugPrint('✅ [RegistrovaniPutnik] UPDATE: Uklonjen ${putnik.putnikIme} (više ne zadovoljava filter)');
        }
      }

      _emitUpdate();
    } catch (e) {
      debugPrint('❌ [RegistrovaniPutnik] UPDATE error: $e');
    }
  }

  /// 🔊 Emit update u stream
  static void _emitUpdate() {
    if (_sharedController != null && !_sharedController!.isClosed) {
      _sharedController!.add(List.from(_lastValue!));
      debugPrint('🔊 [RegistrovaniPutnik] Stream emitovao update sa ${_lastValue!.length} putnika');
    }
  }

  /// 📱 Normalizuje broj telefona za poređenje
  static String _normalizePhone(String telefon) {
    var cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+381')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('00381')) {
      cleaned = '0${cleaned.substring(5)}';
    }
    return cleaned;
  }

  /// 🔍 Proveri da li već postoji putnik sa istim brojem telefona
  /// ✅ FIX: Ignoriši duplikate i obrisane putnike
  Future<RegistrovaniPutnik?> findByPhone(String telefon) async {
    if (telefon.isEmpty) return null;

    final normalizedInput = _normalizePhone(telefon);

    // Dohvati samo ORIGINALNE (ne-duplicirane) putnike koji nisu obrisani
    final allPutnici =
        await _supabase.from('registrovani_putnici').select().eq('obrisan', false).eq('is_duplicate', false);

    for (final p in allPutnici) {
      final storedPhone = p['broj_telefona'] as String? ?? '';
      if (storedPhone.isNotEmpty && _normalizePhone(storedPhone) == normalizedInput) {
        return RegistrovaniPutnik.fromMap(p);
      }
    }
    return null;
  }

  /// Kreira novog mesečnog putnika
  /// Baca grešku ako već postoji putnik sa istim brojem telefona
  Future<RegistrovaniPutnik> createRegistrovaniPutnik(
    RegistrovaniPutnik putnik,
  ) async {
    // 🔍 PROVERA DUPLIKATA - pre insert-a proveri da li već postoji
    final telefon = putnik.brojTelefona;
    if (telefon != null && telefon.isNotEmpty) {
      final existing = await findByPhone(telefon);
      if (existing != null) {
        throw Exception('Putnik sa ovim brojem telefona već postoji: ${existing.putnikIme}. '
            'Možete ga pronaći u listi putnika.');
      }
    }

    final putnikMap = putnik.toMap();
    final response = await _supabase.from('registrovani_putnici').insert(putnikMap).select('''
          *
        ''').single();

    return RegistrovaniPutnik.fromMap(response);
  }

  /// Ažurira mesečnog putnika
  Future<RegistrovaniPutnik> updateRegistrovaniPutnik(
    String id,
    Map<String, dynamic> updates,
  ) async {
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await _supabase.from('registrovani_putnici').update(updates).eq('id', id).select('''
          *
        ''').single();

    return RegistrovaniPutnik.fromMap(response);
  }

  /// Ažurira mesečnog putnika (legacy metoda name)
  Future<RegistrovaniPutnik?> azurirajMesecnogPutnika(RegistrovaniPutnik putnik) async {
    try {
      final result = await updateRegistrovaniPutnik(putnik.id, putnik.toMap());
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Dodaje novog mesečnog putnika (legacy metoda name)
  Future<RegistrovaniPutnik> dodajMesecnogPutnika(RegistrovaniPutnik putnik) async {
    return await createRegistrovaniPutnik(putnik);
  }

  /// Ažurira plaćanje za mesec (vozacId je UUID)
  /// Koristi voznje_log za praćenje vožnji
  Future<bool> azurirajPlacanjeZaMesec(
    String putnikId,
    double iznos,
    String vozacIme, // 🔧 FIX: Sada prima IME vozača, ne UUID
    DateTime pocetakMeseca,
    DateTime krajMeseca,
  ) async {
    String? validVozacId;

    try {
      // Konvertuj ime vozača u UUID za foreign key kolonu
      if (vozacIme.isNotEmpty) {
        if (_isValidUuid(vozacIme)) {
          // Ako je već UUID, koristi ga
          validVozacId = vozacIme;
        } else {
          // Konvertuj ime u UUID
          try {
            // VozacCache je već inicijalizovan pri startu
            var converted = VozacCache.getUuidByIme(vozacIme);
            converted ??= await VozacCache.getUuidByImeAsync(vozacIme);
            if (converted != null && _isValidUuid(converted)) {
              validVozacId = converted;
            }
          } catch (e) {
            debugPrint('❌ azurirajPlacanjeZaMesec: Greška pri VozacMapping za "$vozacIme": $e');
          }
        }
      }

      if (validVozacId == null) {
        debugPrint(
            '⚠️ azurirajPlacanjeZaMesec: vozacId je NULL za vozača "$vozacIme" - uplata neće biti u statistici!');
      }

      await VoznjeLogService.dodajUplatu(
        putnikId: putnikId,
        datum: DateTime.now(),
        iznos: iznos,
        vozacId: validVozacId,
        vozacImeParam: vozacIme, // ✅ fallback: ako UUID lookup ne uspe, ime se upisuje direktno
        placeniMesec: pocetakMeseca.month,
        placenaGodina: pocetakMeseca.year,
        tipUplate: 'uplata_mesecna',
      );

      return true;
    } catch (e) {
      // 🔧 FIX: Baci exception sa pravom greškom da korisnik vidi šta je problem
      rethrow;
    }
  }

  /// Helper funkcija za validaciju UUID formata
  bool _isValidUuid(String str) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(str);
  }

  /// Briše mesečnog putnika (soft delete)
  Future<bool> obrisiRegistrovaniPutnik(String id) async {
    try {
      // Trajno brisanje svih vezanih podataka
      await _supabase.from('pin_zahtevi').delete().eq('putnik_id', id);
      await _supabase.from('seat_requests').delete().eq('putnik_id', id);
      await _supabase.from('voznje_log').delete().eq('putnik_id', id);
      await _supabase.from('registrovani_putnici').delete().eq('id', id);

      return true;
    } catch (e) {
      debugPrint('❌ [obrisiRegistrovaniPutnik] Greška: $e');
      return false;
    }
  }

  /// Dohvata sva plaćanja za mesečnog putnika
  /// 🔄 POJEDNOSTAVLJENO: Koristi voznje_log + registrovani_putnici
  Future<List<Map<String, dynamic>>> dohvatiPlacanjaZaPutnika(
    String putnikIme,
  ) async {
    try {
      List<Map<String, dynamic>> svaPlacanja = [];

      final putnik =
          await _supabase.from('registrovani_putnici').select('id, vozac_id').eq('putnik_ime', putnikIme).maybeSingle();

      if (putnik == null) return [];

      final placanjaIzLoga = await _supabase.from('voznje_log').select().eq('putnik_id', putnik['id']).inFilter(
          'tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']).order('datum', ascending: false) as List<dynamic>;

      for (var placanje in placanjaIzLoga) {
        svaPlacanja.add({
          'cena': placanje['iznos'],
          'created_at': placanje['created_at'],
          'vozac_ime': await _getVozacImeByUuid(placanje['vozac_id'] as String?),
          'putnik_ime': putnikIme,
          'datum': placanje['datum'],
          'placeniMesec': placanje['placeni_mesec'],
          'placenaGodina': placanje['placena_godina'],
        });
      }

      return svaPlacanja;
    } catch (e) {
      return [];
    }
  }

  /// Dohvata sva plaćanja za mesečnog putnika po ID-u
  Future<List<Map<String, dynamic>>> dohvatiPlacanjaZaPutnikaById(String putnikId) async {
    try {
      final placanjaIzLoga = await _supabase.from('voznje_log').select().eq('putnik_id', putnikId).inFilter(
          'tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']).order('datum', ascending: false) as List<dynamic>;

      List<Map<String, dynamic>> results = [];
      for (var placanje in placanjaIzLoga) {
        results.add({
          'cena': placanje['iznos'],
          'created_at': placanje['created_at'],
          // 'vozac_ime': await _getVozacImeByUuid(placanje['vozac_id'] as String?), // Preskočimo vozača za performanse ako nije potreban
          'datum': placanje['datum'],
          'placeniMesec': placanje['placeni_mesec'],
          'placenaGodina': placanje['placena_godina'],
        });
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  /// Helper funkcija za dobijanje imena vozača iz UUID-a
  Future<String?> _getVozacImeByUuid(String? vozacUuid) async {
    if (vozacUuid == null || vozacUuid.isEmpty) return null;

    try {
      final response = await _supabase.from('vozaci').select('ime').eq('id', vozacUuid).limit(1).maybeSingle();
      if (response == null) {
        return VozacCache.getImeByUuid(vozacUuid);
      }
      return response['ime'] as String?;
    } catch (e) {
      return VozacCache.getImeByUuid(vozacUuid);
    }
  }

  /// Dohvata zakupljene putnike za današnji dan
  /// 🔄 POJEDNOSTAVLJENO: Koristi registrovani_putnici direktno
  /// Stream za realtime ažuriranja mesečnih putnika
  /// Koristi direktan Supabase Realtime
  Stream<List<RegistrovaniPutnik>> get registrovaniPutniciStream {
    return streamAktivniRegistrovaniPutnici();
  }

  /// Izračunava broj putovanja iz voznje_log
  static Future<int> izracunajBrojPutovanjaIzIstorije(
    String mesecniPutnikId,
  ) async {
    try {
      final response =
          await supabase.from('voznje_log').select('datum').eq('putnik_id', mesecniPutnikId).eq('tip', 'voznja');

      final jedinstveniDatumi = <String>{};
      for (final red in response) {
        if (red['datum'] != null) {
          jedinstveniDatumi.add(red['datum'] as String);
        }
      }

      return jedinstveniDatumi.length;
    } catch (e) {
      return 0;
    }
  }

  /// Izračunava broj otkazivanja iz voznje_log
  static Future<int> izracunajBrojOtkazivanjaIzIstorije(
    String mesecniPutnikId,
  ) async {
    try {
      final response =
          await supabase.from('voznje_log').select('datum').eq('putnik_id', mesecniPutnikId).eq('tip', 'otkazivanje');

      final jedinstveniDatumi = <String>{};
      for (final red in response) {
        if (red['datum'] != null) {
          jedinstveniDatumi.add(red['datum'] as String);
        }
      }

      return jedinstveniDatumi.length;
    } catch (e) {
      return 0;
    }
  }

  // ==================== ENHANCED CAPABILITIES ====================

  /// 🔥 Stream poslednjeg plaćanja za putnika (iz voznje_log)
  /// Vraća Map sa 'vozac_ime', 'datum' i 'iznos'
  static Stream<Map<String, dynamic>?> streamPoslednjePlacanje(String putnikId) async* {
    try {
      final response = await supabase
          .from('voznje_log')
          .select('datum, vozac_id, iznos')
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna'])
          .order('datum', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        yield null;
        return;
      }

      final vozacId = response['vozac_id'] as String?;
      final datum = response['datum'] as String?;
      final iznos = (response['iznos'] as num?)?.toDouble() ?? 0.0;
      String? vozacIme;
      if (vozacId != null && vozacId.isNotEmpty) {
        vozacIme = VozacCache.getImeByUuid(vozacId);
      }

      yield {
        'vozac_ime': vozacIme,
        'datum': datum,
        'iznos': iznos,
      };
    } catch (e) {
      debugPrint('⚠️ Error yielding vozac info: $e');
      yield null;
    }
  }

  /// 💰 Dohvati UKUPNO plaćeno za putnika (svi uplate)
  static Future<double> dohvatiUkupnoPlaceno(String putnikId) async {
    try {
      final response = await supabase
          .from('voznje_log')
          .select('iznos')
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna']);

      double ukupno = 0.0;
      for (final row in response) {
        ukupno += (row['iznos'] as num?)?.toDouble() ?? 0.0;
      }
      return ukupno;
    } catch (e) {
      debugPrint('⚠️ Error calculating total payment: $e');
      return 0.0;
    }
  }

  /// 🔧 SINGLETON STREAM za SVE mesečne putnike (uključujući neaktivne)
  static Stream<List<RegistrovaniPutnik>> streamSviRegistrovaniPutnici() {
    if (_sharedSviController != null && !_sharedSviController!.isClosed) {
      if (_lastSviValue != null) {
        Future.microtask(() {
          if (_sharedSviController != null && !_sharedSviController!.isClosed) {
            _sharedSviController!.add(_lastSviValue!);
          }
        });
      }
      return _sharedSviController!.stream;
    }

    _sharedSviController = StreamController<List<RegistrovaniPutnik>>.broadcast();

    _fetchAndEmitSvi(supabase);
    _setupRealtimeSubscriptionSvi(supabase);

    return _sharedSviController!.stream;
  }

  static Future<void> _fetchAndEmitSvi(SupabaseClient supabase) async {
    try {
      final data = await supabase
          .from('registrovani_putnici')
          .select()
          .eq('obrisan', false) // Samo ovo je razlika - ne filtriramo po 'aktivan'
          .order('putnik_ime');

      final putnici = data.map((json) => RegistrovaniPutnik.fromMap(json)).toList();
      _lastSviValue = putnici;

      if (_sharedSviController != null && !_sharedSviController!.isClosed) {
        _sharedSviController!.add(putnici);
      }
    } catch (_) {}
  }

  static void _setupRealtimeSubscriptionSvi(SupabaseClient supabase) {
    _sharedSviSubscription?.cancel();
    _sharedSviSubscription = RealtimeManager.instance.subscribe('registrovani_putnici_svi').listen((payload) {
      _fetchAndEmitSvi(supabase);
    });
  }
}
