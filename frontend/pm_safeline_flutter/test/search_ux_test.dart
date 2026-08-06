import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pm_safeline_flutter/app_controller.dart';
import 'package:pm_safeline_flutter/models/place_search_result.dart';
import 'package:pm_safeline_flutter/screens/route_input_screen.dart';
import 'package:pm_safeline_flutter/services/geocoding_service.dart';

PlaceSearchResult result(
  String name,
  String qualifier,
  double lat,
  double lon,
) => PlaceSearchResult(
  id: '$name-$qualifier',
  name: name,
  displayTitle: '$name($qualifier)',
  address: '대전광역시 $qualifier 대종로',
  category: '베이커리',
  lat: lat,
  lon: lon,
  qualifierCandidates: [qualifier],
);

class FakeGeocodingService extends GeocodingService {
  final calls = <String>[];
  final pending = <String, Completer<List<PlaceSearchResult>>>{};

  @override
  Future<List<PlaceSearchResult>> search(String query) {
    calls.add(query);
    return pending
        .putIfAbsent(query, Completer<List<PlaceSearchResult>>.new)
        .future;
  }

  void complete(String query, List<PlaceSearchResult> results) =>
      pending[query]!.complete(results);
}

void main() {
  test('같은 장소명은 주소 기반 displayTitle로 구분한다', () {
    final results = createDistinctDisplayTitles([
      result('성심당', '은행동', 36.328, 127.427),
      result('성심당', '둔산점', 36.351, 127.378),
      result('성심당', '대전역', 36.332, 127.434),
    ]);
    expect(results.map((item) => item.displayTitle).toSet(), {
      '성심당(은행동)',
      '성심당(둔산점)',
      '성심당(대전역)',
    });
  });

  testWidgets('400ms debounce 후 엔터 없이 검색하고 선택 좌표를 저장한다', (tester) async {
    final geocoding = FakeGeocodingService();
    final controller = AppController();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteInputScreen(
          controller: controller,
          geocodingService: geocoding,
        ),
      ),
    );

    final fields = find.byType(TextField);
    final searchFields = tester.widgetList<TextField>(fields).toList();
    expect(searchFields[0].decoration?.hintText, '출발지');
    expect(searchFields[1].decoration?.hintText, '도착지');
    await tester.enterText(fields.first, '성심당');
    await tester.pump(const Duration(milliseconds: 399));
    expect(geocoding.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(geocoding.calls, ['성심당']);

    final bank = result('성심당', '은행동', 36.328, 127.427);
    geocoding.complete('성심당', [bank]);
    await tester.pump();
    expect(find.text('성심당(은행동)'), findsOneWidget);
    await tester.tap(find.text('성심당(은행동)'));
    await tester.pump();
    expect(controller.start?.name, '성심당(은행동)');
    expect(controller.start?.position, const LatLng(36.328, 127.427));
    expect(controller.recentPlaces.first.name, '성심당(은행동)');
  });

  testWidgets('결과 수정 진입은 기존 값을 채우고 도착지에 포커스한다', (tester) async {
    final controller = AppController();
    controller.setStart(result('대전시청', '둔산동', 36.3504, 127.3845).toPlace());
    controller.setDestination(result('성심당', '은행동', 36.328, 127.427).toPlace());
    controller.editRoute();

    await tester.pumpWidget(
      MaterialApp(
        home: RouteInputScreen(
          controller: controller,
          geocodingService: FakeGeocodingService(),
        ),
      ),
    );
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(find.text('출발지와 도착지를 검색하세요'), findsOneWidget);
    expect(fields[0].controller?.text, '대전시청(둔산동)');
    expect(fields[1].controller?.text, '성심당(은행동)');
    expect(fields[1].focusNode?.hasFocus, isTrue);
    expect(controller.routeSearchTarget, RouteSearchTarget.destination);
  });

  testWidgets('모바일 키보드 위에서 자동검색 결과를 선택할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final geocoding = FakeGeocodingService();
    final controller = AppController();
    controller.setStart(result('대전시청', '둔산동', 36.3504, 127.3845).toPlace());
    controller.routeSearchTarget = RouteSearchTarget.destination;
    await tester.pumpWidget(
      MaterialApp(
        home: RouteInputScreen(
          controller: controller,
          geocodingService: geocoding,
        ),
      ),
    );
    await tester.pump();

    final destination = find.byKey(const ValueKey('destination-search-field'));
    expect(tester.widget<TextField>(destination).focusNode?.hasFocus, isTrue);
    await tester.enterText(destination, '성심당');
    await tester.pump(const Duration(milliseconds: 400));
    geocoding.complete('성심당', [result('성심당', '롯데백화점', 36.351, 127.378)]);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('place-search-results')), findsOneWidget);
    expect(find.text('성심당(롯데백화점)'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('성심당(롯데백화점)')).dy,
      lessThan(844 - 320),
    );

    await tester.tap(find.text('성심당(롯데백화점)'));
    await tester.pump();
    expect(controller.destination?.name, '성심당(롯데백화점)');
    expect(controller.destination?.position, const LatLng(36.351, 127.378));
    expect(
      tester.widget<TextField>(destination).controller?.text,
      '성심당(롯데백화점)',
    );

    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('analyze-route-button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('출발지와 도착지 교환 시 제목과 좌표를 함께 바꾼다', (tester) async {
    final controller = AppController();
    controller.setStart(result('성심당', '은행동', 36.328, 127.427).toPlace());
    controller.setDestination(
      result('대전시청', '둔산동', 36.3504, 127.3845).toPlace(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RouteInputScreen(
          controller: controller,
          geocodingService: FakeGeocodingService(),
        ),
      ),
    );

    await tester.tap(find.text('출발·도착 교환'));
    await tester.pump();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller?.text, '대전시청(둔산동)');
    expect(fields[1].controller?.text, '성심당(은행동)');
    expect(controller.start?.position, const LatLng(36.3504, 127.3845));
    expect(controller.destination?.position, const LatLng(36.328, 127.427));
  });
  testWidgets('느린 이전 응답이 최신 검색 결과를 덮지 않는다', (tester) async {
    final geocoding = FakeGeocodingService();
    final controller = AppController();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteInputScreen(
          controller: controller,
          geocodingService: geocoding,
        ),
      ),
    );
    final startField = find.byType(TextField).first;

    await tester.enterText(startField, '성심당');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(startField, '대전시청');
    await tester.pump(const Duration(milliseconds: 400));
    geocoding.complete('대전시청', [result('대전시청', '둔산동', 36.3504, 127.3845)]);
    await tester.pump();
    await tester.pump();
    expect(find.text('대전시청(둔산동)'), findsOneWidget);

    geocoding.complete('성심당', [result('성심당', '은행동', 36.328, 127.427)]);
    await tester.pump();
    await tester.pump();
    expect(find.text('대전시청(둔산동)'), findsOneWidget);
    expect(find.text('성심당(은행동)'), findsNothing);
  });
}
