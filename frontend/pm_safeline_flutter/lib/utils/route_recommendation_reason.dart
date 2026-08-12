import '../models/route_result.dart';

class RouteRecommendationReason {
  const RouteRecommendationReason(this.sentences);

  final List<String> sentences;

  String get text => sentences.join(' ');
}

abstract final class RouteRecommendationReasonBuilder {
  static RouteRecommendationReason build({
    required RouteResult selected,
    required List<RouteResult> candidates,
    required bool isRecommended,
  }) {
    final others = candidates
        .where((route) => !identical(route, selected))
        .toList();
    final sentences = <String>[];
    final selectedBikePercent = _percent(selected.bikeInfraRatio);
    final averageBikePercent = _average(
      others.map((route) => route.bikeInfraRatio * 100),
    )?.round();
    final averageTransitions = _average(
      others.map((route) => route.transitionCount.toDouble()),
    );
    final shortest = _shortest(candidates);

    if (isRecommended) {
      final advantages = <String>[];
      if (selectedBikePercent != null &&
          averageBikePercent != null &&
          selectedBikePercent > averageBikePercent) {
        advantages.add('자전거도로 비율이 다른 후보 경로의 평균보다 높고');
      }
      if (averageTransitions != null &&
          selected.transitionCount < averageTransitions) {
        advantages.add('도로 유형 전환이 다른 후보 경로의 평균보다 적어');
      }
      if (advantages.isNotEmpty) {
        sentences.add(
          '후보 경로 중 ${advantages.take(2).join(' ')} 상대적으로 나은 경로로 추천되었습니다.',
        );
      } else {
        sentences.add('후보 중 상대적으로 높은 점수를 받은 경로로 추천되었습니다.');
      }

      if (selectedBikePercent != null) {
        if (averageBikePercent != null &&
            selectedBikePercent != averageBikePercent) {
          final comparison = selectedBikePercent > averageBikePercent
              ? '높습니다'
              : '낮습니다';
          sentences.add(
            '자전거도로 비율은 $selectedBikePercent퍼센트로, '
            '다른 후보 경로의 평균인 $averageBikePercent퍼센트보다 $comparison.',
          );
        } else {
          sentences.add('자전거도로 비율은 $selectedBikePercent퍼센트입니다.');
        }
      }

      if (sentences.length < 3) {
        sentences.add('도로 유형 전환은 ${selected.transitionCount}회입니다.');
      }

      if (shortest != null &&
          !identical(shortest, selected) &&
          _finite(selected.distanceMeters) &&
          _finite(selected.safetyScore) &&
          _finite(shortest.safetyScore)) {
        final distanceDifference =
            selected.distanceMeters - shortest.distanceMeters;
        final scoreDifference = selected.safetyScore - shortest.safetyScore;
        if (distanceDifference > 50 && scoreDifference > 0.5) {
          sentences.add(
            '최단 경로보다 ${_formatDistanceDifference(distanceDifference)} 길지만 '
            '안전점수가 ${scoreDifference.round()}점 높습니다.',
          );
        }
      }
      if (sentences.length < 3 && _finite(selected.safetyScore)) {
        sentences.add('안전점수는 ${selected.safetyScore.round()}점입니다.');
      }
    } else {
      if (shortest != null && identical(shortest, selected)) {
        sentences.add('후보 경로 중 이동 거리가 가장 짧습니다.');
      } else if (averageTransitions != null &&
          selected.transitionCount < averageTransitions) {
        sentences.add(
          '도로 유형 전환은 ${selected.transitionCount}회로, '
          '다른 후보 경로의 평균보다 적습니다.',
        );
      }

      if (selectedBikePercent != null) {
        if (averageBikePercent != null &&
            selectedBikePercent != averageBikePercent) {
          final comparison = selectedBikePercent > averageBikePercent
              ? '높습니다'
              : '낮습니다';
          sentences.add(
            '자전거도로 비율은 $selectedBikePercent퍼센트로, '
            '다른 후보 경로의 평균인 $averageBikePercent퍼센트보다 $comparison.',
          );
        } else {
          sentences.add('자전거도로 비율은 $selectedBikePercent퍼센트입니다.');
        }
      }
      if (_finite(selected.safetyScore)) {
        sentences.add('안전점수는 ${selected.safetyScore.round()}점입니다.');
      }
    }

    if (sentences.isEmpty) {
      sentences.add(
        isRecommended
            ? '후보 경로를 비교해 상대적으로 나은 경로로 추천되었습니다.'
            : '선택한 경로의 상세 지표를 확인해 주세요.',
      );
    }
    return RouteRecommendationReason(sentences.take(3).toList(growable: false));
  }

  static bool _finite(double value) => value.isFinite;

  static int? _percent(double ratio) =>
      _finite(ratio) ? (ratio * 100).round() : null;

  static double? _average(Iterable<double> values) {
    final finiteValues = values.where(_finite).toList(growable: false);
    if (finiteValues.isEmpty) return null;
    return finiteValues.reduce((a, b) => a + b) / finiteValues.length;
  }

  static RouteResult? _shortest(List<RouteResult> candidates) {
    final finiteCandidates = candidates
        .where((route) => _finite(route.distanceMeters))
        .toList(growable: false);
    if (finiteCandidates.isEmpty) return null;
    return finiteCandidates.reduce(
      (a, b) => a.distanceMeters <= b.distanceMeters ? a : b,
    );
  }

  static String _formatDistanceDifference(double meters) {
    if (meters < 500) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
}
