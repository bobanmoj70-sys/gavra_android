import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../config/app_platform.dart';
import '../l10n/app_translations.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
import '../utils/v3_belgrade_time.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_input_utils.dart';

// Deljeni prevodi za ekran pozicije vozača (SR/EN/RU/DE/ZH).
class _VozacPozTr {
  _VozacPozTr._();

  static final Map<String, Map<String, String>> _t = AppTranslations.ns('vozacPozicijaScreen');

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

/// Admin ekran — poslednja GPS pozicija vozača na OSM mapi.
///
/// Izvor: `V3MasterRealtimeManager.vozacLocationCache` (bootstrap + realtime).
/// Bez periodičnog poll-a ka Supabase-u.
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

  /// km/h; null = GPS nije poslao validan speed.
  final Map<String, double?> _brzine = {};

  StreamSubscription<int>? _locationSub;
  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _vozaci = V3VozacService.getAllVozaci();
    _applyCacheToState(moveMap: false);
    _locationSub = V3MasterRealtimeManager.instance.tableRevisionStream('v3_vozac_location').listen((_) {
      if (!mounted) return;
      _applyCacheToState(moveMap: true);
    });
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  void _applyCacheToState({required bool moveMap}) {
    final cache = V3MasterRealtimeManager.instance.vozacLocationCache;
    final newPozicije = <String, ll.LatLng>{};
    final newUpdates = <String, DateTime>{};
    final newBrzine = <String, double?>{};

    for (final entry in cache.entries) {
      final row = entry.value;
      final vozacId = row['vozac_id']?.toString() ?? entry.key;
      final lat = (row['lat'] as num?)?.toDouble();
      final lng = (row['lng'] as num?)?.toDouble();
      if (vozacId.isEmpty || lat == null || lng == null) continue;
      newPozicije[vozacId] = ll.LatLng(lat, lng);
      final parsed = V3BelgradeTime.parseTs(row['updated_at']?.toString());
      newUpdates[vozacId] = parsed ?? V3BelgradeTime.now();
      final speedRaw = row['speed_kmh'];
      newBrzine[vozacId] = speedRaw is num ? speedRaw.toDouble() : null;
    }

    setState(() {
      _pozicije
        ..clear()
        ..addAll(newPozicije);
      _lastUpdates
        ..clear()
        ..addAll(newUpdates);
      _brzine
        ..clear()
        ..addAll(newBrzine);
      // Ako se lista vozača popuni kasnije iz auth cache-a.
      if (_vozaci.isEmpty) {
        _vozaci = V3VozacService.getAllVozaci();
      }
    });

    if (!moveMap || !_mapReady) return;
    if (_selectedVozacId != null && _pozicije.containsKey(_selectedVozacId)) {
      _mapController.move(_pozicije[_selectedVozacId]!, 15);
    } else if (_selectedVozacId == null && _pozicije.length == 1) {
      _mapController.move(_pozicije.values.first, 15);
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

  /// Vozači sa lokacijom, filtrirani dropdown-om.
  List<V3Vozac> get _prikazaniVozaci {
    final aktivni = _vozaci.where((v) => _pozicije.containsKey(v.id));
    if (_selectedVozacId == null) return aktivni.toList();
    return aktivni.where((v) => v.id == _selectedVozacId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final prikazaniVozaci = _prikazaniVozaci;
    final brojAktivnih = _pozicije.length;
    final selectedSpeed = _selectedVozacId != null ? _brzine[_selectedVozacId] : null;

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
              dropdownColor: V3InputStyle.dropdownMenu,
              style: V3InputUtils.fieldTextStyle,
              decoration: V3InputUtils.dropdownDecoration(
                label: _VozacPozTr.tr('izaberiVozaca'),
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
                                '${selectedSpeed != null ? ' · ${_formatSpeed(selectedSpeed)}' : ''}'
                            : '${_VozacPozTr.tr('aktivnihVozaca')}: $brojAktivnih',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                onMapReady: () {
                  _mapReady = true;
                  _applyCacheToState(moveMap: true);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: AppPlatform.mapUserAgentPackageName,
                ),
                MarkerLayer(
                  markers: [
                    for (final vozac in prikazaniVozaci)
                      Marker(
                        point: _pozicije[vozac.id]!,
                        width: 140,
                        height: 78,
                        alignment: Alignment.bottomCenter,
                        child: _VozacMarker(
                          boja: V3CardColorPolicy.vozacColorOr(vozac.boja),
                          ime: vozac.imePrezime,
                          brzinaLabel: _formatSpeed(_brzine[vozac.id]),
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

  /// null → "—"; inače zaokruženo "42 km/h".
  String _formatSpeed(double? kmh) {
    if (kmh == null) return '— ${_VozacPozTr.tr('kmh')}';
    return '${kmh.round()} ${_VozacPozTr.tr('kmh')}';
  }
}

/// Marker na mapi: balončić sa imenom + brzinom + pin.
/// Sadržaj je na dnu kutije (`MainAxisAlignment.end`) da vrh pina = GPS tačka.
class _VozacMarker extends StatelessWidget {
  const _VozacMarker({
    required this.boja,
    required this.ime,
    required this.brzinaLabel,
  });

  final Color boja;
  final String ime;
  final String brzinaLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: boja,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Text(
                brzinaLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        // Material `location_on` ima ~2–3px praznog ispod vrha igle u glyph-u.
        Icon(Icons.location_on, color: boja, size: 34, opticalSize: 34),
      ],
    );
  }
}
