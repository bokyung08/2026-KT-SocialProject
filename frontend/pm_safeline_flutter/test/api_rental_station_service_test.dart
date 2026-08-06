import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pm_safeline_flutter/models/rental_station.dart';
import 'package:pm_safeline_flutter/services/api_rental_station_service.dart';
import 'package:pm_safeline_flutter/services/mock_rental_station_service.dart';
import 'package:pm_safeline_flutter/services/rental_station_service.dart';
import 'package:pm_safeline_flutter/services/rental_station_service_factory.dart';

void main() {
  test('ApiRentalStationService가 표준 대여소 JSON을 파싱한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'http://localhost:8080/tashu/stations');
      expect(request.headers['Accept'], 'application/json');
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'source': 'api',
            'count': '1',
            'stations': [
              {
                'id': 'tashu-cityhall',
                'name': '대전시청역 타슈 대여소',
                'address': '대전 서구 둔산중로 55',
                'lat': 36.3508,
                'lon': 127.3842,
                'availableBikes': 7,
                'totalDocks': null,
                'returnableDocks': null,
                'updatedAt': null,
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = ApiRentalStationService(
      client: client,
      baseUrl: 'http://localhost:8080/',
    );

    final stations = await service.fetchStations();

    expect(stations, hasLength(1));
    final station = stations.single;
    expect(station.id, 'tashu-cityhall');
    expect(station.name, '대전시청역 타슈 대여소');
    expect(station.address, '대전 서구 둔산중로 55');
    expect(station.lat, 36.3508);
    expect(station.lon, 127.3842);
    expect(station.availableBikes, 7);
    expect(station.totalDocks, isNull);
    expect(station.returnableDocks, isNull);
    expect(station.updatedAt, isNull);
  });

  test('USE_MOCK 값에 따라 mock/API 대여소 서비스를 선택한다', () {
    expect(
      createRentalStationService(useMock: true),
      isA<MockRentalStationService>(),
    );
    expect(
      createRentalStationService(
        useMock: false,
        client: MockClient((_) async => http.Response('[]', 200)),
        baseUrl: 'http://localhost:8080',
      ),
      isA<ApiRentalStationService>(),
    );
  });

  test('API 실패는 RentalStationException으로 변환한다', () async {
    final service = ApiRentalStationService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'source': 'error',
            'stations': <dynamic>[],
            'message': '타슈 API 호출 실패',
          }),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      baseUrl: 'http://localhost:8080',
    );

    await expectLater(
      service.fetchStations(),
      throwsA(
        isA<RentalStationException>().having(
          (error) => error.message,
          'message',
          '타슈 API 호출 실패',
        ),
      ),
    );
  });

  test('source=error 응답은 빈 mock 목록 대신 실패로 처리한다', () async {
    final service = ApiRentalStationService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'source': 'error',
            'stations': [
              {
                'id': 'mock-station',
                'name': '표시되면 안 되는 대여소',
                'address': '주소',
                'lat': 36.35,
                'lon': 127.38,
              },
            ],
            'message': '타슈 API 응답 파싱 실패',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      baseUrl: 'http://localhost:8080',
    );

    await expectLater(
      service.fetchStations(),
      throwsA(
        isA<RentalStationException>().having(
          (error) => error.message,
          'message',
          '타슈 API 응답 파싱 실패',
        ),
      ),
    );
  });

  test('수량 상태는 null/0/1~2/3 이상 기준을 따른다', () {
    RentalStation station(int? bikes) => RentalStation(
      id: 'id',
      name: 'name',
      address: 'address',
      lat: 36.35,
      lon: 127.38,
      availableBikes: bikes,
      totalDocks: 10,
      returnableDocks: 10,
      updatedAt: null,
    );

    expect(station(null).status, RentalStationStatus.unknown);
    expect(station(0).status, RentalStationStatus.unavailable);
    expect(station(1).status, RentalStationStatus.lowAvailability);
    expect(station(2).status, RentalStationStatus.lowAvailability);
    expect(station(3).status, RentalStationStatus.available);
  });
}
