import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../helpers/v2_putnik_statistike_helper.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_permission_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../widgets/v2_pin_dialog.dart';
import '../widgets/v2_putnik_dialog.dart';

class V2PutniciScreen extends StatefulWidget {
  const V2PutniciScreen({super.key});

  @override
  State<V2PutniciScreen> createState() => _V2PutniciScreenState();
}

class _V2PutniciScreenState extends State<V2PutniciScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'svi';

  final _rm = V2MasterRealtimeManager.instance;

  // Master realtime stream — broadcast, reaguje na svaki onCacheChanged event
  final Stream<List<V2RegistrovaniPutnik>> _streamPutnici = V2MasterRealtimeManager.instance.streamAktivniPutnici();

  @override
  void dispose() {
    _searchController.dispose();
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
    return StreamBuilder<List<V2RegistrovaniPutnik>>(
      stream: _streamPutnici,
      builder: (context, snapshot) {
        final sviPutnici = snapshot.data ?? [];
        // Badge-ovi direktno iz cache-a — reaguju na svaki realtime event
        final int brRadnici = _rm.radniciCache.values.where((r) => r['status'] == 'aktivan').length;
        final int brUcenici = _rm.uceniciCache.values.where((r) => r['status'] == 'aktivan').length;
        final int brDnevni = _rm.dnevniCache.values.where((r) => r['status'] == 'aktivan').length;
        final int brPosiljke = _rm.posiljkeCache.values.where((r) => r['status'] == 'aktivan').length;

        return Scaffold(
          extendBodyBehindAppBar: true,
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
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                            child: _putniciiBuildBadge(
                                brRadnici, const Color(0xFF5C9CE6), const Color(0xFF3B7DD8), Colors.blue)),
                      ]),
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
                            child: _putniciiBuildBadge(
                                brUcenici, const Color(0xFF4ECDC4), const Color(0xFF44A08D), Colors.teal)),
                      ]),
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
                            child: _putniciiBuildBadge(
                                brDnevni, const Color(0xFFFF6B6B), const Color(0xFFFF8E53), Colors.red)),
                      ]),
                      Stack(children: [
                        IconButton(
                          icon: Icon(Icons.local_shipping,
                              color: _selectedFilter == 'v2_posiljke' ? Colors.white : Colors.white70,
                              shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                          onPressed: () => setState(
                              () => _selectedFilter = _selectedFilter == 'v2_posiljke' ? 'svi' : 'v2_posiljke'),
                          tooltip: 'Pošiljke',
                        ),
                        Positioned(
                            right: 0,
                            top: 0,
                            child: _putniciiBuildBadge(
                                brPosiljke, const Color(0xFFFF8C00), const Color(0xFFE65C00), Colors.orange)),
                      ]),
                      IconButton(
                        icon: const Icon(Icons.add,
                            color: Colors.white,
                            shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                        onPressed: _pokaziDijalogZaDodavanje,
                        tooltip: 'Dodaj novog putnika',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // SEARCH BAR
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          blurRadius: 10,
                          spreadRadius: 1,
                          offset: const Offset(0, 3),
                        ),
                      ],
                      border: Border.all(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
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

                  // LISTA PUTNIKA — jedan StreamBuilder za cijeli ekran + ValueListenableBuilder za pretragu
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : snapshot.hasError
                            ? const Center(
                                child: Text(
                                  'Greška pri učitavanju putnika',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              )
                            : ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _searchController,
                                builder: (context, searchValue, _) {
                                  final filteredPutnici = _filterPutniciDirect(sviPutnici, searchValue.text);
                                  const int _limit = 50;
                                  final bool isTruncated = filteredPutnici.length > _limit;
                                  final prikazaniPutnici =
                                      isTruncated ? filteredPutnici.sublist(0, _limit) : filteredPutnici;

                                  if (prikazaniPutnici.isEmpty) {
                                    return Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            searchValue.text.isNotEmpty ? Icons.search_off : Icons.group_off,
                                            size: 64,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            searchValue.text.isNotEmpty ? 'Nema rezultata pretrage' : 'Nema putnika',
                                            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                                          ),
                                          if (searchValue.text.isNotEmpty) ...[
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

                                  return Column(
                                    children: [
                                      // Fix #3: Prikaži info ako je lista truncated
                                      if (isTruncated)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                          child: Row(
                                            children: [
                                              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Prikazano $_limit od ${filteredPutnici.length} — precizíraj pretragu',
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Expanded(
                                        child: ListView.builder(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          itemCount: prikazaniPutnici.length,
                                          physics: const AlwaysScrollableScrollPhysics(
                                            parent: BouncingScrollPhysics(),
                                          ),
                                          itemBuilder: (context, index) {
                                            final v2Putnik = prikazaniPutnici[index];
                                            // Fix #4: TweenAnimationBuilder samo za svježe dodane elemente
                                            // key: ValueKey(id) garantuje da se animacija pokreće samo jednom po putnik-u
                                            return TweenAnimationBuilder<double>(
                                              key: ValueKey(v2Putnik.id),
                                              duration: const Duration(milliseconds: 300),
                                              tween: Tween(begin: 0.0, end: 1.0),
                                              curve: Curves.easeOutCubic,
                                              builder: (context, value, child) => Transform.translate(
                                                offset: Offset(0, 20 * (1 - value)),
                                                child: Opacity(opacity: value, child: child),
                                              ),
                                              child: _buildPutnikCard(v2Putnik, index + 1),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPutnikCard(V2RegistrovaniPutnik v2Putnik, int redniBroj) {
    final bool bolovanje = v2Putnik.status == 'bolovanje';

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
                Row(
                  children: [
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
                            'v2_radnici' => const Color(0xFF3B7DD8),
                            'v2_ucenici' => const Color(0xFF44A08D),
                            'v2_dnevni' => const Color(0xFFFF6B6B),
                            'v2_posiljke' => const Color(0xFFE65C00),
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
                              'v2_radnici' => const Color(0xFF3B7DD8),
                              'v2_ucenici' => const Color(0xFF44A08D),
                              'v2_dnevni' => const Color(0xFFFF6B6B),
                              'v2_posiljke' => const Color(0xFFE65C00),
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
                Row(
                  children: [
                    Expanded(
                      child: _putniciiBuildCompactActionButton(
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
                    Expanded(
                      child: _putniciiBuildCompactActionButton(
                        onPressed: () => _prikaziDetaljneStatistike(v2Putnik),
                        icon: Icons.analytics_outlined,
                        label: 'Detalji',
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (v2Putnik.telefon != null || v2Putnik.telefonOca != null || v2Putnik.telefonMajke != null) ...[
                      Expanded(
                        child: _putniciiBuildCompactActionButton(
                          onPressed: () => _pokaziKontaktOpcije(v2Putnik),
                          icon: Icons.phone,
                          label: 'Pozovi',
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: _putniciiBuildCompactActionButton(
                        onPressed: () => _editPutnik(v2Putnik),
                        icon: Icons.edit_outlined,
                        label: 'Uredi',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _putniciiBuildCompactActionButton(
                        onPressed: () => _showPinDialog(v2Putnik),
                        icon: Icons.lock_outline,
                        label: 'PIN',
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _putniciiBuildCompactActionButton(
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
              tileColor: Colors.teal.withValues(alpha: 0.07),
              onTap: () => Navigator.pop(ctx, 'godisnji'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.medical_services_outlined, color: Colors.orange),
              title: const Text('Bolovanje'),
              subtitle: const Text('Putnik je na bolovanju'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.orange.withValues(alpha: 0.07),
              onTap: () => Navigator.pop(ctx, 'bolovanje'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.pause_circle_outline, color: Colors.grey),
              title: const Text('Neaktivan'),
              subtitle: const Text('Privremeno deaktiviran'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.grey.withValues(alpha: 0.07),
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
      await _rm.v2UpdatePutnik(
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
        V2AppSnackBar.success(context, poruka);
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, '❌ Greška pri promeni statusa');
      }
    }
  }

  void _editPutnik(V2RegistrovaniPutnik v2Putnik) {
    showDialog(
      context: context,
      builder: (dialogCtx) => V2PutnikDialog(
        existingPutnik: v2Putnik,
        // Ne resetujemo filter/pretragu — korisnik ostaje u svom kontekstu
        onSaved: () {},
      ),
    );
  }

  /// Prikaži PIN dijalog za putnika
  void _showPinDialog(V2RegistrovaniPutnik v2Putnik) {
    showDialog(
      context: context,
      builder: (dialogCtx) => V2PinDialog(
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
      builder: (dialogCtx) => V2PutnikDialog(
        existingPutnik: null,
        // Realtime će automatski dodati novog putnika u stream — nema potrebe za setState
        onSaved: () {},
      ),
    );
  }

  Future<void> _obrisiPutnika(V2RegistrovaniPutnik v2Putnik) async {
    // Pokaži potvrdu za brisanje
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
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
                color: Theme.of(dialogCtx).colorScheme.primaryContainer.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(dialogCtx).colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info,
                        color: Theme.of(dialogCtx).colorScheme.primary,
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
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Otkaži'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Obriši', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (potvrda != true || !mounted) return;
    try {
      final success = await _rm.v2DeletePutnik(v2Putnik.id, v2Putnik.v2Tabela);

      if (success && mounted) {
        V2AppSnackBar.success(context, '${v2Putnik.ime} je uspešno obrisan');
      } else if (mounted) {
        V2AppSnackBar.error(context, '❌ Greška pri brisanju putnika');
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }

  // Prikazi kontakt opcije za putnika
  Future<void> _pokaziKontaktOpcije(V2RegistrovaniPutnik v2Putnik) async {
    final imaKontakt = v2Putnik.telefon?.isNotEmpty == true ||
        v2Putnik.telefonOca?.isNotEmpty == true ||
        v2Putnik.telefonMajke?.isNotEmpty == true;

    if (!imaKontakt) {
      V2AppSnackBar.info(context, 'Nema dostupnih kontakata');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kontaktiraj ${v2Putnik.ime}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              if (v2Putnik.telefon?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: const Text('Pozovi putnika'),
                  subtitle: Text(v2Putnik.telefon!),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await _pozovi(v2Putnik.telefon!);
                  },
                ),
              if (v2Putnik.telefonOca?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.man, color: Colors.blue),
                  title: const Text('Pozovi oca'),
                  subtitle: Text(v2Putnik.telefonOca!),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await _pozovi(v2Putnik.telefonOca!);
                  },
                ),
              if (v2Putnik.telefonMajke?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.woman, color: Colors.pink),
                  title: const Text('Pozovi majku'),
                  subtitle: Text(v2Putnik.telefonMajke!),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await _pozovi(v2Putnik.telefonMajke!);
                  },
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(sheetCtx),
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
      final hasPermission = await V2PermissionService.ensurePhonePermissionHuawei();
      if (!mounted) return;
      if (!hasPermission) {
        V2AppSnackBar.error(context, '❌ Dozvola za pozive je potrebna');
        return;
      }
      await launchUrl(Uri.parse('tel:$brojTelefona'), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška pri pozivanju: $e');
    }
  }

  Future<void> _prikaziDetaljneStatistike(V2RegistrovaniPutnik v2Putnik) async {
    await V2PutnikStatistikeHelper.prikaziDetaljneStatistike(
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
}

// ─── Top-level helpers ────────────────────────────────────────────────────────

Widget _putniciiBuildBadge(int count, Color c1, Color c2, Color shadow) {
  if (count == 0) return const SizedBox.shrink();
  return Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [c1, c2]),
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: shadow.withValues(alpha: 0.5), blurRadius: 4, offset: const Offset(0, 2))],
    ),
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
    ),
  );
}

Widget _putniciiBuildCompactActionButton({
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
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
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
