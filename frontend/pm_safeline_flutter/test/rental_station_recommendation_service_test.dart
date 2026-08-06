import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pm_safeline_flutter/models/rental_station.dart';
import 'package:pm_safeline_flutter/services/rental_station_recommendation_service.dart';

void main() {
  const routePoint = LatLng(36.3508, 127.3842);

  RentalStation station({
    required String id,
    required double lat,
    required double lon,
    int? bikes = 3,
  }) => RentalStation(
    id: id,
    name: '타슈 $id',
    address: '대전광역시',
    lat: lat,
    lon: lon,
    availableBikes: bikes,
    totalDocks: null,
    returnableDocks: null,
    updatedAt: null,
  );

  test('경로 좌표에서 500m 이내 대여소만 추천한다', () {
    const service = RentalStationRecommendationService();
    final nearby = station(id: 'near', lat: 36.3510, lon: 127.3842);
    final far = station(id: 'far', lat: 36.3600, lon: 127.3842);

    final result = service.recommend(
      stations: [far, nearby],
      routeGeometry: const [routePoint],
      routeStart: routePoint,
    );

    expect(result.map((item) => item.id), ['near']);
  });

  test('경로 거리, 자전거 수, 출발지 거리 순으로 정렬한다', () {
    const service = RentalStationRecommendationService();
    final nearest = station(
      id: 'nearest',
      lat: routePoint.latitude,
      lon: routePoint.longitude,
      bikes: 0,
    );
    final fewer = station(
      id: 'fewer',
      lat: routePoint.latitude + 0.001,
      lon: routePoint.longitude,
      bikes: 1,
    );
    final more = station(
      id: 'more',
      lat: routePoint.latitude + 0.001,
      lon: routePoint.longitude,
      bikes: 8,
    );

    final result = service.recommend(
      stations: [fewer, more, nearest],
      routeGeometry: const [routePoint],
      routeStart: routePoint,
    );

    expect(result.map((item) => item.id), ['nearest', 'more', 'fewer']);
  });

  test('추천 대여소는 최대 25개이며 경로 주변이 없으면 빈 목록이다', () {
    const service = RentalStationRecommendationService();
    final many = List.generate(
      30,
      (index) => station(
        id: '$index',
        lat: routePoint.latitude,
        lon: routePoint.longitude,
      ),
    );

    expect(
      service.recommend(
        stations: many,
        routeGeometry: const [routePoint],
        routeStart: routePoint,
      ),
      hasLength(25),
    );
    expect(
      service.recommend(
        stations: [station(id: 'far', lat: 36.3700, lon: 127.3842)],
        routeGeometry: const [routePoint],
        routeStart: routePoint,
      ),
      isEmpty,
    );
  });
}
