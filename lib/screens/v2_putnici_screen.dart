import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';
import '../helpers/v2_putnik_statistike_helper.dart';
import '../models/registrovani_putnik.dart';
import '../services/permission_service.dart';
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_putnik_service.dart';
import '../theme.dart';
import '../utils/app_snack_bar.dart';
import '../utils/vozac_cache.dart';
import '../widgets/v2_pin_dialog.dart';
import '../widgets/v2_putnik_dialog.dart';

// 🔌 HELPER EXTENSION za Set poredenje
extension SetExtensions<T> on Set<T> {
  bool isEqualTo(Set<T> other) {
    if (length != other.length) return false;
    return containsAll(other) && other.containsAll(this);
  }
}

class V2PutniciScreen extends StatefulWidget {
  const V2PutniciScreen({super.key});

  @override
  State<V2PutniciScreen> createState() => _V2PutniciScreenState();
}

class _V2PutniciScreenState extends State<V2PutniciScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'svi'; // 'svi', 'radnik', 'ucenik', 'dnevni'

  // 🔄 REFRESH KEY: Forsira kreiranje novog stream-a nakon cuvanja
  int _streamRefreshKey = 0;

  // V2 servis instance
  final V2PutnikService _putnikService = V2PutnikService();

  // ?? OPTIMIZACIJA: Connection resilience
  StreamSubscription<dynamic>? _connectionSubscription;
  bool _isConnected = true;

  // Mapa placenih meseci po putniku
  Map<String, Set<String>> _placeniMeseci = {};

  // Controllers for new passenger (declared but initialized in _initializeControllers)
  late TextEditingController _imeController;
  late TextEditingController _tipSkoleController;
  late TextEditingController _brojTelefonaController;
  late TextEditingController _brojTelefonaOcaController;
  late TextEditingController _brojTelefonaMajkeController;

  // Services
  final List<StreamSubscription> _subscriptions = [];

  // 💳 PLACANJE STATE
  Map<String, double> _stvarnaPlacanja = {};
  DateTime? _lastPaymentUpdate;
  Set<String> _lastPutnikIds = {};
  Timer? _paymentUpdateDebounceTimer; // ⏱️ DEBOUNCE TIMER za payment updates

  // 📊 BROJANJE PUTNIKA PO TIPU
  int _brojRadnika = 0;
  int _brojUcenika = 0;
  int _brojDnevnih = 0;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeOptimizations();
  }

  void _initializeControllers() {
    _imeController = TextEditingController();
    _tipSkoleController = TextEditingController();
    _brojTelefonaController = TextEditingController();
    _brojTelefonaOcaController = TextEditingController();
    _brojTelefonaMajkeController = TextEditingController();
  }

  // ⚙️ OPTIMIZACIJA: Inicijalizacija debounced search i error handling
  void _initializeOptimizations() {
    // Listen za search promene - rebuild UI
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });

    // 🔌 Connection monitoring - prati konekciju ka serveru
    _setupConnectionMonitoring();
  }

  // 🔌 PRAVI CONNECTION MONITORING - Periodiski ping server
  void _setupConnectionMonitoring() {
    // Periodiski ping server da proveri konekciju (svakih 30 sekundi)
    _connectionSubscription = Stream.periodic(const Duration(seconds: 30)).listen((_) async {
      try {
        // Ping: dohvati jedan red iz v2_radnici
        await supabase.from('v2_radnici').select('id').limit(1).maybeSingle();
        if (_isConnected == false && mounted) {
          setState(() => _isConnected = true);
        }
      } catch (e) {
        // Nema konekcije
        if (_isConnected == true && mounted) {
          setState(() => _isConnected = false);
        }
      }
    });
  }

  // 🚀 BATCH UCITAVANJE
  Future<void> _ucitajSvePodatke(List<RegistrovaniPutnik> putnici) async {
    if (putnici.isEmpty) return;

    try {
      await _ucitajStvarnaPlacanja(putnici);
    } catch (e) {
      debugPrint('🔴 [RegistrovaniPutnici._ucitajSvePodatke] Error: $e');
    }
  }

  // 💰 UCITAJ STVARNA PLACANJA iz voznje_log
  Future<void> _ucitajStvarnaPlacanja(List<RegistrovaniPutnik> putnici) async {
    try {
      if (putnici.isEmpty) return; // ? Early exit - nema šta učitavati

      // ?? FIX: Ucitaj STVARNE uplate iz voznje_log tabele
      final Map<String, double> placanja = {};
      final Map<String, Set<String>> placeniMeseciMap = {};

      // Dohvati poslednje placanje za svakog putnika
      for (final putnik in putnici) {
        try {
          // Učitaj sve uplate za putnika da bi se znali placeni meseci
          final allPayments = await supabase
              .from('v2_statistika_istorija')
              .select('iznos, placeni_mesec, placena_godina')
              .eq('putnik_id', putnik.id)
              .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna'])
              .not('placeni_mesec', 'is', null)
              .not('placena_godina', 'is', null);

          // Popuni placene mesece
          final placeniMeseci = <String>{};
          for (final payment in allPayments) {
            final mesec = payment['placeni_mesec'];
            final godina = payment['placena_godina'];
            if (mesec != null && godina != null) {
              placeniMeseci.add('$mesec-$godina');
            }
          }
          placeniMeseciMap[putnik.id] = placeniMeseci;

          // Poslednje placanje za iznos
          final response = await supabase
              .from('v2_statistika_istorija')
              .select('iznos')
              .eq('putnik_id', putnik.id)
              .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna'])
              .order('datum', ascending: false)
              .limit(1)
              .maybeSingle();

          if (response != null && response['iznos'] != null) {
            placanja[putnik.id] = (response['iznos'] as num).toDouble();
          } else {
            // Ako nema uplate, stavi 0
            placanja[putnik.id] = 0.0;
          }
        } catch (e) {
          placanja[putnik.id] = 0.0;
          placeniMeseciMap[putnik.id] = {};
        }
      }
      if (mounted) {
        // ?? ANTI-REBUILD OPTIMIZATION: Samo update ako su se podaci stvarno promenili
        final existingKeys = _stvarnaPlacanja.keys.toSet();
        final newKeys = placanja.keys.toSet();

        bool hasChanges = !existingKeys.isEqualTo(newKeys);
        if (!hasChanges) {
          // Proveri vrednosti za postojece kljuceve
          for (final key in existingKeys) {
            if (_stvarnaPlacanja[key] != placanja[key]) {
              hasChanges = true;
              break;
            }
          }
        }

        // Proveri i placene mesece
        final existingMeseciKeys = _placeniMeseci.keys.toSet();
        final newMeseciKeys = placeniMeseciMap.keys.toSet();
        bool meseciChanged = !existingMeseciKeys.isEqualTo(newMeseciKeys);
        if (!meseciChanged) {
          for (final key in existingMeseciKeys) {
            if (_placeniMeseci[key] != placeniMeseciMap[key]) {
              meseciChanged = true;
              break;
            }
          }
        }

        if (hasChanges || meseciChanged) {
          _stvarnaPlacanja = placanja;
          _placeniMeseci = placeniMeseciMap;
          // ?? SAMO JEDNOM setState() umesto kontinuiranih rebuild-a
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      // Greška u učitavanju stvarnih plaćanja
    }
  }

  @override
  void dispose() {
    // Cleanup debounce timer
    _paymentUpdateDebounceTimer?.cancel();
    _connectionSubscription?.cancel();

    // COMPREHENSIVE TEXTCONTROLLER CLEANUP
    try {
      _searchController.dispose();
      _imeController.dispose();
      _tipSkoleController.dispose();
      _brojTelefonaController.dispose();
      _brojTelefonaOcaController.dispose();
      _brojTelefonaMajkeController.dispose();

      _subscriptions.forEach((subscription) => subscription.cancel());
    } catch (e) {
      // ignore controller dispose errors
    }

    super.dispose();
  }

  /// ?? DIREKTNO FILTRIRANJE - dodaje search i filterType na vec filtrirane podatke iz streama
  /// Stream vec vraca aktivne putnike sa validnim statusom, ovde samo dodajemo dinamicke filtere
  List<RegistrovaniPutnik> _filterPutniciDirect(
    List<RegistrovaniPutnik> putnici,
    String searchTerm,
    String filterType,
  ) {
    var filtered = putnici;

    // Filter po tipu (radnik/ucenik)
    if (filterType != 'svi') {
      filtered = filtered.where((p) => p.tip == filterType).toList();
    }

    // Filter po search term
    if (searchTerm.isNotEmpty) {
      final searchLower = searchTerm.toLowerCase();
      filtered = filtered.where((p) {
        return p.putnikIme.toLowerCase().contains(searchLower) ||
            p.tip.toLowerCase().contains(searchLower) ||
            (p.tipSkole?.toLowerCase().contains(searchLower) ?? false);
      }).toList();
    }

    // ?? BINARYBITCH SORTING BLADE: A Ž (Serbian alphabet), neaktivni na dno
    filtered.sort((a, b) {
      // Neaktivni uvek idu na kraj
      if (a.aktivan != b.aktivan) return a.aktivan ? -1 : 1;
      return a.putnikIme.toLowerCase().compareTo(b.putnikIme.toLowerCase());
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: Theme.of(context).backgroundGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).glassContainer,
              border: Border.all(
                color: Theme.of(context).glassBorder,
                width: 1.5,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(25),
                bottomRight: Radius.circular(25),
              ),
              // No boxShadow - keep AppBar fully transparent and only glassBorder
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Filter za radnike sa brojem
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.engineering,
                            color: _selectedFilter == 'radnik' ? Colors.white : Colors.white70,
                            shadows: const [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 3,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          onPressed: () {
                            final newFilter = _selectedFilter == 'radnik' ? 'svi' : 'radnik';
                            setState(() {
                              _selectedFilter = newFilter;
                            });
                          },
                          tooltip: 'Filtriraj radnike',
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFF6B6B),
                                  Color(0xFFFF8E53),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            child: Text(
                              _brojRadnika.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Filter za ucenike sa brojem
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.school,
                            color: _selectedFilter == 'ucenik' ? Colors.white : Colors.white70,
                            shadows: const [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 3,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          onPressed: () {
                            final newFilter = _selectedFilter == 'ucenik' ? 'svi' : 'ucenik';
                            setState(() {
                              _selectedFilter = newFilter;
                            });
                          },
                          tooltip: 'Filtriraj ucenike',
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF4ECDC4),
                                  Color(0xFF44A08D),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.teal.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            child: Text(
                              _brojUcenika.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Filter za dnevne putnike sa brojem
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.today,
                            color: _selectedFilter == 'dnevni' ? Colors.white : Colors.white70,
                            shadows: const [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 3,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          onPressed: () {
                            final newFilter = _selectedFilter == 'dnevni' ? 'svi' : 'dnevni';
                            setState(() {
                              _selectedFilter = newFilter;
                            });
                          },
                          tooltip: 'Filtriraj dnevne putnike',
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF5C9CE6),
                                  Color(0xFF3B7DD8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            child: Text(
                              _brojDnevnih.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 3,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      onPressed: () => _pokaziDijalogZaDodavanje(),
                      tooltip: 'Dodaj novog putnika',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            // ?? SEARCH BAR
            Container(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Pretraži putnike...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).primaryColor,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ?? LISTA PUTNIKA - direktan Supabase realtime stream
            Expanded(
              child: StreamBuilder<List<RegistrovaniPutnik>>(
                // ? REMOVED: ValueKey - ispravljeno memory leak problem sa stream lifecycle-om
                stream: _putnikService.streamAktivniPutnici(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Greška pri učitavanju mesečnih putnika',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    );
                  }

                  final sviPutnici = snapshot.data ?? [];

                  // 📊 PREBROJAVANJE PUTNIKA PO TIPU
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      final radnika = sviPutnici.where((p) => p.tip == 'radnik').length;
                      final ucenika = sviPutnici.where((p) => p.tip == 'ucenik').length;
                      final dnevnih = sviPutnici.where((p) => p.tip == 'dnevni' || p.tip == 'posiljka').length;

                      if (_brojRadnika != radnika || _brojUcenika != ucenika || _brojDnevnih != dnevnih) {
                        setState(() {
                          _brojRadnika = radnika;
                          _brojUcenika = ucenika;
                          _brojDnevnih = dnevnih;
                        });
                      }
                    }
                  });

                  // Filtriraj lokalno
                  final filteredPutnici = _filterPutniciDirect(
                    sviPutnici,
                    _searchController.text,
                    _selectedFilter,
                  );

                  // ??? UCITAJ STVARNA PLACANJA kada se dobiju novi podaci - DEBOUNCED
                  if (filteredPutnici.isNotEmpty) {
                    final currentIds = filteredPutnici.map((p) => p.id).toSet();

                    // ?? PRAVI DEBOUNCE: Ako se putnici promenili, ponovo pokreni timer
                    if (!_lastPutnikIds.isEqualTo(currentIds)) {
                      _lastPutnikIds = currentIds;

                      // Otkaži stari timer ako postoji
                      _paymentUpdateDebounceTimer?.cancel();

                      // Kreiraj novi timer - čekaj 2 sekunde pre nego što učitaš podatke
                      _paymentUpdateDebounceTimer = Timer(const Duration(seconds: 2), () {
                        if (mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            // 🚀 BATCH UCITAVANJE - sve tri operacije odjednom za performanse
                            _ucitajSvePodatke(filteredPutnici);
                          });
                        }
                      });
                    }
                  }

                  // Prikaži samo prvih 50 rezultata
                  final prikazaniPutnici =
                      filteredPutnici.length > 50 ? filteredPutnici.sublist(0, 50) : filteredPutnici;

                  if (prikazaniPutnici.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchController.text.isNotEmpty ? Icons.search_off : Icons.group_off,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isNotEmpty ? 'Nema rezultata pretrage' : 'Nema mesecnih putnika',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (_searchController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Pokušajte sa drugim terminom',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    key: ValueKey(prikazaniPutnici.length),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: prikazaniPutnici.length,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    itemBuilder: (context, index) {
                      final putnik = prikazaniPutnici[index];
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(putnik.id),
                        duration: Duration(milliseconds: 300 + (index * 50)),
                        tween: Tween(begin: 0.0, end: 1.0),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, 30 * (1 - value)),
                            child: Opacity(
                              opacity: value,
                              child: child,
                            ),
                          );
                        },
                        child: _buildPutnikCard(putnik, index + 1),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPutnikCard(RegistrovaniPutnik putnik, int redniBroj) {
    final bool bolovanje = putnik.status == 'bolovanje';
    // Sačuvaj sva vremena po danima (pon -> pet) i prikaži ih na kartici.
    // Prethodna logika je prikazivala samo PRVI dan koji je imao vreme.
    // Sada prikazujemo sve dane koji imaju bar jedan polazak (BC i/ili VS)
    final List<String> _daniOrder = ['pon', 'uto', 'sre', 'cet', 'pet'];

    final bool neaktivan = !putnik.aktivan && !bolovanje;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: neaktivan ? 1 : 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Opacity(
        opacity: neaktivan ? 0.55 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: bolovanje
                ? LinearGradient(
                    colors: [Colors.amber[50]!, Colors.orange[50]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : neaktivan
                    ? LinearGradient(
                        colors: [Colors.grey[200]!, Colors.grey[300]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [Colors.white, Colors.grey[50]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
            border: Border.all(
              color: bolovanje
                  ? Colors.orange[200]!
                  : neaktivan
                      ? Colors.grey[400]!
                      : Colors.grey[200]!,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ?? HEADER - Ime, broj i aktivnost switch
                Row(
                  children: [
                    // Redni broj i ime
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            '$redniBroj.',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              putnik.putnikIme,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: bolovanje ? Colors.orange : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Switch za aktivnost ili bolovanje
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bolovanje ? 'BOLUJE' : (putnik.aktivan ? 'AKTIVAN' : 'PAUZIRAN'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: bolovanje ? Colors.orange : (putnik.aktivan ? Colors.green : Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Switch(
                          value: putnik.aktivan,
                          onChanged: bolovanje ? null : (value) => _toggleAktivnost(putnik),
                          thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.green;
                            }
                            return Colors.grey;
                          }),
                          trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.green.shade200;
                            }
                            return Colors.grey.shade300;
                          }),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ?? OSNOVNE INFORMACIJE - tip, telefon, škola, statistike u jednom redu
                Row(
                  children: [
                    // Tip putnika
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Icon(
                            putnik.tip == 'radnik'
                                ? Icons.engineering
                                : putnik.tip == 'dnevni'
                                    ? Icons.today
                                    : Icons.school,
                            size: 16,
                            color: putnik.tip == 'radnik'
                                ? Colors.blue.shade600
                                : putnik.tip == 'dnevni'
                                    ? Colors.orange.shade600
                                    : Colors.green.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            putnik.tip.toUpperCase(),
                            style: TextStyle(
                              color: putnik.tip == 'radnik'
                                  ? Colors.blue.shade700
                                  : putnik.tip == 'dnevni'
                                      ? Colors.orange.shade700
                                      : Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Telefon - prikaže broj dostupnih kontakata
                    if (putnik.brojTelefona != null ||
                        putnik.brojTelefonaOca != null ||
                        putnik.brojTelefonaMajke != null)
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            // Ikone za dostupne kontakte
                            if (putnik.brojTelefona != null)
                              Icon(
                                Icons.person,
                                size: 14,
                                color: Colors.green.shade600,
                              ),
                            if (putnik.brojTelefonaOca != null)
                              Icon(
                                Icons.man,
                                size: 14,
                                color: Colors.blue.shade600,
                              ),
                            if (putnik.brojTelefonaMajke != null)
                              Icon(
                                Icons.woman,
                                size: 14,
                                color: Colors.pink.shade600,
                              ),
                            const SizedBox(width: 4),
                            Text(
                              '${_prebrojKontakte(putnik)} kontakt${_prebrojKontakte(putnik) == 1 ? '' : 'a'}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Tip škole/ustanova (ako postoji)
                    if (putnik.tipSkole != null)
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Icon(
                              putnik.tip == 'ucenik' ? Icons.school_outlined : Icons.business_outlined,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                putnik.tipSkole!,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                // ??? PLACANJE I STATISTIKE - jednaki elementi u redu

                Row(
                  children: [
                    // ?? DUGME ZA PLACANJE
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _prikaziPlacanje(putnik),
                        icon: (_stvarnaPlacanja[putnik.id] ?? 0) > 0
                            ? Icons.check_circle_outline
                            : Icons.payments_outlined,
                        label: (_stvarnaPlacanja[putnik.id] ?? 0) > 0
                            ? '${(_stvarnaPlacanja[putnik.id]!).toStringAsFixed(0)} RSD'
                            : 'Plati',
                        color: (_stvarnaPlacanja[putnik.id] ?? 0) > 0 ? Colors.green : Colors.purple,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ?? DUGME ZA DETALJE
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _prikaziDetaljneStatistike(putnik),
                        icon: Icons.analytics_outlined,
                        label: 'Detalji',
                        color: Colors.blue,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ?? BROJAC PUTOVANJA
                    Expanded(
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.trending_up,
                              size: 14,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 4),
                            StreamBuilder<int>(
                              stream: Stream.fromFuture(_putnikService.izracunajBrojVoznji(putnik.id)),
                              builder: (context, snapshot) => Text(
                                '${snapshot.data ?? 0}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ? BROJAC OTKAZIVANJA
                    Expanded(
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cancel_outlined,
                              size: 14,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 4),
                            StreamBuilder<int>(
                              stream: Stream.fromFuture(_putnikService.izracunajBrojOtkazivanja(putnik.id)),
                              builder: (context, snapshot) => Text(
                                '${snapshot.data ?? 0}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ??? ACTION BUTTONS - samo najvažnije
                Row(
                  children: [
                    // Pozovi (ako ima bilo koji telefon)
                    if (putnik.brojTelefona != null ||
                        putnik.brojTelefonaOca != null ||
                        putnik.brojTelefonaMajke != null) ...[
                      Expanded(
                        child: _buildCompactActionButton(
                          onPressed: () => _pokaziKontaktOpcije(putnik),
                          icon: Icons.phone,
                          label: 'Pozovi',
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],

                    // Uredi
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _editPutnik(putnik),
                        icon: Icons.edit_outlined,
                        label: 'Uredi',
                        color: Colors.blue,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ?? PIN
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _showPinDialog(putnik),
                        icon: Icons.lock_outline,
                        label: 'PIN',
                        color: Colors.amber,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Obriši
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _obrisiPutnika(putnik),
                        icon: Icons.delete_outline,
                        label: 'Obriši',
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return SizedBox(
      height: 32,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.15),
              color.withOpacity(0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withOpacity(0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 14, color: color),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: color,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAktivnost(RegistrovaniPutnik putnik) async {
    final noviStatus = putnik.aktivan ? 'neaktivan' : 'aktivan';
    try {
      await _putnikService.updatePutnik(
        putnik.id,
        {'status': noviStatus},
        putnik.tabela,
      );
      if (mounted) {
        AppSnackBar.success(context, '${putnik.putnikIme} je ${noviStatus == 'aktivan' ? "aktiviran" : "deaktiviran"}');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška pri promeni statusa');
      }
    }
  }

  void _editPutnik(RegistrovaniPutnik putnik) {
    showDialog(
      context: context,
      builder: (context) => V2PutnikDialog(
        existingPutnik: putnik,
        onSaved: () {
          // ?? REFRESH: Inkrementiraj key da forsira novi stream sa svježim podacima
          if (mounted) {
            setState(() {
              _streamRefreshKey++;
              // ?? RESET FILTERA: Kada se sačuva putnik, očisti filtere da se svi vide
              _selectedFilter = 'svi';
              _searchController.clear();
            });
          }
        },
      ),
    );
  }

  /// ?? Prikaži PIN dijalog za putnika
  void _showPinDialog(RegistrovaniPutnik putnik) {
    showDialog(
      context: context,
      builder: (context) => V2PinDialog(
        putnikId: putnik.id,
        putnikIme: putnik.putnikIme,
        putnikTabela: putnik.tabela,
        trenutniPin: putnik.pin,
        brojTelefona: putnik.brojTelefona,
      ),
    );
  }

  void _pokaziDijalogZaDodavanje() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => V2PutnikDialog(
        existingPutnik: null, // null indicates adding mode
        onSaved: () {
          if (mounted) {
            setState(() {
              // ?? RESET FILTERA: Kada se doda novi putnik, očisti filtere da se svi vide
              _selectedFilter = 'svi';
              _searchController.clear();
            });
          }
        },
      ),
    );
  }

  void _obrisiPutnika(RegistrovaniPutnik putnik) async {
    // Pokaži potvrdu za brisanje
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Potvrdi brisanje'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Da li ste sigurni da želite da obrišete putnika "${putnik.putnikIme}"?',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Važne informacije:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• Putnik će biti TRAJNO obrisan iz baze'),
                  const Text('• Sve vožnje i statistike se brišu'),
                  const Text('• Svi zahtevi za sedišta se brišu'),
                  const Text('• Ova akcija je NEPOVRATNA!',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Otkaži'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Obriši', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (potvrda == true && mounted) {
      try {
        final success = await _putnikService.deletePutnik(putnik.id, putnik.tabela);

        if (success) {
          // logic simplified slightly if not needing immediate mount check
        }

        if (success && mounted) {
          AppSnackBar.success(context, '${putnik.putnikIme} je uspešno obrisan');
        } else if (mounted) {
          AppSnackBar.error(context, 'Greška pri brisanju putnika');
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.error(context, 'Greška: $e');
        }
      }
    }
  }

  // Helper funkcija za brojanje kontakata
  int _prebrojKontakte(RegistrovaniPutnik putnik) {
    int brojKontakata = 0;
    if (putnik.brojTelefona != null && putnik.brojTelefona!.isNotEmpty) {
      brojKontakata++;
    }
    if (putnik.brojTelefonaOca != null && putnik.brojTelefonaOca!.isNotEmpty) {
      brojKontakata++;
    }
    if (putnik.brojTelefonaMajke != null && putnik.brojTelefonaMajke!.isNotEmpty) {
      brojKontakata++;
    }
    return brojKontakata;
  }

  // ??????????? NOVA FUNKCIJA - Prikazuje sve dostupne kontakte
  Future<void> _pokaziKontaktOpcije(RegistrovaniPutnik putnik) async {
    final List<Widget> opcije = [];

    // Glavni broj telefona
    if (putnik.brojTelefona != null && putnik.brojTelefona!.isNotEmpty) {
      opcije.add(
        ListTile(
          leading: const Icon(Icons.person, color: Colors.green),
          title: const Text('Pozovi putnika'),
          subtitle: Text(putnik.brojTelefona!),
          onTap: () async {
            Navigator.pop(context);
            await _pozovi(putnik.brojTelefona!);
          },
        ),
      );
    }

    // Otac
    if (putnik.brojTelefonaOca != null && putnik.brojTelefonaOca!.isNotEmpty) {
      opcije.add(
        ListTile(
          leading: const Icon(Icons.man, color: Colors.blue),
          title: const Text('Pozovi oca'),
          subtitle: Text(putnik.brojTelefonaOca!),
          onTap: () async {
            Navigator.pop(context);
            await _pozovi(putnik.brojTelefonaOca!);
          },
        ),
      );
    }

    // Majka
    if (putnik.brojTelefonaMajke != null && putnik.brojTelefonaMajke!.isNotEmpty) {
      opcije.add(
        ListTile(
          leading: const Icon(Icons.woman, color: Colors.pink),
          title: const Text('Pozovi majku'),
          subtitle: Text(putnik.brojTelefonaMajke!),
          onTap: () async {
            Navigator.pop(context);
            await _pozovi(putnik.brojTelefonaMajke!);
          },
        ),
      );
    }

    if (opcije.isEmpty) {
      AppSnackBar.info(context, 'Nema dostupnih kontakata');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kontaktiraj ${putnik.putnikIme}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ...opcije,
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Otkaži'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pozovi(String brojTelefona) async {
    try {
      // ?? HUAWEI KOMPATIBILNO - koristi Huawei specificnu logiku (konzistentno sa putnik_card)
      final hasPermission = await PermissionService.ensurePhonePermissionHuawei();
      if (!hasPermission) {
        if (mounted) {
          AppSnackBar.error(context, '❌ Dozvola za pozive je potrebna');
        }
        return;
      }

      final phoneUrl = Uri.parse('tel:$brojTelefona');
      try {
        await launchUrl(phoneUrl, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          AppSnackBar.error(context, '❌ Nije moguće pozivanje sa ovog uređaja');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška pri pozivanju: $e');
      }
    }
  }

  // ?? PRIKAZ DIJALOGA ZA PLACANJE
  Future<void> _prikaziPlacanje(RegistrovaniPutnik putnik) async {
    if (!mounted) return;

    final TextEditingController iznosController = TextEditingController();
    String selectedMonth = _getCurrentMonthYear(); // Default current month

    // ?? FIX: Ucitaj stvarni ukupni iznos iz baze
    final ukupnoPlaceno = await _putnikService.dohvatiUkupnoPlaceno(putnik.id);

    // Default cena po danu za input field
    final cenaPoDanu = CenaObracunService.getCenaPoDanu(putnik);
    iznosController.text = cenaPoDanu.toStringAsFixed(0);

    final tipLower = putnik.tip.toLowerCase();
    final imeLower = putnik.putnikIme.toLowerCase();

    // ?? FIKSNE CENE (Vozaci/Admini prate isti standard)
    final jeZubi = tipLower == 'posiljka' && imeLower.contains('zubi');
    final jePosiljka = tipLower == 'posiljka';
    final jeDnevni = tipLower == 'dnevni';
    final jeFiksna = jeZubi || jePosiljka || jeDnevni;

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    jeFiksna ? Icons.lock : Icons.payments_outlined,
                    color: jeFiksna ? Colors.orange : Colors.purple.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      jeFiksna ? 'Fiksna naplata - ${putnik.putnikIme}' : 'Placanje - ${putnik.putnikIme}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (jeFiksna)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          jeZubi
                              ? 'Tip: Pošiljka ZUBI (300 RSD po pokupljenju)'
                              : (jePosiljka
                                  ? 'Tip: Pošiljka (500 RSD po pokupljenju)'
                                  : 'Tip: Dnevni (600 RSD po pokupljenju)'),
                          style: TextStyle(
                            color: jeZubi ? Colors.purple : (jePosiljka ? Colors.blue : Colors.orange),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (ukupnoPlaceno > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green.shade600,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ukupno placeno: ${ukupnoPlaceno.toStringAsFixed(0)} RSD',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                      // ?? REALTIME: Vozac i datum poslednjeg placanja iz voznje_log
                                      StreamBuilder<Map<String, dynamic>?>(
                                        stream: Stream.fromFuture(_putnikService.dohvatiPlacanja(putnik.id))
                                            .map((lista) => lista.isNotEmpty ? lista.first : null),
                                        builder: (context, snapshot) {
                                          final placanje = snapshot.data;
                                          if (placanje == null) {
                                            return const SizedBox.shrink();
                                          }
                                          final vozacIme = placanje['vozac_ime'] as String?;
                                          final datum = placanje['datum'] as String?;
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (datum != null)
                                                Text(
                                                  'Poslednje placanje: $datum',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.green.shade600,
                                                  ),
                                                ),
                                              if (vozacIme != null)
                                                Text(
                                                  'Placeno: $datum',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    // Ako imamo ime vozaca iz strema, koristimo njegovu boju
                                                    color: VozacCache.getColor(
                                                      vozacIme,
                                                      fallback: Colors.green.shade600,
                                                    ),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              if (vozacIme != null)
                                                Text(
                                                  'Naplatio: $vozacIme',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: VozacCache.getColor(
                                                      vozacIme,
                                                    ),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.add_circle_outline,
                                    color: Colors.blue.shade600,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Dodavanje novog placanja (bice dodato na postojeca)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade700,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ?? IZBOR MESECA
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedMonth,
                          icon: Icon(
                            Icons.calendar_month,
                            color: Colors.purple.shade600,
                          ),
                          style: TextStyle(
                            color: Colors.purple.shade700,
                            fontSize: 16,
                          ),
                          menuMaxHeight: 300, // Ogranici visinu dropdown menija
                          onChanged: (String? newValue) {
                            if (mounted) {
                              setState(() {
                                selectedMonth = newValue!;
                              });
                            }
                          },
                          items: _getMonthOptions().map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ?? IZNOS
                    TextField(
                      controller: iznosController,
                      enabled: !jeFiksna, // ?? Onemoguci izmenu za fiksne cene
                      readOnly: jeFiksna, // ?? Read only
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: jeFiksna ? 'Fiksni iznos (dinari)' : 'Iznos (dinari)',
                        prefixIcon: Icon(
                          jeFiksna ? Icons.lock_outline : Icons.attach_money,
                          color: jeFiksna ? Colors.grey : Colors.purple.shade600,
                        ),
                        helperText: jeFiksna ? 'Fiksna cena za ovaj tip putnika.' : null,
                        fillColor: jeFiksna ? Colors.grey.shade100 : null,
                        filled: jeFiksna,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.purple.shade600,
                            width: 2,
                          ),
                        ),
                      ),
                      autofocus: !jeFiksna,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Otkaži'),
                ),
                // ?? DUGME ZA DETALJNE STATISTIKE
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(); // Zatvori trenutni dialog
                    _prikaziDetaljneStatistike(putnik); // Otvori statistike
                  },
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Detaljno'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final iznos = double.tryParse(iznosController.text);
                    if (iznos != null && iznos > 0) {
                      Navigator.of(context).pop();
                      await _sacuvajPlacanje(putnik, iznos, selectedMonth);
                    } else {
                      AppSnackBar.error(context, 'Unesite valjan iznos');
                    }
                  },
                  icon: Icon(ukupnoPlaceno > 0 ? Icons.add : Icons.save),
                  label: Text(ukupnoPlaceno > 0 ? 'Dodaj placanje' : 'Sacuvaj'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  } // ?? CUVANJE PLACANJA

  // ?? PRIKAŽI DETALJNE STATISTIKE PUTNIKA
  Future<void> _prikaziDetaljneStatistike(RegistrovaniPutnik putnik) async {
    await PutnikStatistikeHelper.prikaziDetaljneStatistike(
      context: context,
      putnikId: putnik.id,
      putnikIme: putnik.putnikIme,
      tip: putnik.tip,
      tipSkole: putnik.tipSkole,
      brojTelefona: putnik.brojTelefona,
      createdAt: putnik.createdAt,
      updatedAt: putnik.updatedAt,
      aktivan: putnik.aktivan,
    );
  }

  Future<void> _sacuvajPlacanje(
    RegistrovaniPutnik putnik,
    double iznos,
    String mesec,
  ) async {
    try {
      // ?? FIX: Koristi IME vozaca, ne UUID
      final currentDriverName = await _getCurrentDriverName();

      // ?? Konvertuj string meseca u datume
      final Map<String, dynamic> datumi = _konvertujMesecUDatume(mesec);

      final uspeh = await _putnikService.upisPlacanjaULog(
        putnikId: putnik.id,
        putnikIme: putnik.putnikIme,
        putnikTabela: putnik.tabela,
        iznos: iznos,
        vozacIme: currentDriverName,
        datum: datumi['pocetakMeseca'] as DateTime,
        placeniMesec: (datumi['pocetakMeseca'] as DateTime).month,
        placenaGodina: (datumi['pocetakMeseca'] as DateTime).year,
      );

      if (uspeh) {
        if (mounted) {
          AppSnackBar.payment(context, '✅ Dodato plaćanje od ${iznos.toStringAsFixed(0)} RSD za $mesec');
        }
      } else {
        if (mounted) {
          AppSnackBar.error(context, 'Greška pri čuvanju plaćanja');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  // ?? HELPER FUNKCIJE ZA MESECE
  String _getCurrentMonthYear() {
    final now = DateTime.now();
    return '${_getMonthName(now.month)} ${now.year}';
  }

  List<String> _getMonthOptions() {
    final now = DateTime.now();
    List<String> options = [];

    // Dodaj svih 12 meseci trenutne godine
    for (int month = 1; month <= 12; month++) {
      final monthYear = '${_getMonthName(month)} ${now.year}';
      options.add(monthYear);
    }

    return options;
  }

  // ?? HELPER: DOBIJ BROJ MESECA IZ IMENA
  int _getMonthNumber(String monthName) {
    const months = [
      '', // 0 - ne postoji
      'Januar', 'Februar', 'Mart', 'April', 'Maj', 'Jun',
      'Jul', 'Avgust', 'Septembar', 'Oktobar', 'Novembar', 'Decembar',
    ];

    for (int i = 1; i < months.length; i++) {
      if (months[i] == monthName) {
        return i;
      }
    }
    return 0; // Ne postoji
  }

  String _getMonthName(int month) {
    const months = [
      '',
      'Januar',
      'Februar',
      'Mart',
      'April',
      'Maj',
      'Jun',
      'Jul',
      'Avgust',
      'Septembar',
      'Oktobar',
      'Novembar',
      'Decembar',
    ];
    return months[month];
  }

  // Helper za konvertovanje meseca u datume
  Map<String, dynamic> _konvertujMesecUDatume(String izabranMesec) {
    // Parsiraj izabrani mesec (format: "Septembar 2025")
    final parts = izabranMesec.split(' ');
    if (parts.length != 2) {
      throw Exception('Neispravno format meseca: $izabranMesec');
    }

    final monthName = parts[0];
    final year = int.tryParse(parts[1]);
    if (year == null) {
      throw Exception('Neispravna godina: ${parts[1]}');
    }

    final monthNumber = _getMonthNumber(monthName);
    if (monthNumber == 0) {
      throw Exception('Neispravno ime meseca: $monthName');
    }

    DateTime pocetakMeseca = DateTime(year, monthNumber);
    DateTime krajMeseca = DateTime(year, monthNumber + 1, 0, 23, 59, 59);

    return {
      'pocetakMeseca': pocetakMeseca,
      'krajMeseca': krajMeseca,
      'mesecBroj': monthNumber,
      'godina': year,
    };
  }

  Future<String> _getCurrentDriverName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ime_vozaca') ?? 'Gavra';
  }
}
