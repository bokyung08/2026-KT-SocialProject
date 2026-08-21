import 'package:latlong2/latlong.dart';

import 'current_location_service.dart' show CurrentLocationException;

Future<LatLng> fetchCurrentLocation() async {
  throw const CurrentLocationException('이 플랫폼에서는 현재 위치를 지원하지 않습니다.');
}
