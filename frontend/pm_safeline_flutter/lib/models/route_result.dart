import 'package:latlong2/latlong.dart';

class HazardPoint {
  const HazardPoint({
    required this.title,
    required this.description,
    this.position,
  });

  final String title;
  final String description;
  final LatLng? position;
}

class RouteResult {
  const RouteResult({
    required this.name,
    required this.distanceMeters,
    required this.durationMillis,
    required this.weight,
    required this.safetyScore,
    required this.bikeInfraRatio,
    required this.transitionCount,
    required this.geometry,
    this.hazards = const [],
    this.hasDetailedAnalysis = false,
  });

  final String name;
  final double distanceMeters;
  final int durationMillis;
  final double weight;
  final double safetyScore;
  final double bikeInfraRatio;
  final int transitionCount;
  final List<LatLng> geometry;
  final List<HazardPoint> hazards;
  final bool hasDetailedAnalysis;

  factory RouteResult.fromJson(
    Map<String, dynamic> json, {
    String name = '추천 경로',
  }) {
    double number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      throw FormatException('$key 숫자 형식이 올바르지 않습니다.');
    }

    final rawGeometry = json['geometry'];
    final rawMetrics = json['metrics'];
    if (rawGeometry is! List || rawMetrics is! Map) {
      throw const FormatException('경로 필수 데이터가 없습니다.');
    }
    final geometry = rawGeometry
        .map((point) {
          if (point is! List ||
              point.length < 2 ||
              point[0] is! num ||
              point[1] is! num) {
            throw const FormatException('경로 좌표 형식이 올바르지 않습니다.');
          }
          // 서버 GeoJSON 좌표 [경도, 위도]를 Flutter [위도, 경도]로 변환한다.
          return LatLng(
            (point[1] as num).toDouble(),
            (point[0] as num).toDouble(),
          );
        })
        .toList(growable: false);
    final metrics = Map<String, dynamic>.from(rawMetrics);
    final duration = json['durationMillis'];
    final ratio = metrics['bikeInfraRatio'];
    final transitions = metrics['transitionCount'];
    if (duration is! num || ratio is! num || transitions is! num) {
      throw const FormatException('경로 지표 형식이 올바르지 않습니다.');
    }
    return RouteResult(
      name: name,
      distanceMeters: number('distanceMeters'),
      durationMillis: duration.toInt(),
      weight: number('weight'),
      safetyScore: number('safetyScore'),
      bikeInfraRatio: ratio.toDouble(),
      transitionCount: transitions.toInt(),
      geometry: geometry,
    );
  }
}
