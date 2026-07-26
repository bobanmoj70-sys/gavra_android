import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_translations.dart';
import '../models/v3_vozac.dart';
import '../services/v3/v3_vozac_location_tracking_service.dart';
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

/// Admin ekran — uživo prikazuje poslednju poznatu GPS poziciju vozača, na
/// besplatnoj OpenStreetMap mapi (bez API ključa, bez naplate).
///
/// Podrazumevano (opcija "Svi vozači") prikazuje markere SVIH vozača koji
/// trenutno imaju aktivan auto-tracking istovremeno. Preko dropdown-a admin
/// može da izabere jednog konkretnog vozača — tada se mapa fokusira i prikazuje
/// samo njegov marker.
///
/// Pozicija se ne čuva u bazi — vozačeva app je broadcast-uje preko Supabase
/// Realtime kanala (`v3-vozac-pozicija-<id>`) svaki put kad pošalje GPS radi
/// ETA računa (isti okidač kao i za sada postojeći auto-tracking). Ovaj ekran
/// se pretplaćuje na kanale svih vozača dok je otvoren.
class V3AdminVozacPozicijaScreen extends StatefulWidget {
  const V3AdminVozacPozicijaScreen({super.key});

  @override
  State<V3AdminVozacPozicijaScreen> createState() => _V3AdminVozacPozicijaScreenState();
}

/// null = opcija "Svi vozači" (default).
class _V3AdminVozacPozicijaScreenState extends State<V3AdminVozacPozicijaScreen> {
  List<V3Vozac> _vozaci = [];
  String? _selectedVozacId;

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, ll.LatLng> _pozicije = {};
  final Map<String, DateTime> _lastUpdates = {};

  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _vozaci = V3VozacService.getAllVozaci();
    _subscribeToAll();
  }

  @override
  void dispose() {
    for (final ch in _channels.values) {
      unawaited(Supabase.instance.client.removeChannel(ch));
    }
    _channels.clear();
    super.dispose();
  }

  void _subscribeToAll() {
    for (final vozac in _vozaci) {
      if (_channels.containsKey(vozac.id)) continue;
      final channel = Supabase.instance.client.channel(
        V3VozacLocationTrackingService.pozicijaChannelName(vozac.id),
      );
      channel.onBroadcast(
        event: 'pozicija',
        callback: (payload) => _onPozicija(vozac.id, payload),
      );
      channel.subscribe();
      _channels[vozac.id] = channel;
    }
  }

  void _onPozicija(String vozacId, Map<String, dynamic> payload) {
    final lat = (payload['lat'] as num?)?.toDouble();
    final lng = (payload['lng'] as num?)?.toDouble();
    if (lat == null || lng == null || !mounted) return;
    final novaPozicija = ll.LatLng(lat, lng);
    setState(() {
      _pozicije[vozacId] = novaPozicija;
      _lastUpdates[vozacId] = DateTime.now();
    });

    // Fokusiraj kameru samo ako je ovaj vozač trenutno izabran (ili je "Svi"
    // režim i ovo je jedina aktivna pozicija do sada).
    final shouldFollow = _selectedVozacId == vozacId || (_selectedVozacId == null && _pozicije.length == 1);
    if (shouldFollow && _mapReady) {
      _mapController.move(novaPozicija, _mapController.camera.zoom < 3 ? 15 : _mapController.camera.zoom);
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

  /// Vozači koji se trenutno prikazuju kao marker na mapi (imaju bar jednu
  /// primljenu poziciju), filtrirani po izboru u dropdown-u.
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
              initialValue: _selectedVozacId,
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
