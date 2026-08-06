import 'package:flutter_test/flutter_test.dart';
import 'package:pm_safeline_flutter/models/route_result.dart';
import 'package:pm_safeline_flutter/utils/formatters.dart';

void main() {
  final json = <String, dynamic>{
    'distanceMeters': 1500.0,
    'durationMillis': 3660000,
    'weight': 12.5,
    'safetyScore': 82,
    'geometry': [
      [127.3447, 36.3664],
      [127.3845, 36.3504],
    ],
    'metrics': {'bikeInfraRatio': .86, 'transitionCount': 1},
  };
  test('API 응답을 안전 경로 모델로 파싱한다', () {
    final route = RouteResult.fromJson(json);
    expect(route.safetyScore, 82);
    expect(route.transitionCount, 1);
  });
  test('[경도, 위도] 좌표를 LatLng(위도, 경도)로 바꾼다', () {
    final point = RouteResult.fromJson(json).geometry.first;
    expect(point.latitude, 36.3664);
    expect(point.longitude, 127.3447);
  });
  test('거리와 시간을 한국어로 표시한다', () {
    expect(formatDistance(950), '950m');
    expect(formatDistance(1500), '1.5km');
    expect(formatDuration(900000), '15분');
    expect(formatDuration(3660000), '1시간 1분');
  });
}
