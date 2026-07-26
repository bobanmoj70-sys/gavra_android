import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/v3_vozac.dart';
import '../services/v3/v3_vozac_location_tracking_service.dart';
import '../services/v3/v3_vozac_service.dart';

/// Admin ekran — uživo prikazuje SAMO poslednju poznatu GPS poziciju izabranog
/// vozača, na besplatnoj OpenStreetMap mapi (bez API ključa, bez naplate).
///
/// Pozicija se ne čuva u bazi — vozačeva app je broadcast-uje preko Supabase
/// Realtime kanala (`v3-vozac-pozicija-<id>`) svaki put kad pošalje GPS radi
/// ETA računa (isti okidač kao i za sada postojeći auto-tracking). Ovaj ekran
/// se samo pretplati na taj kanal dok je otvoren.
class V3AdminVozacPozicijaScreen extends StatefulWidget {
  const V3AdminVozacPozicijaScreen({super.key});

  @override
  State<V3AdminVozacPozicijaScreen> createState() => _V3AdminVozacPozicijaScreenState();
}

class _V3AdminVozacPozicijaScreenState extends State<V3AdminVozacPozicijaScreen> {
  List<V3Vozac> _vozaci = [];
  String? _selectedVozacId;
  RealtimeChannel? _channel;

  ll.LatLng? _pozicija;
  DateTime? _lastUpdate;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _vozaci = V3VozacService.getAllVozaci();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      unawaited(Supabase.instance.client.removeChannel(ch));
    }
  }

  void _selectVozac(String? vozacId) {
    _unsubscribe();
    setState(() {
      _selectedVozacId = vozacId;
      _pozicija = null;
      _lastUpdate = null;
    });
    if (vozacId == null || vozacId.isEmpty) return;

    final channel = Supabase.instance.client.channel(
      V3VozacLocationTrackingService.pozicijaChannelName(vozacId),
    );
    channel.onBroadcast(
      event: 'pozicija',
      callback: (payload) {
        final lat = (payload['lat'] as num?)?.toDouble();
        final lng = (payload['lng'] as num?)?.toDouble();
        if (lat == null || lng == null || !mounted) return;
        final novaPozicija = ll.LatLng(lat, lng);
        setState(() {
          _pozicija = novaPozicija;
          _lastUpdate = DateTime.now();
        });
        _mapController.move(novaPozicija, _mapController.camera.zoom < 3 ? 15 : _mapController.camera.zoom);
      },
    );
    channel.subscribe();
    _channel = channel;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('🛰️ Pozicija vozača'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedVozacId,
              decoration: const InputDecoration(
                labelText: 'Izaberi vozača',
                border: OutlineInputBorder(),
              ),
              items: _vozaci
                  .map((v) => DropdownMenuItem<String>(
                        value: v.id,
                        child: Text(v.imePrezime),
                      ))
                  .toList(),
              onChanged: _selectVozac,
            ),
          ),
          if (_selectedVozacId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    _pozicija != null ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 16,
                    color: _pozicija != null ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _pozicija == null
                          ? 'Čeka se pozicija vozača (mora imati aktivan tracking)...'
                          : 'Ažurirano: ${_formatTime(_lastUpdate!)}',
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
            child: _selectedVozacId == null
                ? const Center(child: Text('Izaberi vozača da vidiš njegovu poziciju.'))
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _pozicija ?? const ll.LatLng(44.7866, 20.4489), // Beograd default
                      initialZoom: _pozicija != null ? 15 : 6,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.gavra013.app',
                      ),
                      if (_pozicija != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pozicija!,
                              width: 44,
                              height: 44,
                              child: const Icon(Icons.directions_car, color: Colors.red, size: 36),
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
