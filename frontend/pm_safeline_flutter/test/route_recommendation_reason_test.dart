import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm_safeline_flutter/models/route_result.dart';
import 'package:pm_safeline_flutter/utils/route_recommendation_reason.dart';
import 'package:pm_safeline_flutter/widgets/route_recommendation_reason_card.dart';

void main() {
  const recommended = RouteResult(
    name: '안전 우선',
    distanceMeters: 5600,
    durationMillis: 1200000,
    weight: 100,
    safetyScore: 82,
    bikeInfraRatio: .76,
    transitionCount: 3,
    geometry: [],
  );
  const shortest = RouteResult(
    name: '최단 경로',
    distanceMeters: 5000,
    durationMillis: 1050000,
    weight: 90,
    safetyScore: 70,
    bikeInfraRatio: .63,
    transitionCount: 7,
    geometry: [],
  );

  test('추천 경로는 현재 경로를 제외한 후보 실제 값으로 설명한다', () {
    final reason = RouteRecommendationReasonBuilder.build(
      selected: recommended,
      candidates: const [recommended, shortest],
      isRecommended: true,
    );

    expect(reason.text, contains('후보 경로 중'));
    expect(
      reason.text,
      contains('자전거도로 비율은 76퍼센트로, 다른 후보 경로의 평균인 63퍼센트보다 높습니다.'),
    );
    expect(reason.sentences.length, lessThanOrEqualTo(3));
    _expectNoInvalidWording(reason.text);
  });

  test('대안 경로는 추천 표현 없이 장단점과 점수를 중립적으로 설명한다', () {
    final reason = RouteRecommendationReasonBuilder.build(
      selected: shortest,
      candidates: const [recommended, shortest],
      isRecommended: false,
    );

    expect(reason.text, contains('이동 거리가 가장 짧습니다'));
    expect(reason.text, contains('안전점수는 70점입니다'));
    expect(reason.text, isNot(contains('추천되었습니다')));
    expect(reason.sentences.length, lessThanOrEqualTo(3));
    _expectNoInvalidWording(reason.text);
  });

  test('비교 후보가 없으면 현재 경로 값만 자연어로 표시한다', () {
    final reason = RouteRecommendationReasonBuilder.build(
      selected: recommended,
      candidates: const [recommended],
      isRecommended: true,
    );

    expect(reason.text, contains('자전거도로 비율은 76퍼센트입니다'));
    expect(reason.text, isNot(contains('다른 후보 경로의 평균')));
    _expectNoInvalidWording(reason.text);
  });

  test('NaN과 Infinity 비교값은 문장에서 제외한다', () {
    const invalid = RouteResult(
      name: '비교 불가 경로',
      distanceMeters: double.infinity,
      durationMillis: 1,
      weight: 1,
      safetyScore: double.nan,
      bikeInfraRatio: double.nan,
      transitionCount: 2,
      geometry: [],
    );
    final reason = RouteRecommendationReasonBuilder.build(
      selected: recommended,
      candidates: const [recommended, invalid],
      isRecommended: true,
    );

    expect(reason.text, contains('자전거도로 비율은 76퍼센트입니다'));
    expect(reason.text, isNot(contains('다른 후보 경로의 평균인')));
    _expectNoInvalidWording(reason.text);
  });

  testWidgets('추천 여부에 따라 설명 카드 제목을 구분한다', (tester) async {
    const reason = RouteRecommendationReason(['설명입니다.']);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RouteRecommendationReasonCard(
                reason: reason,
                isRecommended: true,
              ),
              RouteRecommendationReasonCard(
                reason: reason,
                isRecommended: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('이 경로가 추천된 이유'), findsOneWidget);
    expect(find.text('이 경로의 특징'), findsOneWidget);
    expect(find.text('이 경로를 추천하는 이유'), findsNothing);
  });
}

void _expectNoInvalidWording(String text) {
  expect(text, isNot(contains('%p')));
  expect(text, isNot(contains('%포인트')));
  expect(text, isNot(contains('퍼센트포인트')));
  expect(text, isNot(contains('null')));
  expect(text, isNot(contains('NaN')));
  expect(text, isNot(contains('Infinity')));
  expect(text, isNot(contains('점점')));
  expect(text, isNot(contains('퍼센트퍼센트')));
  expect(text, isNot(contains('평균인 퍼센트')));
}
