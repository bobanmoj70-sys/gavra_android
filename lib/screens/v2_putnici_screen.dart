import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';
import '../helpers/v2_putnik_statistike_helper.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_permission_service.dart';
import '../services/v2_polasci_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_vozac_cache.dart';
import '../widgets/v2_pin_dialog.dart';
import '../widgets/v2_putnik_dialog.dart';

// HELPER EXTENSION za Set poredenje
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
  String _selectedFilter = 'svi';

  // V2 servis - koristi V2MasterRealtimeManager za write ops, V2PutnikStatistikaService za placanja
  final _rm = V2MasterRealtimeManager.instance;

  // Master realtime stream — inicijalizovan jednom u initState()
  late final Stream<List<V2RegistrovaniPutnik>> _streamPutnici;

  // Mapa placenih meseci po putniku
  Map<String, Set<String>> _placeniMeseci = {};

  // BADGE COUNTERS
  int _brojRadnika = 0;
  int _brojUcenika = 0;
  int _brojDnevnih = 0;
  int _brojPosiljki = 0;

  // PLACANJE STATE
  Map<String, double> _stvarnaPlacanja = {};
  DateTime? _lastPaymentUpdate;
  Set<String> _lastPutnikIds = {};
  Timer? _paymentUpdateDebounceTimer; // ⏱ DEBOUNCE TIMER za payment updates

  @override
  void initState() {
    super.initState();
    _streamPutnici = _rm.streamAktivniPutnici();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  // BATCH UCITAVANJE
  Future<void> _ucitajSvePodatke(List<V2RegistrovaniPutnik> putnici) async {
    if (putnici.isEmpty) return;

    try {
      await _ucitajStvarnaPlacanja(putnici);
    } catch (e) {
      debugPrint('🔴 [RegistrovaniPutnici._ucitajSvePodatke] Error: $e');
    }
  }

  // UCITAJ STVARNA PLACANJA — batch query (1 DB upit) + dopuna iz statistikaCache
  Future<void> _ucitajStvarnaPlacanja(List<V2RegistrovaniPutnik> putnici) async {
    try {
      if (putnici.isEmpty) return;

      final Map<String, double> placanja = {};
      final Map<String, Set<String>> placeniMeseciMap = {};

      // Inicijalizuj prazne mape za sve putnike
      for (final p in putnici) {
        placanja[p.id] = 0.0;
        placeniMeseciMap[p.id] = {};
      }

      final putnikIds = putnici.map((p) => p.id).toList();

      // 1 Iz statistikaCache (danas, 0 DB) — dopuni plaćanja tekućeg dana
      final rm = V2MasterRealtimeManager.instance;
      for (final row in rm.statistikaCache.values) {
        final putnikId = row['putnik_id'] as String?;
        if (putnikId == null || !placanja.containsKey(putnikId)) continue;
        final tip = row['tip'] as String?;
        if (!['uplata', 'uplata_mesecna', 'uplata_dnevna'].contains(tip)) continue;
        final mesec = row['placeni_mesec'];
        final godina = row['placena_godina'];
        if (mesec != null && godina != null) {
          placeniMeseciMap[putnikId]!.add('$mesec-$godina');
        }
        final iznos = (row['iznos'] as num?)?.toDouble() ?? 0.0;
        if (iznos > placanja[putnikId]!) placanja[putnikId] = iznos;
      }

      // 2 Jedan batch DB upit za historijska plaćanja (svi putnici odjednom)
      try {
        final histRows = await supabase
            .from('v2_statistika_istorija')
            .select('putnik_id, iznos, placeni_mesec, placena_godina')
            .inFilter('putnik_id', putnikIds)
            .inFilter('tip', ['uplata', 'uplata_mesecna', 'uplata_dnevna'])
            .not('placeni_mesec', 'is', null)
            .not('placena_godina', 'is', null)
            .order('datum', ascending: false);

        for (final row in histRows) {
          final putnikId = row['putnik_id'] as String?;
          if (putnikId == null || !placanja.containsKey(putnikId)) continue;
          final mesec = row['placeni_mesec'];
          final godina = row['placena_godina'];
          if (mesec != null && godina != null) {
            placeniMeseciMap[putnikId]!.add('$mesec-$godina');
          }
          final iznos = (row['iznos'] as num?)?.toDouble() ?? 0.0;
          if (iznos > placanja[putnikId]!) placanja[putnikId] = iznos;
        }
      } catch (e) {
      debugPrint('[V2PutniciScreen] Error: $e');
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
    _paymentUpdateDebounceTimer?.cancel();

    // TEXTCONTROLLER CLEANUP
    try {
      _searchController.dispose();
    } catch (e) {
      // ignore controller dispose errors
    }

    super.dispose();
  }

  List<V2RegistrovaniPutnik> _filterPutniciDirect(
    List<V2RegistrovaniPutnik> putnici,
    String searchTerm,
  ) {
    var filtered = putnici;

    // Filter po tipu
    if (_selectedFilter != 'svi') {
      filtered = filtered.where((p) => p.v2Tabela == _selectedFilter).toList();
    }

    // Filter po search term
    if (searchTerm.isNotEmpty) {
      final searchLower = searchTerm.toLowerCase();
      filtered = filtered.where((p) {
        return p.ime.toLowerCase().contains(searchLower) || p.v2Tabela.toLowerCase().contains(searchLower);
      }).toList();
    }

    // ?? BINARYBITCH SORTING BLADE: A Ž (Serbian alphabet), neaktivni/godisnji/bolovanje na dno
    filtered.sort((a, b) {
      final aAktivan = a.status == 'aktivan';
      final bAktivan = b.status == 'aktivan';
      if (aAktivan != bAktivan) return aAktivan ? -1 : 1;
      return a.ime.toLowerCase().compareTo(b.ime.toLowerCase());
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
                    // Radnici
                    Stack(children: [
                      IconButton(
                        icon: Icon(Icons.engineering,
                            color: _selectedFilter == 'v2_radnici' ? Colors.white : Colors.white70,
                            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                        onPressed: () =>
                            setState(() => _selectedFilter = _selectedFilter == 'v2_radnici' ? 'svi' : 'v2_radnici'),
                        tooltip: 'Radnici',
                      ),
                      Positioned(
                          right: 0,
                          top: 0,
                          child:
                              _buildBadge(_brojRadnika, const Color(0xFFFF6B6B), const Color(0xFFFF8E53), Colors.red)),
                    ]),
                    // Učenici
                    Stack(children: [
                      IconButton(
                        icon: Icon(Icons.school,
                            color: _selectedFilter == 'v2_ucenici' ? Colors.white : Colors.white70,
                            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                        onPressed: () =>
                            setState(() => _selectedFilter = _selectedFilter == 'v2_ucenici' ? 'svi' : 'v2_ucenici'),
                        tooltip: 'Učenici',
                      ),
                      Positioned(
                          right: 0,
                          top: 0,
                          child:
                              _buildBadge(_brojUcenika, const Color(0xFF4ECDC4), const Color(0xFF44A08D), Colors.teal)),
                    ]),
                    // Dnevni
                    Stack(children: [
                      IconButton(
                        icon: Icon(Icons.today,
                            color: _selectedFilter == 'v2_dnevni' ? Colors.white : Colors.white70,
                            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                        onPressed: () =>
                            setState(() => _selectedFilter = _selectedFilter == 'v2_dnevni' ? 'svi' : 'v2_dnevni'),
                        tooltip: 'Dnevni',
                      ),
                      Positioned(
                          right: 0,
                          top: 0,
                          child:
                              _buildBadge(_brojDnevnih, const Color(0xFF5C9CE6), const Color(0xFF3B7DD8), Colors.blue)),
                    ]),
                    // Pošiljke
                    Stack(children: [
                      IconButton(
                        icon: Icon(Icons.local_shipping,
                            color: _selectedFilter == 'v2_posiljke' ? Colors.white : Colors.white70,
                            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                        onPressed: () =>
                            setState(() => _selectedFilter = _selectedFilter == 'v2_posiljke' ? 'svi' : 'v2_posiljke'),
                        tooltip: 'Pošiljke',
                      ),
                      Positioned(
                          right: 0,
                          top: 0,
                          child: _buildBadge(
                              _brojPosiljki, const Color(0xFFFF8C00), const Color(0xFFE65C00), Colors.orange)),
                    ]),
                    IconButton(
                      icon: const Icon(Icons.add,
                          color: Colors.white,
                          shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
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

            // LISTA PUTNIKA — master realtime cache stream
            Expanded(
              child: StreamBuilder<List<V2RegistrovaniPutnik>>(
                stream: _streamPutnici,
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

                  // Badge counteri — lokalno izračunati, bez mutiranja State fielda
                  final brojRadnika = sviPutnici.where((p) => p.v2Tabela == 'v2_radnici').length;
                  final brojUcenika = sviPutnici.where((p) => p.v2Tabela == 'v2_ucenici').length;
                  final brojDnevnih = sviPutnici.where((p) => p.v2Tabela == 'v2_dnevni').length;
                  final brojPosiljki = sviPutnici.where((p) => p.v2Tabela == 'v2_posiljke').length;
                  // Sinhrono ažuriranje State fielda ako su se promijenili
                  if (_brojRadnika != brojRadnika ||
                      _brojUcenika != brojUcenika ||
                      _brojDnevnih != brojDnevnih ||
                      _brojPosiljki != brojPosiljki) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted)
                        setState(() {
                          _brojRadnika = brojRadnika;
                          _brojUcenika = brojUcenika;
                          _brojDnevnih = brojDnevnih;
                          _brojPosiljki = brojPosiljki;
                        });
                    });
                  }

                  // Filtriraj lokalno
                  final filteredPutnici = _filterPutniciDirect(
                    sviPutnici,
                    _searchController.text,
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
                          _ucitajSvePodatke(filteredPutnici);
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
                      final v2Putnik = prikazaniPutnici[index];
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(v2Putnik.id),
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
                        child: _buildPutnikCard(v2Putnik, index + 1),
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

  Widget _buildBadge(int count, Color c1, Color c2, Color shadow) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2]),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: shadow.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPutnikCard(V2RegistrovaniPutnik v2Putnik, int redniBroj) {
    final bool bolovanje = v2Putnik.status == 'bolovanje';
    // Sačuvaj sva vremena po danima (pon -> pet) i prikaži ih na kartici.
    // Prethodna logika je prikazivala samo PRVI dan koji je imao vreme.
    // Sada prikazujemo sve dane koji imaju bar jedan polazak (BC i/ili VS)
    final List<String> _daniOrder = ['pon', 'uto', 'sre', 'cet', 'pet'];

    // neaktivan vizualno: sve osim 'aktivan'
    final bool neaktivan = v2Putnik.status != 'aktivan';

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
            gradient: switch (v2Putnik.status) {
              'bolovanje' => LinearGradient(
                  colors: [Colors.orange[50]!, Colors.amber[50]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              'godisnji' => LinearGradient(
                  colors: [Colors.teal[50]!, Colors.cyan[50]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              'neaktivan' => LinearGradient(
                  colors: [Colors.grey[200]!, Colors.grey[300]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              _ => LinearGradient(
                  colors: [Colors.white, Colors.grey[50]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
            },
            border: Border.all(
              color: switch (v2Putnik.status) {
                'bolovanje' => Colors.orange[200]!,
                'godisnji' => Colors.teal[200]!,
                'neaktivan' => Colors.grey[400]!,
                _ => Colors.grey[200]!,
              },
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ?? HEADER - Ime, broj, tip
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
                              v2Putnik.ime,
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
                    // Tip putnika - skroz desno
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          switch (v2Putnik.v2Tabela) {
                            'v2_radnici' => Icons.engineering,
                            'v2_ucenici' => Icons.school,
                            'v2_dnevni' => Icons.today,
                            'v2_posiljke' => Icons.local_shipping,
                            _ => Icons.person,
                          },
                          size: 14,
                          color: switch (v2Putnik.v2Tabela) {
                            'v2_radnici' => Colors.blue.shade600,
                            'v2_ucenici' => Colors.green.shade600,
                            'v2_dnevni' => Colors.orange.shade600,
                            'v2_posiljke' => Colors.deepOrange.shade600,
                            _ => Colors.grey.shade600,
                          },
                        ),
                        const SizedBox(width: 3),
                        Text(
                          switch (v2Putnik.v2Tabela) {
                            'v2_radnici' => 'RADNIK',
                            'v2_ucenici' => 'UCENIK',
                            'v2_dnevni' => 'DNEVNI',
                            'v2_posiljke' => 'POSILJKA',
                            _ => v2Putnik.v2Tabela.toUpperCase(),
                          },
                          style: TextStyle(
                            color: switch (v2Putnik.v2Tabela) {
                              'v2_radnici' => Colors.blue.shade700,
                              'v2_ucenici' => Colors.green.shade700,
                              'v2_dnevni' => Colors.orange.shade700,
                              'v2_posiljke' => Colors.deepOrange.shade700,
                              _ => Colors.grey.shade700,
                            },
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ?? OSNOVNE INFORMACIJE - adresa
                if (v2Putnik.adresa != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          v2Putnik.adresa!,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // ??? PLACANJE I STATISTIKE - jednaki elementi u redu

                Row(
                  children: [
                    // ?? DUGME ZA PLACANJE
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _prikaziPlacanje(v2Putnik),
                        icon: (_stvarnaPlacanja[v2Putnik.id] ?? 0) > 0
                            ? Icons.check_circle_outline
                            : Icons.payments_outlined,
                        label: (_stvarnaPlacanja[v2Putnik.id] ?? 0) > 0
                            ? '${(_stvarnaPlacanja[v2Putnik.id]!).toStringAsFixed(0)} RSD'
                            : 'Plati',
                        color: (_stvarnaPlacanja[v2Putnik.id] ?? 0) > 0 ? Colors.green : Colors.purple,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ?? TOGGLE AKTIVNOST
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _toggleAktivnost(v2Putnik),
                        icon: switch (v2Putnik.status) {
                          'aktivan' => Icons.toggle_on_outlined,
                          'neaktivan' => Icons.toggle_off_outlined,
                          'godisnji' => Icons.beach_access_outlined,
                          'bolovanje' => Icons.medical_services_outlined,
                          _ => Icons.toggle_off_outlined,
                        },
                        label: switch (v2Putnik.status) {
                          'aktivan' => 'Aktivan',
                          'neaktivan' => 'Neaktivan',
                          'godisnji' => 'Godišnji',
                          'bolovanje' => 'Bolovanje',
                          _ => v2Putnik.status,
                        },
                        color: switch (v2Putnik.status) {
                          'aktivan' => Colors.green,
                          'neaktivan' => Colors.grey,
                          'godisnji' => Colors.teal,
                          'bolovanje' => Colors.orange,
                          _ => Colors.grey,
                        },
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ?? DUGME ZA DETALJE
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _prikaziDetaljneStatistike(v2Putnik),
                        icon: Icons.analytics_outlined,
                        label: 'Detalji',
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ??? ACTION BUTTONS - samo najvažnije
                Row(
                  children: [
                    // Pozovi (ako ima bilo koji telefon)
                    if (v2Putnik.telefon != null || v2Putnik.telefonOca != null || v2Putnik.telefonMajke != null) ...[
                      Expanded(
                        child: _buildCompactActionButton(
                          onPressed: () => _pokaziKontaktOpcije(v2Putnik),
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
                        onPressed: () => _editPutnik(v2Putnik),
                        icon: Icons.edit_outlined,
                        label: 'Uredi',
                        color: Colors.blue,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ?? PIN
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _showPinDialog(v2Putnik),
                        icon: Icons.lock_outline,
                        label: 'PIN',
                        color: Colors.amber,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Obriši
                    Expanded(
                      child: _buildCompactActionButton(
                        onPressed: () => _obrisiPutnika(v2Putnik),
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
    required VoidCallback? onPressed,
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

  Future<void> _toggleAktivnost(V2RegistrovaniPutnik v2Putnik) async {
    // Ako nije aktivan → odmah vrati na aktivan
    if (!v2Putnik.aktivan) {
      await _postaviStatus(v2Putnik, 'aktivan');
      return;
    }

    // Ako je aktivan → prikaži izbor
    if (!mounted) return;
    final odabrani = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              v2Putnik.ime,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Promeni status putnika',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.beach_access_outlined, color: Colors.teal),
              title: const Text('Godišnji odmor'),
              subtitle: const Text('Putnik je na godišnjem'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.teal.withOpacity(0.07),
              onTap: () => Navigator.pop(ctx, 'godisnji'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.medical_services_outlined, color: Colors.orange),
              title: const Text('Bolovanje'),
              subtitle: const Text('Putnik je na bolovanju'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.orange.withOpacity(0.07),
              onTap: () => Navigator.pop(ctx, 'bolovanje'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.pause_circle_outline, color: Colors.grey),
              title: const Text('Neaktivan'),
              subtitle: const Text('Privremeno deaktiviran'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.grey.withOpacity(0.07),
              onTap: () => Navigator.pop(ctx, 'neaktivan'),
            ),
          ],
        ),
      ),
    );

    if (odabrani != null) {
      await _postaviStatus(v2Putnik, odabrani);
    }
  }

  Future<void> _postaviStatus(V2RegistrovaniPutnik v2Putnik, String noviStatus) async {
    try {
      await _rm.updatePutnik(
        v2Putnik.id,
        {'status': noviStatus},
        v2Putnik.v2Tabela,
      );
      if (mounted) {
        final poruka = switch (noviStatus) {
          'aktivan' => '${v2Putnik.ime} je aktiviran',
          'neaktivan' => '${v2Putnik.ime} je deaktiviran',
          'godisnji' => '${v2Putnik.ime} je na godišnjem',
          'bolovanje' => '${v2Putnik.ime} je na bolovanju',
          _ => 'Status promenjen',
        };
        AppSnackBar.success(context, poruka);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška pri promeni statusa');
      }
    }
  }

  void _editPutnik(V2RegistrovaniPutnik v2Putnik) {
    showDialog(
      context: context,
      builder: (context) => V2PutnikDialog(
        existingPutnik: v2Putnik,
        onSaved: () {
          if (mounted) {
            setState(() {
              _selectedFilter = 'svi';
              _searchController.clear();
            });
          }
        },
      ),
    );
  }

  /// ?? Prikaži PIN dijalog za putnika
  void _showPinDialog(V2RegistrovaniPutnik v2Putnik) {
    showDialog(
      context: context,
      builder: (context) => V2PinDialog(
        putnikId: v2Putnik.id,
        putnikIme: v2Putnik.ime,
        putnikTabela: v2Putnik.v2Tabela,
        trenutniPin: v2Putnik.pin,
        brojTelefona: v2Putnik.telefon,
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
              _selectedFilter = 'svi';
              _searchController.clear();
            });
          }
        },
      ),
    );
  }

  void _obrisiPutnika(V2RegistrovaniPutnik v2Putnik) async {
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
              'Da li ste sigurni da želite da obrišete putnika "${v2Putnik.ime}"?',
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
                  const Text('• v2Putnik će biti TRAJNO obrisan iz baze'),
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
        final success = await _rm.deletePutnik(v2Putnik.id, v2Putnik.v2Tabela);

        if (success && mounted) {
          AppSnackBar.success(context, '${v2Putnik.ime} je uspešno obrisan');
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
  // ??????????? NOVA FUNKCIJA - Prikazuje sve dostupne kontakte
  Future<void> _pokaziKontaktOpcije(V2RegistrovaniPutnik v2Putnik) async {
    final List<Widget> opcije = [];

    // Glavni broj telefona
    if (v2Putnik.telefon != null && v2Putnik.telefon!.isNotEmpty) {
      opcije.add(
        ListTile(
          leading: const Icon(Icons.person, color: Colors.green),
          title: const Text('Pozovi putnika'),
          subtitle: Text(v2Putnik.telefon!),
          onTap: () async {
            Navigator.pop(context);
            await _pozovi(v2Putnik.telefon!);
          },
        ),
      );
    }

    // Otac
    if (v2Putnik.telefonOca != null && v2Putnik.telefonOca!.isNotEmpty) {
      opcije.add(
        ListTile(
          leading: const Icon(Icons.man, color: Colors.blue),
          title: const Text('Pozovi oca'),
          subtitle: Text(v2Putnik.telefonOca!),
          onTap: () async {
            Navigator.pop(context);
            await _pozovi(v2Putnik.telefonOca!);
          },
        ),
      );
    }

    // Majka
    if (v2Putnik.telefonMajke != null && v2Putnik.telefonMajke!.isNotEmpty) {
      opcije.add(
        ListTile(
          leading: const Icon(Icons.woman, color: Colors.pink),
          title: const Text('Pozovi majku'),
          subtitle: Text(v2Putnik.telefonMajke!),
          onTap: () async {
            Navigator.pop(context);
            await _pozovi(v2Putnik.telefonMajke!);
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
                'Kontaktiraj ${v2Putnik.ime}',
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
  Future<void> _prikaziPlacanje(V2RegistrovaniPutnik v2Putnik) async {
    if (!mounted) return;

    final TextEditingController iznosController = TextEditingController();
    try {
      await _prikaziPlacanjeDialog(v2Putnik, iznosController);
    } finally {
      iznosController.dispose();
    }
  }

  Future<void> _prikaziPlacanjeDialog(
    V2RegistrovaniPutnik v2Putnik,
    TextEditingController iznosController,
  ) async {
    if (!mounted) return;
    String selectedMonth = _getCurrentMonthYear(); // Default current month

    // ?? FIX: Ucitaj stvarni ukupni iznos iz baze
    final ukupnoPlaceno = await V2PutnikStatistikaService.dohvatiUkupnoPlaceno(v2Putnik.id);

    // Default cena po danu za input field
    final cenaPoDanu = CenaObracunService.getCenaPoDanu(v2Putnik);
    iznosController.text = cenaPoDanu.toStringAsFixed(0);

    final tipLower = v2Putnik.v2Tabela;
    final imeLower = v2Putnik.ime.toLowerCase();

    // ?? FIKSNE CENE (Vozaci/Admini prate isti standard)
    final jeZubi = tipLower == 'v2_posiljke' && imeLower.contains('zubi');
    final jePosiljka = tipLower == 'v2_posiljke';
    final jeDnevni = tipLower == 'v2_dnevni';
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
                      jeFiksna ? 'Fiksna naplata - ${v2Putnik.ime}' : 'Placanje - ${v2Putnik.ime}',
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
                                      // ?? Posjednje plaćanje — FutureBuilder (jednom, ne na svakom rebuildu)
                                      FutureBuilder<Map<String, dynamic>?>(
                                        future: V2PutnikStatistikaService.dohvatiPlacanja(v2Putnik.id)
                                            .then((lista) => lista.isNotEmpty ? lista.first : null),
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
                                                    color: V2VozacCache.getColor(
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
                                                    color: V2VozacCache.getColor(
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
                    _prikaziDetaljneStatistike(v2Putnik); // Otvori statistike
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
                      await _sacuvajPlacanje(v2Putnik, iznos, selectedMonth);
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
  Future<void> _prikaziDetaljneStatistike(V2RegistrovaniPutnik v2Putnik) async {
    await PutnikStatistikeHelper.prikaziDetaljneStatistike(
      context: context,
      putnikId: v2Putnik.id,
      putnikIme: v2Putnik.ime,
      tip: v2Putnik.v2Tabela,
      tipSkole: null,
      brojTelefona: v2Putnik.telefon,
      createdAt: v2Putnik.createdAt,
      updatedAt: v2Putnik.updatedAt,
      aktivan: v2Putnik.aktivan,
    );
  }

  Future<void> _sacuvajPlacanje(
    V2RegistrovaniPutnik v2Putnik,
    double iznos,
    String mesec,
  ) async {
    try {
      // ?? FIX: Koristi IME vozaca, ne UUID
      final currentDriverName = await _getCurrentDriverName();

      // ?? Konvertuj string meseca u datume
      final Map<String, dynamic> datumi = _konvertujMesecUDatume(mesec);

      final uspeh = await V2PutnikStatistikaService.upisPlacanjaULog(
        putnikId: v2Putnik.id,
        putnikIme: v2Putnik.ime,
        putnikTabela: v2Putnik.v2Tabela,
        iznos: iznos,
        vozacIme: currentDriverName,
        datum: DateTime.now(),
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
