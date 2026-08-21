import 'package:latlong2/latlong.dart';

import 'current_location_provider_stub.dart'
    if (dart.library.html) 'current_location_provider_web.dart'
    as provider;

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.message);
  final String message;
}

class CurrentLocationService {
  const CurrentLocationService();

  Future<LatLng> getCurrentLocation() => provider.fetchCurrentLocation();
}
