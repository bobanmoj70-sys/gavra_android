import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_translations.dart';
import '../models/v3_vozac.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
import '../utils/v3_card_color_policy.dart';

// Deljeni prevodi za ekran pozicije vozača (SR/EN/RU/DE/ZH).
class _VozacPozTr {
  _VozacPozTr._();

  static final Map<String, Map<String, String>> _t = AppTranslations.ns('vozacPozicijaScreen');

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

/// Admin ekran — prikazuje poslednju poznatu GPS poziciju vozača, na
/// besplatnoj OpenStreetMap mapi (bez API ključa, bez naplate).
///
/// Podrazumevano (opcija "Svi vozači") prikazuje markere SVIH vozača koji
/// trenutno imaju lokaciju u tabeli v3_vozac_location. Preko dropdown-a admin
/// može da izabere jednog konkretnog vozača — tada se mapa fokusira i prikazuje
/// samo njegov marker.
///
/// Lokacija se čita iz tabele v3_vozac_location (jedan red po vozaču,
/// ažurira se svakih 20s). Ekran periodično osvežava podatke.
class V3AdminVozacPozicijaScreen extends StatefulWidget {
  const V3AdminVozacPozicijaScreen({super.key});

  @override
  State<V3AdminVozacPozicijaScreen> createState() => _V3AdminVozacPozicijaScreenState();
}

/// null = opcija "Svi vozači" (default).
class _V3AdminVozacPozicijaScreenState extends State<V3AdminVozacPozicijaScreen> {
  List<V3Vozac> _vozaci = [];
  String? _selectedVozacId;

  final Map<String, ll.LatLng> _pozicije = {};
  final Map<String, DateTime> _lastUpdates = {};

  Timer? _refreshTimer;
  bool _isLoading = false;

  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _vozaci = V3VozacService.getAllVozaci();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final rows = await Supabase.instance.client.from('v3_vozac_location').select('vozac_id, lat, lng, updated_at');

      final newPozicije = <String, ll.LatLng>{};
      final newUpdates = <String, DateTime>{};
      for (final row in rows as List<dynamic>) {
        final vozacId = row['vozac_id']?.toString();
        final lat = (row['lat'] as num?)?.toDouble();
        final lng = (row['lng'] as num?)?.toDouble();
        final updatedAt = row['updated_at']?.toString();
        if (vozacId == null || lat == null || lng == null) continue;
        newPozicije[vozacId] = ll.LatLng(lat, lng);
        final parsed = updatedAt != null ? DateTime.tryParse(updatedAt) : null;
        newUpdates[vozacId] = parsed ?? DateTime.now();
      }

      if (!mounted) return;
      setState(() {
        _pozicije
          ..clear()
          ..addAll(newPozicije);
        _lastUpdates
          ..clear()
          ..addAll(newUpdates);
      });

      if (_selectedVozacId != null && _pozicije.containsKey(_selectedVozacId) && _mapReady) {
        _mapController.move(_pozicije[_selectedVozacId]!, 15);
      } else if (_selectedVozacId == null && _pozicije.length == 1 && _mapReady) {
        _mapController.move(_pozicije.values.first, 15);
      }
    } catch (e) {
      debugPrint('[AdminVozacPozicija] greška pri učitavanju lokacija: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectVozac(String? vozacId) {
    setState(() => _selectedVozacId = vozacId);
    if (vozacId == null) return;
    final pozicija = _pozicije[vozacId];
    if (pozicija != null && _mapReady) {
      _mapController.move(pozicija, 15);
    }
  }

  /// Vozači koji se trenutno prikazuju kao marker na mapi (imaju lokaciju),
  /// filtrirani po izboru u dropdown-u.
  List<V3Vozac> get _prikazaniVozaci {
    final aktivni = _vozaci.where((v) => _pozicije.containsKey(v.id));
    if (_selectedVozacId == null) return aktivni.toList();
    return aktivni.where((v) => v.id == _selectedVozacId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final prikazaniVozaci = _prikazaniVozaci;
    final brojAktivnih = _pozicije.length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(_VozacPozTr.tr('naslov')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              value: _selectedVozacId,
              decoration: InputDecoration(
                labelText: _VozacPozTr.tr('izaberiVozaca'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('🌍 ${_VozacPozTr.tr('sviVozaci')} ($brojAktivnih)'),
                ),
                ..._vozaci.map((v) => DropdownMenuItem<String>(
                      value: v.id,
                      child: Text(
                        _pozicije.containsKey(v.id) ? '${v.imePrezime} 🟢' : v.imePrezime,
                      ),
                    )),
              ],
              onChanged: _selectVozac,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  prikazaniVozaci.isNotEmpty ? Icons.gps_fixed : Icons.gps_not_fixed,
                  size: 16,
                  color: prikazaniVozaci.isNotEmpty ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    prikazaniVozaci.isEmpty
                        ? _VozacPozTr.tr('cekaSePozicija')
                        : _selectedVozacId != null && _lastUpdates[_selectedVozacId] != null
                            ? '${_VozacPozTr.tr('azurirano')}: ${_formatTime(_lastUpdates[_selectedVozacId]!)}'
                            : '${_VozacPozTr.tr('aktivnihVozaca')}: $brojAktivnih',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const ll.LatLng(44.7866, 20.4489), // Beograd default
                initialZoom: 12,
                onMapReady: () => _mapReady = true,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.gavra013.app',
                ),
                MarkerLayer(
                  markers: [
                    for (final vozac in prikazaniVozaci)
                      Marker(
                        point: _pozicije[vozac.id]!,
                        width: 140,
                        height: 64,
                        alignment: Alignment.bottomCenter,
                        child: _VozacMarker(
                          boja: V3CardColorPolicy.vozacColorOr(vozac.boja),
                          ime: vozac.imePrezime,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// Marker na mapi: pin u boji vozača + balončić sa imenom iznad njega.
class _VozacMarker extends StatelessWidget {
  const _VozacMarker({required this.boja, required this.ime});

  final Color boja;
  final String ime;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ime.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: boja, width: 1.5),
            ),
            child: Text(
              ime,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 2),
        Icon(Icons.location_on, color: boja, size: 40, shadows: const [
          Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54),
        ]),
      ],
    );
  }
}
