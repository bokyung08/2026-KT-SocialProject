import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pm_safeline_flutter/app_controller.dart';
import 'package:pm_safeline_flutter/models/place.dart';
import 'package:pm_safeline_flutter/models/rental_station.dart';
import 'package:pm_safeline_flutter/models/route_result.dart';
import 'package:pm_safeline_flutter/repositories/route_repository.dart';
import 'package:pm_safeline_flutter/screens/route_result_screen.dart';
import 'package:pm_safeline_flutter/services/mock_rental_station_service.dart';
import 'package:pm_safeline_flutter/services/rental_station_service.dart';
import 'package:pm_safeline_flutter/theme/app_theme.dart';
import 'package:pm_safeline_flutter/widgets/route_map.dart';

void main() {
  test('mock 타슈 서비스는 대전 대여소와 모든 수량 상태를 제공한다', () async {
    final stations = await MockRentalStationService(
      delay: Duration.zero,
    ).fetchStations();

    expect(stations.length, inInclusiveRange(5, 10));
    expect(
      stations.map((station) => station.status),
      containsAll(RentalStationStatus.values),
    );
    expect(stations.every((station) => station.name.contains('타슈')), isTrue);
    expect(stations.every((station) => station.address.isNotEmpty), isTrue);
    expect(stations.every((station) => station.totalDocks != null), isTrue);
    expect(
      stations.every((station) => station.returnableDocks != null),
      isTrue,
    );
    expect(stations.every((station) => station.updatedAt != null), isTrue);
  });

  testWidgets('초록·노랑·빨강·회색 마커의 표준 상세 정보가 표시된다', (tester) async {
    final controller = _resultController();
    await tester.pumpWidget(_resultApp(controller));
    await tester.tap(find.byKey(const ValueKey('rental-station-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    Color markerColor(String id) {
      final marker = tester.widget<GestureDetector>(
        find.byKey(ValueKey('rental-station-$id')),
      );
      final container = marker.child! as Container;
      return (container.decoration! as BoxDecoration).color!;
    }

    expect(markerColor('tashu-cityhall'), const Color(0xFF20A464));
    expect(markerColor('tashu-gov'), const Color(0xFF20A464));
    expect(markerColor('tashu-hanbat'), const Color(0xFFF5B700));
    expect(markerColor('tashu-jungangno'), const Color(0xFFD94A45));
    expect(markerColor('tashu-dunsan'), const Color(0xFF8C8C94));

    Future<void> openStation(String id) async {
      tester
          .widget<GestureDetector>(find.byKey(ValueKey('rental-station-$id')))
          .onTap!();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> closeSheet() async {
      Navigator.of(
        tester.element(find.byKey(const ValueKey('rental-station-sheet'))),
      ).pop();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openStation('tashu-cityhall');
    expect(find.text('대전시청역 타슈 대여소'), findsOneWidget);
    expect(find.text('대전 서구 둔산중로 55'), findsOneWidget);
    expect(find.text('7대'), findsOneWidget);
    expect(find.text('14개'), findsNothing);
    expect(find.text('정보 없음'), findsNothing);
    await closeSheet();

    await openStation('tashu-gov');
    expect(find.text('정부청사역 타슈 대여소'), findsOneWidget);
    expect(find.text('대전 서구 청사로 189'), findsOneWidget);
    expect(find.text('대여 가능'), findsOneWidget);
    expect(find.text('3대'), findsOneWidget);
    expect(find.text('12개'), findsNothing);
    expect(find.text('9개'), findsNothing);
    expect(find.text('정보 없음'), findsNothing);
    await closeSheet();

    await openStation('tashu-hanbat');
    expect(find.text('한밭수목원 타슈 대여소'), findsOneWidget);
    expect(find.text('대전 서구 둔산대로 169'), findsOneWidget);
    expect(find.text('수량 부족'), findsOneWidget);
    expect(find.text('2대'), findsOneWidget);
    expect(find.text('10개'), findsNothing);
    expect(find.text('8개'), findsNothing);
    expect(find.text('정보 없음'), findsNothing);
    await closeSheet();

    await openStation('tashu-jungangno');
    expect(find.text('중앙로역 타슈 대여소'), findsOneWidget);
    expect(find.text('대전 중구 중앙로 145'), findsOneWidget);
    expect(find.text('대여 불가'), findsOneWidget);
    expect(find.text('0대'), findsOneWidget);
    expect(find.text('10개'), findsNothing);
    expect(find.text('정보 없음'), findsNothing);
    await closeSheet();

    await openStation('tashu-dunsan');
    expect(find.text('둔산동 타슈 대여소'), findsOneWidget);
    expect(find.text('대전 서구 둔산로 100'), findsOneWidget);
    expect(find.text('11개'), findsNothing);
    expect(find.text('6개'), findsNothing);
    expect(find.text('정보 없음'), findsNWidgets(2));
    await closeSheet();
  });

  testWidgets('경로 주변 대여소가 없으면 전체 목록 대신 안내를 표시한다', (tester) async {
    final controller = _resultController();
    await tester.pumpWidget(
      _resultApp(
        controller,
        rentalStationService: const _FarRentalStationService(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('rental-station-toggle')));
    await tester.pump();

    expect(find.text('경로 주변에 추천 가능한 타슈 대여소가 없습니다'), findsOneWidget);
    expect(find.byKey(const ValueKey('rental-station-far')), findsNothing);
  });
  testWidgets('API 대여소 호출 실패는 지도 화면을 깨뜨리지 않고 안내한다', (tester) async {
    final controller = _resultController();
    await tester.pumpWidget(
      _resultApp(
        controller,
        rentalStationService: const _FailingRentalStationService(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('rental-station-toggle')));
    await tester.pump();

    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.text('타슈 대여소 정보를 불러오지 못했습니다.'), findsOneWidget);
  });

  testWidgets('결과 지도는 상단 조작부와 하단 대시보드를 피해서 경로를 맞춘다', (tester) async {
    tester.view.physicalSize = const Size(430, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _resultController();
    await tester.pumpWidget(_resultApp(controller));
    await tester.pump();

    final routeMap = tester.widget<RouteMap>(find.byType(RouteMap));
    expect(routeMap.fitPadding.top, greaterThanOrEqualTo(120));
    expect(routeMap.fitPadding.left, greaterThanOrEqualTo(40));
    expect(routeMap.fitPadding.right, greaterThanOrEqualTo(40));
    expect(routeMap.fitPadding.bottom, greaterThan(300));
    expect(routeMap.maxRouteZoom, lessThanOrEqualTo(15.5));
  });

  testWidgets('지도 조작 버튼은 위치 이동, 전체보기, 집중 모드를 제공한다', (tester) async {
    tester.view.physicalSize = const Size(430, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _resultController();
    final mapController = RouteMapController();
    const currentLocation = LatLng(36.355, 127.39);
    await tester.pumpWidget(
      _resultApp(
        controller,
        mapController: mapController,
        currentLocation: currentLocation,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('map-current-location-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('map-fit-route-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-focus-mode-button')), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);

    await tester.tap(find.byKey(const ValueKey('map-current-location-button')));
    expect(mapController.lastMoveTarget, currentLocation);

    final fitRequests = mapController.fitRequestCount;
    await tester.tap(find.byKey(const ValueKey('map-fit-route-button')));
    expect(mapController.fitRequestCount, fitRequests + 1);

    final expandedPadding = tester
        .widget<RouteMap>(find.byType(RouteMap))
        .fitPadding
        .bottom;
    await tester.tap(find.byKey(const ValueKey('map-focus-mode-button')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('map-focus-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-again-button')), findsNothing);
    final focusedPadding = tester
        .widget<RouteMap>(find.byType(RouteMap))
        .fitPadding
        .bottom;
    expect(focusedPadding, lessThan(expandedPadding));

    await tester.tap(find.byKey(const ValueKey('map-focus-mode-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-again-button')), findsOneWidget);
  });

  testWidgets('현재 위치가 없으면 지도 위치 버튼은 출발지로 이동한다', (tester) async {
    final controller = _resultController();
    final mapController = RouteMapController();
    await tester.pumpWidget(
      _resultApp(controller, mapController: mapController),
    );

    await tester.tap(find.byKey(const ValueKey('map-current-location-button')));
    expect(mapController.lastMoveTarget, controller.start!.position);
  });

  testWidgets('타슈 토글은 대여소 마커를 표시하고 숨긴다', (tester) async {
    final controller = _resultController();
    await tester.pumpWidget(_resultApp(controller));

    expect(
      find.byKey(const ValueKey('rental-station-tashu-cityhall')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('rental-station-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      find.byKey(const ValueKey('rental-station-tashu-cityhall')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('rental-station-toggle')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('rental-station-tashu-cityhall')),
      findsNothing,
    );
  });

  testWidgets('대여소 sheet는 모바일 폭이고 실제 저장소 경로로 다시 계산한다', (tester) async {
    final repository = _RecordingRouteRepository();
    final controller = _resultController(repository: repository);
    final originalStart = controller.start;
    final originalDestination = controller.destination;
    await tester.pumpWidget(_resultApp(controller));
    await tester.tap(find.byKey(const ValueKey('rental-station-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    tester
        .widget<GestureDetector>(
          find.byKey(const ValueKey('rental-station-tashu-cityhall')),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 300));

    final sheetRect = tester.getRect(
      find.byKey(const ValueKey('rental-station-sheet')),
    );
    expect(sheetRect.width, lessThanOrEqualTo(430));
    expect(sheetRect.center.dx, closeTo(400, 1));
    expect(find.text('대여 가능 자전거'), findsOneWidget);
    expect(find.textContaining('직선거리'), findsOneWidget);

    tester
        .widget<FilledButton>(find.byKey(const ValueKey('rent-from-station')))
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.callCount, 1);
    expect(repository.lastStart?.name, '대전시청역 타슈 대여소');
    expect(repository.lastStart?.position, const LatLng(36.3508, 127.3842));
    expect(repository.lastDestination, originalDestination);
    expect(controller.rentalAccessOrigin, originalStart);
    expect(controller.rentalStationStart, repository.lastStart);
    expect(controller.routes.first.geometry.length, greaterThan(2));
    expect(controller.routes.first.distanceMeters, 12345);
    expect(controller.routes.first.safetyScore, 91);
    expect(controller.routes.first.bikeInfraRatio, .95);
    expect(controller.routes.first.transitionCount, 4);

    await tester.pumpWidget(_resultApp(controller));
    await tester.pump();
    expect(find.byKey(const ValueKey('main-route-polyline')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rental-access-polyline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rental-access-distance')),
      findsOneWidget,
    );
    expect(find.text('12.3km'), findsOneWidget);
    expect(find.text('91점'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(find.textContaining('전환은 4회'), findsOneWidget);

    final accessLayer = tester.widget<PolylineLayer>(
      find.byKey(const ValueKey('rental-access-polyline')),
    );
    final mainLayer = tester.widget<PolylineLayer>(
      find.byKey(const ValueKey('main-route-polyline')),
    );
    expect(accessLayer.polylines.single.points.length, 2);
    expect(accessLayer.polylines.single.strokeWidth, lessThan(3));
    expect(mainLayer.polylines.single.points.length, greaterThan(2));
    expect(mainLayer.polylines.single.strokeWidth, 6);
    expect(mainLayer.polylines.single.color, AppColors.safe);
  });

  testWidgets('모바일 viewport에서는 대여소 sheet가 화면 너비를 사용한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _resultController();
    await tester.pumpWidget(_resultApp(controller));
    await tester.tap(find.byKey(const ValueKey('rental-station-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    tester
        .widget<GestureDetector>(
          find.byKey(const ValueKey('rental-station-tashu-cityhall')),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 300));

    final sheetRect = tester.getRect(
      find.byKey(const ValueKey('rental-station-sheet')),
    );
    expect(sheetRect.width, closeTo(390, 1));
    expect(sheetRect.left, closeTo(0, 1));
  });
  testWidgets('결과 화면 이동 동작은 메인과 재검색을 구분한다', (tester) async {
    final controller = _resultController();
    await tester.pumpWidget(_resultApp(controller));

    await tester.tap(find.byKey(const ValueKey('route-back-button')));
    expect(controller.screen, AppScreen.home);

    controller.screen = AppScreen.result;
    await tester.pumpWidget(_resultApp(controller));
    await tester.tap(find.byKey(const ValueKey('route-summary-pill')));
    expect(controller.screen, AppScreen.input);
    expect(controller.routeSearchTarget, RouteSearchTarget.destination);
    expect(controller.start?.name, '대전시청');
    expect(controller.destination?.name, '성심당(대종로480번길)');

    controller.screen = AppScreen.result;
    await tester.pumpWidget(_resultApp(controller));
    await tester.tap(find.byKey(const ValueKey('search-again-button')));
    expect(controller.screen, AppScreen.input);
    expect(controller.routeSearchTarget, RouteSearchTarget.destination);
  });

  testWidgets('390px 모바일은 기존 상단 검색과 하단 패널을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _resultApp(_resultController(), width: 390, height: 844),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('route-summary-pill')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-again-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('responsive-side-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('800px 태블릿은 320px 사이드 패널과 나머지 지도 영역을 사용한다', (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _resultApp(_resultController(), width: 800, height: 1280),
    );
    await tester.pump();

    final panelRect = tester.getRect(
      find.byKey(const ValueKey('responsive-side-panel')),
    );
    final mapRect = tester.getRect(find.byType(RouteMap));
    expect(panelRect.width, closeTo(320, 1));
    expect(mapRect.left, closeTo(320, 1));
    expect(mapRect.width, closeTo(480, 1));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '경로 정보 패널 접기',
      ),
      findsAtLeastNWidgets(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('1440px PC는 380px 패널을 쓰고 탭으로 지도를 전체 폭까지 확장한다', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _resultApp(_resultController(), width: 1440, height: 900),
    );
    await tester.pump();

    expect(
      tester.getRect(find.byKey(const ValueKey('responsive-side-panel'))).width,
      closeTo(380, 1),
    );
    expect(tester.getRect(find.byType(RouteMap)).left, closeTo(380, 1));

    await tester.tap(find.byKey(const ValueKey('desktop-panel-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final expandedMapRect = tester.getRect(find.byType(RouteMap));
    expect(expandedMapRect.left, closeTo(0, 1));
    expect(expandedMapRect.width, closeTo(1440, 1));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '경로 정보 패널 열기',
      ),
      findsAtLeastNWidgets(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 화면의 지도 크게보기는 패널을 자동으로 접고 탭을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _resultApp(_resultController(), width: 800, height: 1280),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map-focus-mode-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(tester.getRect(find.byType(RouteMap)).left, closeTo(0, 1));
    expect(find.byKey(const ValueKey('desktop-panel-toggle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

AppController _resultController({RouteRepository? repository}) {
  final controller = AppController(repository: repository);
  const start = Place('대전시청', '대전광역시 서구 둔산동', LatLng(36.3504, 127.3845));
  const destination = Place(
    '성심당(대종로480번길)',
    '대전광역시 중구 대종로480번길',
    LatLng(36.3277, 127.4273),
  );
  controller
    ..start = start
    ..destination = destination
    ..screen = AppScreen.result
    ..routes = const [
      RouteResult(
        name: '연속주행 우선',
        distanceMeters: 5200,
        durationMillis: 1100000,
        weight: 1500,
        safetyScore: 82,
        bikeInfraRatio: .74,
        transitionCount: 2,
        geometry: [
          LatLng(36.3504, 127.3845),
          LatLng(36.3508, 127.3842),
          LatLng(36.3575, 127.3812),
          LatLng(36.3519, 127.3778),
          LatLng(36.3683, 127.3881),
          LatLng(36.3400, 127.4050),
          LatLng(36.3288, 127.4255),
          LatLng(36.3277, 127.4273),
        ],
      ),
    ];
  return controller;
}

Widget _resultApp(
  AppController controller, {
  RouteMapController? mapController,
  LatLng? currentLocation,
  RentalStationService? rentalStationService,
  double width = 430,
  double height = 800,
}) => MaterialApp(
  theme: buildAppTheme(),
  home: Center(
    child: SizedBox(
      width: width,
      height: height,
      child: RouteResultScreen(
        controller: controller,
        rentalStationService:
            rentalStationService ??
            const MockRentalStationService(delay: Duration.zero),
        mapController: mapController,
        currentLocation: currentLocation,
      ),
    ),
  ),
);

class _FarRentalStationService implements RentalStationService {
  const _FarRentalStationService();

  @override
  Future<List<RentalStation>> fetchStations() async => const [
    RentalStation(
      id: 'far',
      name: '경로 밖 타슈',
      address: '대전광역시 유성구',
      lat: 36.3900,
      lon: 127.3000,
      availableBikes: 10,
      totalDocks: null,
      returnableDocks: null,
      updatedAt: null,
    ),
  ];
}

class _FailingRentalStationService implements RentalStationService {
  const _FailingRentalStationService();

  @override
  Future<List<RentalStation>> fetchStations() =>
      throw const RentalStationException('타슈 대여소 정보를 불러오지 못했습니다.');
}

class _RecordingRouteRepository implements RouteRepository {
  int callCount = 0;
  Place? lastStart;
  Place? lastDestination;

  @override
  Future<List<RouteResult>> findRoutes(Place start, Place destination) async {
    callCount++;
    lastStart = start;
    lastDestination = destination;
    return [
      RouteResult(
        name: 'API 추천 경로',
        distanceMeters: 12345,
        durationMillis: 1260000,
        weight: 3200,
        safetyScore: 91,
        bikeInfraRatio: .95,
        transitionCount: 4,
        geometry: [
          start.position,
          LatLng(
            start.position.latitude + .006,
            start.position.longitude - .008,
          ),
          LatLng(
            destination.position.latitude - .004,
            destination.position.longitude + .006,
          ),
          destination.position,
        ],
      ),
    ];
  }
}
