import '../models/place.dart';
import '../models/route_result.dart';

abstract interface class RouteRepository {
  Future<List<RouteResult>> findRoutes(Place start, Place destination);
}

class RouteRepositoryException implements Exception {
  const RouteRepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}
