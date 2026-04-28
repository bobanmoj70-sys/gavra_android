import '../../models/v3_putnik.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_address_coordinate_service.dart';
import 'v3_osrm_route_service.dart';
import 'v3_putnik_adresa_resolver_service.dart';

/// Rešava V3RouteWaypoint za putnika koristeći njegovu adresu iz profila.
class V3RouteWaypointResolverService {
  V3RouteWaypointResolverService({V3AddressCoordinateService? addressCoordinateService})
      : _addressCoordinateService = addressCoordinateService ?? V3AddressCoordinateService.instance;

  final V3AddressCoordinateService _addressCoordinateService;

  /// Rešava koordinate za putnika (za ETA orchestrator).
  Future<V3RouteCoordinate?> resolveCoordinateForPutnikFromAuth({
    required String putnikId,
    required String grad,
    bool koristiSekundarnu = false,
    String adresaIdOverride = '',
  }) async {
    final raw = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    if (raw == null) return null;

    final putnik = V3Putnik.fromJson(raw);
    final adresaId = V3PutnikAdresaResolverService.resolveAdresaIdFromPutnikModel(
      putnik: putnik,
      grad: grad,
      koristiSekundarnu: koristiSekundarnu,
      adresaIdOverride: adresaIdOverride,
    );

    return _addressCoordinateService.resolveCoordinate(
      adresaId: adresaId,
      fallbackQuery: putnik.imePrezime,
    );
  }

  /// Rešava pun V3RouteWaypoint za putnika (za vozač screen).
  Future<V3RouteWaypoint?> resolveWaypointForPutnikModel({
    required V3Putnik putnik,
    required String grad,
    bool koristiSekundarnu = false,
    String adresaIdOverride = '',
    required String waypointId,
    required String waypointLabel,
  }) async {
    final adresaId = V3PutnikAdresaResolverService.resolveAdresaIdFromPutnikModel(
      putnik: putnik,
      grad: grad,
      koristiSekundarnu: koristiSekundarnu,
      adresaIdOverride: adresaIdOverride,
    );

    final coordinate = await _addressCoordinateService.resolveCoordinate(
      adresaId: adresaId,
      fallbackQuery: putnik.imePrezime,
    );
    if (coordinate == null) return null;

    return V3RouteWaypoint(
      id: waypointId,
      label: waypointLabel,
      coordinate: coordinate,
    );
  }
}
