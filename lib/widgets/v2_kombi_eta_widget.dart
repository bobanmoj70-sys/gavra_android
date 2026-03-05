import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../utils/v2_grad_adresa_validator.dart';

/// Widget koji prikazuje ETA dolaska kombija.
/// - Uvek vidljiv sa informativnom porukom
/// - Kada vozač startuje rutu: prikazuje ETA uživo
/// - Kada vozač pokupi putnika: prikazuje vreme pokupljenja pa se gasi
class V2KombiEtaWidget extends StatefulWidget {
  const V2KombiEtaWidget({
    super.key,
    required this.putnikIme,
    required this.grad,
    this.sledecaVoznja,
    this.putnikId,
    this.vreme,
  });

  final String putnikIme;
  final String grad;
  final String? sledecaVoznja;
  final String? putnikId;
  final String? vreme; // Termin polaska putnika npr. '7:00'

  @override
  State<V2KombiEtaWidget> createState() => _KombiEtaWidgetState();
}

class _KombiEtaWidgetState extends State<V2KombiEtaWidget> {
  StreamSubscription<String>? _subscription;
  StreamSubscription<String>? _putnikSubscription;
  Timer? _pollingTimer;
  int? _etaMinutes;
  bool _isLoading = true;
  bool _isActive = false;
  String? _vozacIme;
  DateTime? _vremePokupljenja;
  bool _jePokupljenIzBaze = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _subscription?.cancel();
    _putnikSubscription?.cancel();
    super.dispose();
  }

  /// Cita aktivne lokacije vozaca iz in-memory cache-a (0 DB upita).
  /// Cache se puni pri startu i azurira automatski na svaki realtime event.
  /// Fallback DB upit se radi samo ako je cache prazan (npr. odmah pri startu
  /// pre nego sto se RealtimeManager inicijalizovao).
  Future<void> _loadGpsData() async {
    if (!mounted) return;
    try {
      final normalizedGrad = V2GradAdresaValidator.normalizeGrad(widget.grad);
      final normVreme = widget.vreme != null ? V2GradAdresaValidator.normalizeTime(widget.vreme!) : null;

      // PRIMARNI PUT: citaj iz lokacijeCache (0 DB upita)
      final cacheValues = V2MasterRealtimeManager.instance.lokacijeCache.values.toList();
      List<dynamic> list;
      if (cacheValues.isNotEmpty) {
        list = cacheValues.where((row) => row['aktivan'] == true).toList();
      } else {
        // FALLBACK: cache jos nije popunjen (prva sekunda pri startu)
        // Radi jedan DB upit i popuni lokacijeCache
        final data = await supabase
            .from('v2_vozac_lokacije')
            .select('id,vozac_id,lat,lng,grad,vreme_polaska,smer,putnici_eta,aktivan,updated_at')
            .eq('aktivan', true);
        if (!mounted) return;
        // Ažuriraj cache kroz upsertToCache — emituje onCacheChanged i prolazi kroz validaciju
        for (final row in data as List<dynamic>) {
          V2MasterRealtimeManager.instance.v2UpsertToCache('v2_vozac_lokacije', Map<String, dynamic>.from(row as Map));
        }
        list = V2MasterRealtimeManager.instance.lokacijeCache.values.toList();
      }

      if (!mounted) return;

      final filteredList = list.where((driver) {
        final driverGrad = (driver as Map<String, dynamic>)['grad'] as String? ?? '';
        if (V2GradAdresaValidator.normalizeGrad(driverGrad) != normalizedGrad) return false;
        if (normVreme != null) {
          final driverVreme = driver['vreme_polaska'] as String? ?? '';
          if (V2GradAdresaValidator.normalizeTime(driverVreme) != normVreme) return false;
        }
        return true;
      }).toList();

      if (filteredList.isEmpty) {
        setState(() {
          _isActive = false;
          _etaMinutes = null;
          _vozacIme = null;
          _isLoading = false;
        });
        return;
      }

      final driver = filteredList.first;
      final rawEta = driver['putnici_eta'];
      Map<String, dynamic>? putniciEta;
      if (rawEta is String) {
        try {
          putniciEta = json.decode(rawEta) as Map<String, dynamic>?;
        } catch (_) {}
      } else if (rawEta is Map) {
        putniciEta = Map<String, dynamic>.from(rawEta);
      }

      int? eta;
      if (putniciEta != null) {
        // 1. Exact match po putnikId (vozac treba da cuva ID kao kljuc)
        if (widget.putnikId != null && putniciEta.containsKey(widget.putnikId)) {
          eta = putniciEta[widget.putnikId] as int?;
        }
        // 2. Exact match po imenu (stari format, vozac cuva ime kao kljuc)
        if (eta == null && putniciEta.containsKey(widget.putnikIme)) {
          eta = putniciEta[widget.putnikIme] as int?;
        }
        // 3. Case-insensitive exact match po imenu
        if (eta == null) {
          for (final entry in putniciEta.entries) {
            if (entry.key.toLowerCase() == widget.putnikIme.toLowerCase()) {
              eta = entry.value as int?;
              break;
            }
          }
        }
        // Fuzzy contains match uklonjen — bio nestabilan i mogao je
        // da vrati ETA drugog putnika (npr. "Ana" bi matchovala "Anabela")
      }

      setState(() {
        _isActive = true;
        if (eta == -1 && _vremePokupljenja == null) {
          _vremePokupljenja = DateTime.now();
          _jePokupljenIzBaze = true;
        }
        if (eta != null && eta >= 0) {
          _vremePokupljenja = null;
          _jePokupljenIzBaze = false;
        }
        _etaMinutes = eta;
        _vozacIme = driver['vozac_ime'] as String?;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isActive = false;
        });
      }
    }
  }

  void _startListening() {
    _loadGpsData();
    _loadPokupljenjeIzBaze();
    // Polling je sada samo fallback ako realtime padne.
    // Interval produžen: 30s → 5min jer nema potrebe za cestim upitima.
    _pollingTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadGpsData());
    _subscription = V2MasterRealtimeManager.instance.onCacheChanged
        .where((t) => t == 'v2_vozac_lokacije')
        .listen((_) => _loadGpsData());
    if (widget.putnikId != null) {
      _putnikSubscription = V2MasterRealtimeManager.instance.onCacheChanged
          .where((t) => t == 'v2_polasci')
          .listen((_) => _loadPokupljenjeIzBaze());
    }
  }

  Future<void> _loadPokupljenjeIzBaze() async {
    if (widget.putnikId == null) return;
    try {
      const dani = ['ned', 'pon', 'uto', 'sre', 'cet', 'pet', 'sub'];
      final danasKratica = dani[DateTime.now().weekday % 7];
      final normVreme = widget.vreme != null ? V2GradAdresaValidator.normalizeTime(widget.vreme!) : null;
      final gradNorm = widget.grad.isNotEmpty ? V2GradAdresaValidator.normalizeGrad(widget.grad) : null;

      // Čita direktno iz polasciCache — 0 DB upita
      final rm = V2MasterRealtimeManager.instance;
      final row = rm.polasciCache.values.where((r) {
        if (r['putnik_id']?.toString() != widget.putnikId) return false;
        if (r['status'] != 'pokupljen') return false;
        if (r['dan']?.toString() != danasKratica) return false;
        if (gradNorm != null && r['grad']?.toString() != gradNorm) return false;
        if (normVreme != null && V2GradAdresaValidator.normalizeTime(r['dodeljeno_vreme']?.toString()) != normVreme)
          return false;
        return true;
      }).fold<Map<String, dynamic>?>(
        null,
        (best, r) {
          if (best == null) return r;
          final a = DateTime.tryParse(r['updated_at']?.toString() ?? '') ?? DateTime(0);
          final b = DateTime.tryParse(best['updated_at']?.toString() ?? '') ?? DateTime(0);
          return a.isAfter(b) ? r : best;
        },
      );

      if (!mounted) return;

      if (row != null) {
        final parsedTime = DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal();
        setState(() {
          _jePokupljenIzBaze = true;
          _vremePokupljenja = parsedTime ?? DateTime.now();
        });
      } else if (_jePokupljenIzBaze) {
        setState(() {
          _jePokupljenIzBaze = false;
          _vremePokupljenja = null;
        });
      }
    } catch (e) {
    }
  }

  Widget _buildFaza1() {
    // Prikazi sledecu voznju ako je poznata (umesto genericke poruke)
    if (widget.sledecaVoznja != null && widget.sledecaVoznja!.isNotEmpty) {
      return _buildContainer(
        Colors.white,
        icon: Icons.directions_bus,
        title: 'SLEDEĆA VOŽNJA',
        message: widget.sledecaVoznja!,
        showHeader: false,
      );
    }
    return _buildContainer(
      Colors.white,
      icon: Icons.directions_bus,
      title: '🚐 PRAĆENJE KOMBIJA',
      message: 'Ovde će biti prikazano vreme dolaska kombija kada vozač krene',
      showHeader: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dok se učitava — prikaži Fazu 1 sa spinnerom (ne prazan container)
    if (_isLoading) {
      return _buildContainer(
        Colors.white,
        icon: Icons.directions_bus,
        title: '🚐 PRAĆENJE KOMBIJA',
        message: '',
        isLoading: true,
        showHeader: false,
      );
    }

    // Pokupljen — prikaži zelenu potvrdu max 60 min, pa nazad na Fazu 1
    if (_jePokupljenIzBaze && _vremePokupljenja != null) {
      final minutesSince = DateTime.now().difference(_vremePokupljenja!).inMinutes;
      if (minutesSince <= 60) {
        final h = _vremePokupljenja!.hour.toString().padLeft(2, '0');
        final m = _vremePokupljenja!.minute.toString().padLeft(2, '0');
        return _buildContainer(
          Colors.green.shade600,
          icon: Icons.check_circle,
          title: '✅ POKUPLJENI STE',
          message: 'u $h:$m • Želimo ugodnu vožnju! 🚐',
        );
      }
      // Prošlo > 60 min od pokupljenja — nazad na Fazu 1
      return _buildFaza1();
    }

    if (_isActive && _etaMinutes != null && _etaMinutes! >= 0) {
      return _buildContainer(
        Colors.blue.shade700,
        icon: Icons.directions_bus,
        title: 'KOMBI STIŽE ZA',
        message: _formatEta(_etaMinutes!),
        subtitle: _vozacIme != null ? 'Vozač: $_vozacIme' : null,
        bigMessage: true,
      );
    }

    if (_isActive) {
      return _buildContainer(
        Colors.orange.shade700,
        icon: Icons.schedule,
        title: 'VOZAČ KREĆE USKORO',
        message: _vozacIme != null ? 'Vozač: $_vozacIme' : 'Kombi je na putu',
      );
    }

    return _buildFaza1();
  }

  Widget _buildContainer(
    Color baseColor, {
    required IconData icon,
    required String title,
    required String message,
    String? subtitle,
    bool bigMessage = false,
    bool isLoading = false,
    bool showHeader = true,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor.withOpacity(0.15),
            baseColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: isLoading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showHeader) ...[
                  Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: bigMessage ? 20 : 13,
                    fontWeight: bigMessage ? FontWeight.bold : FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                    ),
                  ),
              ],
            ),
    );
  }

  String _formatEta(int minutes) {
    if (minutes < 1) return '< 1 min';
    if (minutes == 1) return '~1 minut';
    if (minutes < 5) return '~$minutes minuta';
    return '~$minutes min';
  }
}
