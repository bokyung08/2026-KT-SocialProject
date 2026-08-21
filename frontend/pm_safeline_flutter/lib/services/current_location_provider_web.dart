import 'dart:async';
// ignore: deprecated_member_use
import 'dart:html' as html;

import 'package:latlong2/latlong.dart';

import 'current_location_service.dart' show CurrentLocationException;

Future<LatLng> fetchCurrentLocation() async {
  try {
    final position = await html.window.navigator.geolocation
        .getCurrentPosition(enableHighAccuracy: true)
        .timeout(const Duration(seconds: 10));
    final coords = position.coords;
    final lat = coords?.latitude;
    final lon = coords?.longitude;
    if (lat == null || lon == null) {
      throw const CurrentLocationException('현재 위치를 가져오지 못했습니다.');
    }
    return LatLng(lat.toDouble(), lon.toDouble());
  } on CurrentLocationException {
    rethrow;
  } on TimeoutException {
    throw const CurrentLocationException('현재 위치를 가져오는 데 시간이 초과됐습니다.');
  } catch (_) {
    throw const CurrentLocationException('위치 접근 권한을 확인해 주세요.');
  }
}
