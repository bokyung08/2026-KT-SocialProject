"""route_risk — edge 단위 사고 위험확률을 route(경로) 단위 위험도로 집계.

PROJECT.md §4.5-3 에서 검토한 후보 중 **hazard-rate 기반 생존모델**을 기본(권장)으로
채택하고, 비교용으로 mean/max/sum/count 베이스라인도 함께 제공한다
(numpy/scipy/sklearn 기반, offline 학습 단계).

    route_risk = 1 - exp(-Σ h_i * L_i),   h_i = -ln(1 - p_i) / L_i
               = 1 - Π (1 - p_i)

- p_i : edge i 의 사고확률(teacher 모델 출력, [0,1))
- L_i : edge i 의 길이(m). hazard 형태에서는 h_i*L_i = -ln(1-p_i) 로 상쇄되어
        route_risk 계산 자체에는 길이가 다시 등장하지 않지만(닫힌 형태가 곱 형태로
        축약됨), 길이는 각 edge 의 "노출량"을 표현하는 개념적 근거로 남겨둔다.
"""

from __future__ import annotations

import numpy as np

_EPS = 1e-9
_P_CLIP_MAX = 1.0 - 1e-6  # p_i -> 1 이면 ln(1-p_i) 발산하므로 clip


def _clip_probs(edge_probs: np.ndarray) -> np.ndarray:
    return np.clip(np.asarray(edge_probs, dtype=float), 0.0, _P_CLIP_MAX)


def aggregate(
    edge_probs: np.ndarray,
    edge_lengths: np.ndarray | None = None,
    *,
    method: str = "hazard",
    tau: float = 0.5,
) -> float:
    """edge_probs(사고확률)을 route 단위 스칼라 위험도로 집계.

    method:
        "hazard" (권장, §4.5-3) : 1 - exp(-Σ h_i*L_i) = 1 - Π(1-p_i)
        "mean"                  : 평균 — 위험구간이 경로 길이에 희석됨
        "max"                   : 최댓값 — 위험구간 개수 정보 손실
        "sum"                   : 합 — 경로 길이(엣지 수)에 비례해 왜곡
        "count"                 : 임계값 tau 초과 edge 개수
    """
    p = _clip_probs(edge_probs)
    if p.size == 0:
        return 0.0

    if method == "hazard":
        # h_i * L_i = -ln(1-p_i) 이므로 L_i 값 자체는 상쇄되어 필요 없다(개념적 근거만 유지).
        return float(1.0 - np.exp(np.sum(np.log1p(-p))))
    if method == "mean":
        return float(np.mean(p))
    if method == "max":
        return float(np.max(p))
    if method == "sum":
        return float(np.sum(p))
    if method == "count":
        return float(np.sum(p > tau))
    raise ValueError(f"알 수 없는 method: {method} (hazard|mean|max|sum|count)")


def route_risk(edge_probs: np.ndarray, edge_lengths: np.ndarray | None = None) -> float:
    """§4.5-3 권장안(hazard-rate 생존모델)의 route-risk 편의 함수."""
    return aggregate(edge_probs, edge_lengths, method="hazard")
