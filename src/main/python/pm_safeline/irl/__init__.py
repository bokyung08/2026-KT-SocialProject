"""irl — Bradley-Terry 기반 IRL 가중치 학습 (PROJECT.md §4.2, §4.4, §4.5-3).

teacher(이미지 위험도 모델)의 edge-risk 를 route-risk 로 집계하고,
경로쌍 선호 라벨로부터 비용함수 가중치 w1~w5 를 Bradley-Terry 랭킹 로스로 학습한다.

numpy/scipy/sklearn 기반 (offline 학습 단계).
학습 완료 후에는 고정된 선형 비용함수만 서비스에 배포된다(§4.2).
"""

from __future__ import annotations

from .bradley_terry import (
    BTResult,
    fit_bradley_terry,
    learn_weights_from_routes,
    make_preference_pairs,
    route_features,
)
from .route_risk import aggregate, route_risk

__all__ = [
    "aggregate",
    "route_risk",
    "route_features",
    "fit_bradley_terry",
    "make_preference_pairs",
    "learn_weights_from_routes",
    "BTResult",
]
