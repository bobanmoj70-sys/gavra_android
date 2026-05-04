class V3RouteCoordinate {
  final double latitude;
  final double longitude;

  const V3RouteCoordinate({
    required this.latitude,
    required this.longitude,
  });
}

class V3RouteWaypoint {
  final String id;
  final String label;
  final V3RouteCoordinate coordinate;

  const V3RouteWaypoint({
    required this.id,
    required this.label,
    required this.coordinate,
  });
}
