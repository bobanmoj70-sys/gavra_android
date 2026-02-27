import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../screens/pin_zahtevi_screen.dart';
import '../screens/v2_home_screen.dart';
import '../screens/v2_putnik_profil_screen.dart';
import '../screens/v2_vozac_screen.dart';
import 'realtime/v2_master_realtime_manager.dart';

class NotificationNavigationService {
  /// 🚐 Navigiraj na putnikov profil ekran (za "transport_started" ili seat request notifikacije)
  static Future<void> navigateToPassengerProfile() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final putnikId = prefs.getString('registrovani_putnik_id');

      if (putnikId == null) {
        debugPrint('⚠️ [NavService] Nemam putnik_id u SharedPreferences-u');
        return;
      }

      // Učitaj podatke putnika iz cache-a
      final response = V2MasterRealtimeManager.instance.getPutnikById(putnikId);
      if (response == null) {
        debugPrint('⚠️ [NavService] Putnik $putnikId nije u cache-u');
        return;
      }

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => V2PutnikProfilScreen(
              putnikData: response,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [NavService] Greška pri navigaciji na profil: $e');
    }
  }

  /// 🚐 Navigiraj na Vozač Screen (za 'vozac_krenuo' notifikaciju)
  static Future<void> navigateToVozacScreen() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    try {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const VozacScreen(),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [NavService] Greška pri navigaciji na VozacScreen: $e');
    }
  }

  /// 🔐 Navigiraj na PIN zahtevi ekran (za admina)
  static Future<void> navigateToPinZahtevi() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    try {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const PinZahteviScreen(),
          ),
        );
      }
    } catch (e) {
      // Ignoriši greške
    }
  }

  static Future<void> navigateToPassenger({
    required String type,
    required Map<String, dynamic> putnikData,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    try {
      final putnikIme = putnikData['ime'] ?? '';
      final putnikDan = putnikData['dan'] ?? '';
      final mesecnaKarta = putnikData['mesecnaKarta'] ?? false;

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  type == 'novi_putnik' ? Icons.person_add : Icons.person_remove,
                  color: type == 'novi_putnik' ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    type == 'novi_putnik' ? 'Novi putnik dodat' : 'Putnik otkazan',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '👤 $putnikIme',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if ((putnikDan as String).isNotEmpty)
                  Text(
                    '📅 Dan: $putnikDan',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (putnikData['polazak'] != null)
                  Text(
                    '🕐 Polazak: ${putnikData['polazak']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (putnikData['grad'] != null)
                  Text(
                    '🏘️ Destinacija: ${putnikData['grad']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (mesecnaKarta as bool)
                  const Text(
                    '💳 Mesečna karta',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Vreme: ${DateTime.now().toString().substring(0, 19)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Zatvori'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _navigateToAppropriateScreen(
                    context,
                    type,
                    putnikData,
                    mesecnaKarta,
                  );
                },
                child: const Text('Otvori'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, 'Greška pri otvaranju putnika: $e');
      }
    }
  }

  static void _navigateToAppropriateScreen(
    BuildContext context,
    String type,
    Map<String, dynamic> putnikData,
    bool mesecnaKarta,
  ) {
    final putnikIme = putnikData['ime'];
    final putnikGrad = putnikData['grad'];
    final putnikVreme = putnikData['polazak'] ?? putnikData['vreme'];

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const HomeScreen(),
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Greška'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('U redu'),
            ),
          ],
        );
      },
    );
  }
}
