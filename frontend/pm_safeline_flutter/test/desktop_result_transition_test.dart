import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pm_safeline_flutter/app_controller.dart';
import 'package:pm_safeline_flutter/models/place.dart';
import 'package:pm_safeline_flutter/models/route_result.dart';
import 'package:pm_safeline_flutter/repositories/route_repository.dart';
import 'package:pm_safeline_flutter/screens/route_result_screen.dart';
import 'package:pm_safeline_flutter/theme/app_theme.dart';
import 'package:pm_safeline_flutter/widgets/desktop_app_shell.dart';
import 'package:pm_safeline_flutter/widgets/route_map.dart';

void main() {
  testWidgets('추천 경로는 상대 추천 배지와 추천된 이유 제목을 표시한다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    final controller = _resultController();
    await tester.pumpWidget(_DesktopFlowHarness(controller: controller));
    await tester.pump();

    expect(find.text('후보 중 추천'), findsAtLeastNWidgets(1));
    expect(find.text('이 경로가 추천된 이유'), findsOneWidget);
    expect(find.text('이 경로를 추천하는 이유'), findsNothing);
  });

  testWidgets('최단 대안 경로는 특징 제목을 표시하고 추천 표현을 사용하지 않는다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    final controller = _resultController();
    controller.routes = [
      ...controller.routes,
      const RouteResult(
        name: '최단 경로',
        distanceMeters: 4800,
        durationMillis: 980000,
        weight: 1400,
        safetyScore: 65,
        bikeInfraRatio: .42,
        transitionCount: 5,
        geometry: [
          LatLng(36.3504, 127.3845),
          LatLng(36.3620, 127.3720),
          LatLng(36.3741, 127.3604),
        ],
      ),
    ];
    await tester.pumpWidget(_DesktopFlowHarness(controller: controller));
    await tester.pump();

    expect(find.text('경로 선택'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('route-option-1')));
    await tester.pump();

    expect(find.text('최단'), findsAtLeastNWidgets(1));
    expect(find.text('이 경로의 특징'), findsOneWidget);
    expect(find.text('이 경로가 추천된 이유'), findsNothing);
    expect(find.text('이 경로를 추천하는 이유'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('route-reason-text'))).data,
      isNot(contains('추천되었습니다')),
    );
  });
  testWidgets('PC 결과 편집은 기본 패널과 같은 지도 위에 검색 패널을 연다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    final controller = _resultController();
    await tester.pumpWidget(_DesktopFlowHarness(controller: controller));
    await tester.pump();

    final resultMapState = tester.state(find.byType(RouteMap));
    final resultMapRect = tester.getRect(find.byType(RouteMap));
    expect(resultMapRect.left, closeTo(380, 1));
    expect(find.byKey(const ValueKey('main-route-polyline')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-route-search')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('경로 정보'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-route-search-content')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('desktop-start-search-field')),
          )
          .controller
          ?.text,
      '대전시청',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('desktop-destination-search-field')),
          )
          .controller
          ?.text,
      'KAIST',
    );
    expect(tester.state(find.byType(RouteMap)), same(resultMapState));
    expect(tester.getRect(find.byType(RouteMap)), resultMapRect);
    expect(find.byKey(const ValueKey('main-route-polyline')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC 검색 패널 닫기는 임시 도착지와 기존 경로를 변경하지 않는다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    final controller = _resultController();
    final originalDestination = controller.destination;
    final originalRoute = controller.routes.single;
    await tester.pumpWidget(_DesktopFlowHarness(controller: controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('desktop-edit-destination')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.enterText(
      find.byKey(const ValueKey('desktop-destination-search-field')),
      '',
    );
    await tester.pump();
    final overlay = find.byKey(const ValueKey('desktop-route-search-overlay'));
    await tester.tap(
      find.descendant(of: overlay, matching: find.text('충남대학교 정문')).last,
    );
    await tester.pump();

    expect(controller.destination, same(originalDestination));
    expect(controller.routes.single, same(originalRoute));

    await tester.tap(find.byKey(const ValueKey('desktop-search-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(controller.destination, same(originalDestination));
    expect(controller.routes.single, same(originalRoute));
    expect(find.byKey(const ValueKey('main-route-polyline')), findsOneWidget);
    expect(overlay, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC 검색 완료 성공 시에만 임시 경로를 실제 결과에 반영한다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    final controller = _resultController();
    final originalDestination = controller.destination;
    await tester.pumpWidget(_DesktopFlowHarness(controller: controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('desktop-edit-destination')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.enterText(
      find.byKey(const ValueKey('desktop-destination-search-field')),
      '',
    );
    await tester.pump();
    final overlay = find.byKey(const ValueKey('desktop-route-search-overlay'));
    await tester.tap(
      find.descendant(of: overlay, matching: find.text('충남대학교 정문')).last,
    );
    await tester.pump();

    expect(controller.destination, same(originalDestination));
    await tester.tap(
      find.byKey(const ValueKey('desktop-analyze-route-button')),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(controller.destination?.name, '충남대학교 정문');
    expect(controller.routes.first.geometry.length, greaterThan(2));
    expect(find.byKey(const ValueKey('main-route-polyline')), findsOneWidget);
    expect(overlay, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC 검색 API 실패는 기존 경로를 유지하고 패널 안에 오류를 표시한다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    final controller = _resultController(
      repository: const _FailingRouteRepository(),
    );
    final originalDestination = controller.destination;
    final originalRoute = controller.routes.single;
    await tester.pumpWidget(_DesktopFlowHarness(controller: controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('desktop-edit-destination')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.enterText(
      find.byKey(const ValueKey('desktop-destination-search-field')),
      '',
    );
    await tester.pump();
    final overlay = find.byKey(const ValueKey('desktop-route-search-overlay'));
    await tester.tap(
      find.descendant(of: overlay, matching: find.text('충남대학교 정문')).last,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('desktop-analyze-route-button')),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.destination, same(originalDestination));
    expect(controller.routes.single, same(originalRoute));
    expect(
      find.byKey(const ValueKey('desktop-route-submit-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('main-route-polyline')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC 경로 분석은 왼쪽 패널 안에 표시되고 지도는 오른쪽에 유지된다', (tester) async {
    _setViewport(tester, const Size(800, 1280));
    final controller = _resultController()..screen = AppScreen.loading;
    await tester.pumpWidget(_DesktopFlowHarness(controller: controller));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('desktop-loading-content')),
      findsOneWidget,
    );
    expect(find.text('안전 경로를 분석하고 있어요'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('responsive-side-panel'))).width,
      closeTo(320, 1),
    );
    expect(tester.getRect(find.byType(RouteMap)).left, closeTo(320, 1));
    expect(tester.takeException(), isNull);
  });
}

AppController _resultController({RouteRepository? repository}) {
  final controller = AppController(repository: repository);
  controller
    ..start = const Place('대전시청', '대전광역시 서구 둔산동', LatLng(36.3504, 127.3845))
    ..destination = const Place(
      'KAIST',
      '대전광역시 유성구 대학로',
      LatLng(36.3741, 127.3604),
    )
    ..screen = AppScreen.result
    ..routes = const [
      RouteResult(
        name: '추천 경로',
        distanceMeters: 5200,
        durationMillis: 1100000,
        weight: 1500,
        safetyScore: 82,
        bikeInfraRatio: .74,
        transitionCount: 2,
        geometry: [
          LatLng(36.3504, 127.3845),
          LatLng(36.3600, 127.3750),
          LatLng(36.3680, 127.3670),
          LatLng(36.3741, 127.3604),
        ],
      ),
    ];
  return controller;
}

class _FailingRouteRepository implements RouteRepository {
  const _FailingRouteRepository();

  @override
  Future<List<RouteResult>> findRoutes(Place start, Place destination) =>
      Future<List<RouteResult>>.error(
        const RouteRepositoryException('경로 API 테스트 오류'),
      );
}

class _DesktopFlowHarness extends StatefulWidget {
  const _DesktopFlowHarness({required this.controller});

  final AppController controller;

  @override
  State<_DesktopFlowHarness> createState() => _DesktopFlowHarnessState();
}

class _DesktopFlowHarnessState extends State<_DesktopFlowHarness> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(),
    home: widget.controller.screen == AppScreen.result
        ? RouteResultScreen(controller: widget.controller)
        : DesktopAppShell(controller: widget.controller),
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
