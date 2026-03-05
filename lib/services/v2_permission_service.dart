import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import '../services/v2_theme_manager.dart';

/// Centralizovani servis za sve dozvole
class V2PermissionService {
  V2PermissionService._();

  /// Inicijalno zahtevanje svih dozvola (poziva se u main.dart)
  static Future<bool> requestAllPermissionsOnFirstLaunch(
    BuildContext context,
  ) async {
    // SCREENSHOT MODE - preskoči permissions dialog za testiranje
    const isScreenshotMode = bool.fromEnvironment('SCREENSHOT_MODE', defaultValue: false);
    if (isScreenshotMode) {
      return true; // Preskoči dialog u screenshot modu
    }

    // Ovo radi i nakon hot restart jer se dozvole čuvaju na sistemu
    final areAllPermissionsGranted = await _checkIfAllPermissionsGranted();

    if (areAllPermissionsGranted) {
      return true; // Sve dozvole su već date, preskoči dialog
    }

    // Prikaži dialog samo ako nedostaju dozvole
    return await _showPermissionSetupDialog(context);
  }

  /// Proveri da li su sve dozvole već date
  static Future<bool> checkAllPermissionsGranted() => _checkIfAllPermissionsGranted();

  /// Proveri da li su sve dozvole već date
  static Future<bool> _checkIfAllPermissionsGranted() async {
    final location = await Permission.location.status;
    final contacts = await Permission.contacts.status;
    final notification = await Permission.notification.status;

    // Ako su sve dozvole grantovane, ne prikazuj dialog
    return location.isGranted && contacts.isGranted && notification.isGranted;
  }

  /// Dialog za početno podešavanje dozvola
  static Future<bool> _showPermissionSetupDialog(BuildContext context) async {
    if (!context.mounted) return false;

    // Čekaj da se MaterialLocalizations učita
    try {
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
    } catch (_) {
      // Ako ne postoji, čekaj malo pa pokušaj opet
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    if (!context.mounted) return false;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: _getSafeGradient(),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Podešavanje aplikacije',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Za potpunu funkcionalnost aplikacije potrebne su sledeće dozvole:',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ..._buildPermissionList(),
                          const SizedBox(height: 20),
                          Text(
                            'Dozvole se zahtevaju samo jednom. Možete ih kasnije promeniti u podešavanjima telefona.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Column(
                            children: [
                              // ODOBRI DOZVOLE dugme - zelena boja (gore)
                              SizedBox(
                                width: double.infinity,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.green.shade400,
                                        Colors.green.shade600,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 12,
                                      ),
                                    ),
                                    onPressed: () async {
                                      final success = await requestAllPermissions();
                                      if (context.mounted) {
                                        Navigator.of(context).pop(success);
                                      }
                                    },
                                    child: const Text(
                                      'ODOBRI',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // PRESKOČI dugme - crvenkasto (dole)
                              SizedBox(
                                width: double.infinity,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.red.shade300.withValues(alpha: 0.6),
                                        Colors.red.shade400.withValues(alpha: 0.6),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      'PRESKOČI',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ) ??
        false;
  }

  /// Lista dozvola sa opisima
  static List<Widget> _buildPermissionList() {
    final permissions = [
      {
        'icon': Icons.location_on_rounded,
        'color': const Color(0xFF4CAF50),
        'title': 'GPS lokacija',
        'subtitle': 'za navigaciju do putnika',
      },
      {
        'icon': Icons.phone_rounded,
        'color': const Color(0xFF2196F3),
        'title': 'Pozivi',
        'subtitle': 'za kontaktiranje putnika',
      },
      {
        'icon': Icons.contacts_rounded,
        'color': const Color(0xFFFF9800),
        'title': 'Kontakti',
        'subtitle': 'za biranje broja iz imenika',
      },
      {
        'icon': Icons.notifications_rounded,
        'color': const Color(0xFF9C27B0),
        'title': 'Notifikacije',
        'subtitle': 'za nova putovanja',
      },
    ];

    return permissions
        .map(
          (permission) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (permission['color'] as Color).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    permission['icon'] as IconData,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        permission['title'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        permission['subtitle'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  /// Batch permission request - optimizovano za jedan klik
  static Future<bool> requestAllPermissions() async {
    try {
      final locationStatus =
          await _requestLocationPermission().timeout(const Duration(seconds: 30), onTimeout: () => false);

      final permissions = [
        Permission.phone,
        Permission.contacts,
        Permission.notification,
      ];
      final Map<Permission, PermissionStatus> statuses = await permissions.request();

      final phoneStatus = statuses[Permission.phone] ?? PermissionStatus.denied;
      final contactsStatus = statuses[Permission.contacts] ?? PermissionStatus.denied;
      final notificationStatus = statuses[Permission.notification] ?? PermissionStatus.denied;

      final allCriticalGranted = locationStatus &&
          (phoneStatus.isGranted || phoneStatus.isLimited) &&
          (contactsStatus.isGranted || contactsStatus.isLimited) &&
          (notificationStatus.isGranted || notificationStatus.isLimited);

      return allCriticalGranted;
    } catch (e) {
      return false;
    }
  }

  /// Specijalno zahtevanje lokacijskih dozvola
  static Future<bool> _requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return permission != LocationPermission.denied && permission != LocationPermission.deniedForever;
    } catch (e) {
      return false;
    }
  }

  /// Brza provera lokacijske dozvole
  static Future<bool> _isLocationPermissionGranted() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();

      return serviceEnabled &&
          permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    } catch (e) {
      return false;
    }
  }

  /// Instant GPS za navigaciju (bez dodatnih dialoga)
  static Future<bool> ensureGpsForNavigation() async {
    try {
      final isReady = await _isLocationPermissionGranted();
      if (isReady) {
        return true;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: _getSafeGradient(),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.gps_off_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'GPS je isključen',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Za navigaciju treba da uključite GPS u podešavanjima.\n\nTapnite "Uključi GPS" da otvorite podešavanja.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text(
                                  'Otkaži',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                ),
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text(
                                  'Uključi GPS',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
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

          if (shouldOpen == true) {
            await Geolocator.openLocationSettings();
            await Future<void>.delayed(const Duration(seconds: 2));
            serviceEnabled = await Geolocator.isLocationServiceEnabled();
          }
        } else {
          await Geolocator.openLocationSettings();
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return serviceEnabled &&
          permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    } catch (e) {
      return false;
    }
  }

  /// Huawei specifična logika - Phone permission
  static Future<bool> ensurePhonePermissionHuawei() async {
    try {
      final status = await Permission.phone.status;
      if (status.isGranted || status.isLimited) {
        return true;
      }

      final result = await Permission.phone.request();

      if (result.isDenied || result.isPermanentlyDenied) {
        return true;
      }

      return result.isGranted || result.isLimited;
    } catch (e) {
      return true;
    }
  }

  /// Safe gradient - fallback za startup kad V2ThemeManager nije inicijalizovan
  static LinearGradient _getSafeGradient() {
    try {
      return V2ThemeManager().currentGradient;
    } catch (e) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1E3A8A), // Plava
          Color(0xFF3B82F6), // Svetlija plava
          Color(0xFF60A5FA), // Još svetlija
          Color(0xFF93C5FD), // Svetla plava
          Color(0xFFDBEAFE), // Najsvetlija
        ],
      );
    }
  }
}
