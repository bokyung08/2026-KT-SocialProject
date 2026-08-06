import 'package:latlong2/latlong.dart';

import '../models/rental_station.dart';

class RentalStationRecommendationService {
  const RentalStationRecommendationService({
    this.radiusMeters = 500,
    this.maxResults = 25,
  });

  final double radiusMeters;
  final int maxResults;

  List<RentalStation> recommend({
    required List<RentalStation> stations,
    required List<LatLng> routeGeometry,
    required LatLng? routeStart,
  }) {
    if (stations.isEmpty || routeGeometry.isEmpty || maxResults <= 0) {
      return const [];
    }

    const distance = Distance();
    final candidates = <_StationDistance>[];
    for (final station in stations) {
      var routeDistance = double.infinity;
      for (final point in routeGeometry) {
        final meters = distance.as(LengthUnit.Meter, station.position, point);
        if (meters < routeDistance) routeDistance = meters;
      }
      if (routeDistance > radiusMeters) continue;

      final startDistance = routeStart == null
          ? double.infinity
          : distance.as(LengthUnit.Meter, station.position, routeStart);
      candidates.add(
        _StationDistance(
          station: station,
          routeDistance: routeDistance,
          startDistance: startDistance,
        ),
      );
    }

    candidates.sort((left, right) {
      final routeOrder = left.routeDistance.compareTo(right.routeDistance);
      if (routeOrder != 0) return routeOrder;

      final bikeOrder = (right.station.availableBikes ?? -1).compareTo(
        left.station.availableBikes ?? -1,
      );
      if (bikeOrder != 0) return bikeOrder;
      return left.startDistance.compareTo(right.startDistance);
    });

    return candidates
        .take(maxResults)
        .map((candidate) => candidate.station)
        .toList(growable: false);
  }
}

class _StationDistance {
  const _StationDistance({
    required this.station,
    required this.routeDistance,
    required this.startDistance,
  });

  final RentalStation station;
  final double routeDistance;
  final double startDistance;
}
