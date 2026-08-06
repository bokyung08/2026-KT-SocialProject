import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../models/route_result.dart';
import 'route_repository.dart';

class MockRouteRepository implements RouteRepository {
  @override
  Future<List<RouteResult>> findRoutes(Place start, Place destination) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final directMeters = const Distance().as(
      LengthUnit.Meter,
      start.position,
      destination.position,
    );
    if (directMeters < 10) {
      throw const RouteRepositoryException('출발지와 도착지가 너무 가깝습니다.');
    }
    final safeGeometry = _curvedPath(
      start.position,
      destination.position,
      .0022,
    );
    final shortGeometry = _curvedPath(
      start.position,
      destination.position,
      -.0008,
    );
    final safeMeters = directMeters * 1.16;
    final shortMeters = directMeters * 1.05;
    return [
      RouteResult(
        name: '연속주행 우선',
        distanceMeters: safeMeters,
        durationMillis: _duration(safeMeters, 17),
        weight: safeMeters * .29,
        safetyScore: 82,
        bikeInfraRatio: .86,
        transitionCount: 1,
        geometry: safeGeometry,
        hasDetailedAnalysis: true,
        hazards: [
          HazardPoint(
            title: '자전거도로 단절',
            description: '선택한 경로 중간 지점 · 약 120m',
            position: safeGeometry[3],
          ),
        ],
      ),
      RouteResult(
        name: '최단거리',
        distanceMeters: shortMeters,
        durationMillis: _duration(shortMeters, 19),
        weight: shortMeters * .31,
        safetyScore: 48,
        bikeInfraRatio: .38,
        transitionCount: 3,
        geometry: shortGeometry,
        hasDetailedAnalysis: true,
        hazards: [
          HazardPoint(
            title: '차도 합류 주의',
            description: '선택한 경로 중간 지점 · 약 180m',
            position: shortGeometry[3],
          ),
        ],
      ),
    ];
  }

  // 선택 좌표를 잇는 데모용 곡선을 생성해 검색 장소가 바뀔 때마다 경로도 바뀐다.
  List<LatLng> _curvedPath(LatLng start, LatLng end, double bend) =>
      List.generate(7, (index) {
        final t = index / 6;
        final curve = math.sin(math.pi * t);
        return LatLng(
          start.latitude + (end.latitude - start.latitude) * t + bend * curve,
          start.longitude +
              (end.longitude - start.longitude) * t +
              bend * .4 * curve,
        );
      });

  int _duration(double meters, double speedKmh) =>
      (meters / 1000 / speedKmh * 3600000).round();
}
