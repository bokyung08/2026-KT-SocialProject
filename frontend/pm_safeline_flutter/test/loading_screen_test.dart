import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pm_safeline_flutter/app_controller.dart';
import 'package:pm_safeline_flutter/models/place.dart';
import 'package:pm_safeline_flutter/models/route_result.dart';
import 'package:pm_safeline_flutter/repositories/route_repository.dart';
import 'package:pm_safeline_flutter/screens/loading_screen.dart';
import 'package:pm_safeline_flutter/theme/app_theme.dart';

void main() {
  testWidgets('안전 경로 분석 화면에 경로 애니메이션과 4개 단계를 표시한다', (tester) async {
    final repository = _DeferredRouteRepository();
    final controller = _controller(repository);
    unawaited(controller.analyze());

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LoadingScreen(controller: controller),
      ),
    );

    expect(find.text('안전 경로를 분석하고 있어요'), findsOneWidget);
    expect(find.text('도로 네트워크 불러오기'), findsOneWidget);
    expect(find.text('자전거도로 연결 상태 분석'), findsOneWidget);
    expect(find.text('위험 구간 비용 계산'), findsOneWidget);
    expect(find.text('후보 경로 생성'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('analysis-path-animation')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    controller.cancelAnalysis();
    repository.complete();
    await tester.pump();
  });

  testWidgets('취소한 경로 요청의 늦은 응답을 무시하고 검색 화면 상태를 유지한다', (tester) async {
    final repository = _DeferredRouteRepository();
    final controller = _controller(repository);
    unawaited(controller.analyze());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LoadingScreen(controller: controller),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('cancel-route-analysis')));
    expect(controller.screen, AppScreen.input);

    repository.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(controller.screen, AppScreen.input);
    expect(controller.routes, isEmpty);
    expect(controller.analysisResponseReady, isFalse);
  });

  test('dispose 이후 도착한 경로 응답은 알림 없이 무시한다', () async {
    final repository = _DeferredRouteRepository();
    final controller = _controller(repository);
    final request = controller.analyze();

    controller.dispose();
    repository.complete();

    await request;
  });
}

AppController _controller(RouteRepository repository) {
  final controller = AppController(repository: repository);
  controller
    ..start = const Place('대전시청', '대전광역시 서구 둔산동', LatLng(36.3504, 127.3845))
    ..destination = const Place(
      'KAIST',
      '대전광역시 유성구 대학로 291',
      LatLng(36.3741, 127.3604),
    );
  return controller;
}

class _DeferredRouteRepository implements RouteRepository {
  final _completer = Completer<List<RouteResult>>();

  @override
  Future<List<RouteResult>> findRoutes(Place start, Place destination) =>
      _completer.future;

  void complete() {
    _completer.complete([
      const RouteResult(
        name: '추천 경로',
        distanceMeters: 4200,
        durationMillis: 900000,
        weight: 1200,
        safetyScore: 84,
        bikeInfraRatio: .72,
        transitionCount: 2,
        geometry: [
          LatLng(36.3504, 127.3845),
          LatLng(36.3610, 127.3710),
          LatLng(36.3741, 127.3604),
        ],
      ),
    ]);
  }
}
