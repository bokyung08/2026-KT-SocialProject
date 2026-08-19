import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm_safeline_flutter/app.dart';
import 'package:pm_safeline_flutter/widgets/route_map.dart';

void main() {
  testWidgets('390x844 모바일은 기존 홈과 하단 내비게이션을 유지한다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const SafeLineApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('desktop-app-shell')), findsNothing);
    expect(find.byKey(const ValueKey('responsive-side-panel')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('새 경로 탐색'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(360, 800),
    Size(390, 844),
    Size(430, 932),
    Size(500, 900),
    Size(599, 900),
  ]) {
    testWidgets('${size.width.round()}px 모바일은 전체 화면 너비를 사용한다', (tester) async {
      _setViewport(tester, size);
      await tester.pumpWidget(const SafeLineApp());
      await tester.pump();

      expect(find.byKey(const ValueKey('desktop-app-shell')), findsNothing);
      expect(find.byKey(const ValueKey('responsive-side-panel')), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      final scaffoldRect = tester.getRect(find.byType(Scaffold));
      final navigationRect = tester.getRect(find.byType(NavigationBar));
      final mapRect = tester.getRect(find.byType(RouteMap));
      expect(scaffoldRect.left, 0);
      expect(scaffoldRect.width, size.width);
      expect(navigationRect.left, 0);
      expect(navigationRect.width, size.width);
      expect(mapRect.left, 20);
      expect(mapRect.right, size.width - 20);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in const [
    (size: Size(600, 960), panelWidth: 320.0),
    (size: Size(800, 1280), panelWidth: 320.0),
    (size: Size(1366, 768), panelWidth: 380.0),
    (size: Size(1920, 1080), panelWidth: 380.0),
  ]) {
    testWidgets(
      '${viewport.size.width.round()}x${viewport.size.height.round()}에서 '
      '왼쪽 패널과 나머지 지도 영역을 사용한다',
      (tester) async {
        _setViewport(tester, viewport.size);
        await tester.pumpWidget(const SafeLineApp());
        await tester.pump();

        final panelRect = tester.getRect(
          find.byKey(const ValueKey('responsive-side-panel')),
        );
        final mapRect = tester.getRect(find.byType(RouteMap));
        expect(panelRect.left, 0);
        expect(panelRect.width, closeTo(viewport.panelWidth, 1));
        expect(mapRect.left, closeTo(viewport.panelWidth, 1));
        expect(
          mapRect.width,
          closeTo(viewport.size.width - viewport.panelWidth, 1),
        );
        expect(find.byType(NavigationBar), findsNothing);
        expect(
          find.byKey(const ValueKey('desktop-home-panel')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('PC 새 경로 탐색은 기본 패널과 지도 위젯을 유지한 채 옆 패널을 연다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    await tester.pumpWidget(const SafeLineApp());
    await tester.pump();

    final originalMapState = tester.state(find.byType(RouteMap));
    final originalMapRect = tester.getRect(find.byType(RouteMap));

    await tester.tap(find.byKey(const ValueKey('desktop-new-route-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.byKey(const ValueKey('desktop-home-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-route-search-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-start-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-destination-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-recommended-place-results')),
      findsOneWidget,
    );

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('desktop-route-search-overlay')),
    );
    expect(overlayRect.left, closeTo(380, 1));
    expect(overlayRect.width, closeTo(380, 1));
    expect(tester.state(find.byType(RouteMap)), same(originalMapState));
    expect(tester.getRect(find.byType(RouteMap)), originalMapRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC 검색 닫기는 임시 선택을 버리고 기존 홈과 지도를 유지한다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    await tester.pumpWidget(const SafeLineApp());
    await tester.pump();
    final originalMapState = tester.state(find.byType(RouteMap));

    await tester.tap(find.byKey(const ValueKey('desktop-new-route-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final overlay = find.byKey(const ValueKey('desktop-route-search-overlay'));
    await tester.tap(
      find.descendant(of: overlay, matching: find.text('충남대학교 정문')).last,
    );
    await tester.pump();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('desktop-start-search-field')),
          )
          .controller
          ?.text,
      '충남대학교 정문',
    );

    await tester.tap(find.byKey(const ValueKey('desktop-search-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.byKey(const ValueKey('desktop-home-panel')), findsOneWidget);
    expect(overlay, findsNothing);
    expect(tester.state(find.byType(RouteMap)), same(originalMapState));

    await tester.tap(find.byKey(const ValueKey('desktop-new-route-button')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('desktop-start-search-field')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('기본 패널을 접고 다시 열어도 검색 패널은 나타나지 않는다', (tester) async {
    _setViewport(tester, const Size(1366, 768));
    await tester.pumpWidget(const SafeLineApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('desktop-panel-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      find.byKey(const ValueKey('desktop-route-search-overlay')),
      findsNothing,
    );
    expect(tester.getRect(find.byType(RouteMap)).left, closeTo(0, 1));

    await tester.tap(find.byKey(const ValueKey('desktop-panel-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      find.byKey(const ValueKey('desktop-route-search-overlay')),
      findsNothing,
    );
    expect(tester.getRect(find.byType(RouteMap)).left, closeTo(380, 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('600px에서도 검색 패널이 화면을 넘지 않고 지도 오버레이로 열린다', (tester) async {
    _setViewport(tester, const Size(600, 960));
    await tester.pumpWidget(const SafeLineApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('desktop-new-route-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('desktop-route-search-overlay')),
    );
    expect(overlayRect.left, closeTo(320, 1));
    expect(overlayRect.right, lessThanOrEqualTo(600.1));
    expect(overlayRect.width, closeTo(280, 1));
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
