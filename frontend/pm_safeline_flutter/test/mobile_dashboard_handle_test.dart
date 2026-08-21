import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pm_safeline_flutter/app_controller.dart';
import 'package:pm_safeline_flutter/models/place.dart';
import 'package:pm_safeline_flutter/models/route_result.dart';
import 'package:pm_safeline_flutter/screens/route_result_screen.dart';
import 'package:pm_safeline_flutter/theme/app_theme.dart';

void main() {
  testWidgets('드래그 핸들 바는 타이틀 글자 윗선에 맞고 세로 공간을 차지하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _resultController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: RouteResultScreen(controller: controller),
      ),
    );
    await tester.pump();

    final bar = find.byKey(const ValueKey('mobile-dashboard-handle-bar'));
    final title = find.text('추천 경로');
    expect(bar, findsOneWidget);
    expect(title, findsOneWidget);

    final barRect = tester.getRect(bar);
    final titleRect = tester.getRect(title);

    // 바 윗선이 타이틀 글자 박스 윗선과 나란해야 한다.
    expect(barRect.top, closeTo(titleRect.top, 1));
    // 카드는 좌우 12씩 대칭 여백이라 카드 중앙 == 화면 중앙이다.
    expect(barRect.center.dx, closeTo(390 / 2, 0.5));

    // 별도 줄이 아니라 겹쳐 있어야 한다(= 세로 공간을 차지하지 않는다).
    // 자기 줄을 가지면 바가 타이틀 박스 위로 완전히 벗어난다.
    expect(barRect.bottom, greaterThan(titleRect.top));
    // 핸들이 Positioned 라 타이틀 줄 높이를 키우지 않는다.
    final stack = find.ancestor(of: title, matching: find.byType(Stack)).first;
    final row = find.descendant(of: stack, matching: find.byType(Row)).first;
    expect(tester.getRect(stack).height, tester.getRect(row).height);
  });

  // pill 안의 즐겨찾기 IconButton 기본 최소 크기(40) 때문에 상단 바가 62px 로
  // 부풀던 회귀를 막는다. 플랫폼과 무관하게 같은 높이여야 한다.
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('상단 경로 요약 바 높이는 $platform 에서도 44로 같다', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _resultController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme().copyWith(platform: platform),
          home: RouteResultScreen(controller: controller),
        ),
      );
      await tester.pump();

      final pill = find.byKey(const ValueKey('route-summary-pill'));
      final back = find.byKey(const ValueKey('route-back-button'));
      expect(tester.getRect(pill).height, 44);
      expect(tester.getRect(back).height, 44);
    });
  }
}

AppController _resultController() {
  final controller = AppController();
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
