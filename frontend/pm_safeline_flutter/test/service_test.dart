import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:pm_safeline_flutter/models/place.dart';
import 'package:pm_safeline_flutter/repositories/api_route_repository.dart';
import 'package:pm_safeline_flutter/repositories/mock_route_repository.dart';
import 'package:pm_safeline_flutter/services/geocoding_service.dart';

void main() {
  const start = Place('출발', '대전', LatLng(36.3664, 127.3447));
  const destination = Place('도착', '대전', LatLng(36.3504, 127.3845));
  const responseBody = {
    'routes': [
      {
        'distanceMeters': 1500.0,
        'durationMillis': 900000,
        'weight': 10.0,
        'safetyScore': 80.0,
        'geometry': [
          [127.3447, 36.3664],
          [127.3612, 36.3598],
          [127.3845, 36.3504],
        ],
        'metrics': {'bikeInfraRatio': .7, 'transitionCount': 2},
      },
    ],
  };

  test('API 저장소가 기존 /route 계약으로 좌표를 전송한다', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/route');
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {
        'fromLat': 36.3664,
        'fromLon': 127.3447,
        'toLat': 36.3504,
        'toLon': 127.3845,
        'alternatives': 3,
      });
      return http.Response(
        jsonEncode(responseBody),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final routes = await ApiRouteRepository(
      'http://localhost:8080',
      client: client,
    ).findRoutes(start, destination);
    expect(routes.single.geometry.last, destination.position);
  });

  test('API 저장소는 2점짜리 직선 geometry를 실제 경로로 허용하지 않는다', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'routes': [
            {
              'distanceMeters': 1500.0,
              'durationMillis': 900000,
              'weight': 10.0,
              'safetyScore': 80.0,
              'geometry': [
                [127.3447, 36.3664],
                [127.3845, 36.3504],
              ],
              'metrics': {'bikeInfraRatio': .7, 'transitionCount': 2},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      ApiRouteRepository(
        'http://localhost:8080',
        client: client,
      ).findRoutes(start, destination),
      throwsA(
        predicate<Object>((error) => error.toString().contains('실제 도로 경로 좌표')),
      ),
    );
  });
  test('정상 추천 경로는 유지하고 2점짜리 대안 경로만 제외한다', () async {
    final validRoute = Map<String, dynamic>.from(
      ((responseBody['routes']! as List).first as Map),
    );
    final shortAlternative = Map<String, dynamic>.from(validRoute)
      ..['geometry'] = [
        [127.3447, 36.3664],
        [127.3845, 36.3504],
      ];
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'routes': [validRoute, shortAlternative],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    final routes = await ApiRouteRepository(
      'http://10.0.2.2:8080',
      client: client,
    ).findRoutes(start, destination);

    expect(routes, hasLength(1));
    expect(routes.single.geometry, hasLength(3));
  });
  test('Nominatim 검색 결과를 장소 후보로 변환한다', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['q'], '중앙시장');
      expect(request.url.queryParameters['countrycodes'], 'kr');
      return http.Response(
        jsonEncode([
          {
            'display_name': '대전중앙시장, 동구, 대전광역시, 대한민국',
            'lat': '36.3292',
            'lon': '127.4321',
            'type': 'marketplace',
            'class': 'amenity',
            'namedetails': {'name': '대전중앙시장'},
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final results = await GeocodingService(client: client).search('중앙시장');
    expect(results.single.name, '대전중앙시장');
    expect(results.single.category, '시장');
    expect(results.single.toPlace().position, const LatLng(36.3292, 127.4321));
  });

  test('Mock 경로는 선택한 출발지와 도착지 좌표를 사용한다', () async {
    final routes = await MockRouteRepository().findRoutes(start, destination);
    expect(routes.first.geometry.first, start.position);
    expect(routes.first.geometry.last, destination.position);
    expect(routes.first.geometry, isNot(equals(routes.last.geometry)));
  });
}
