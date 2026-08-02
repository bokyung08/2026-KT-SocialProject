"""irl — Bradley-Terry 기반 IRL 가중치 학습 (PROJECT.md §4.2, §4.4, §4.5-3).

teacher(이미지 위험도 모델)의 edge-risk 를 route-risk 로 집계하고, 경로쌍 선호
라벨로부터 비용함수 가중치 w1~w5 를 Bradley-Terry 랭킹 로스로 학습한다.
numpy/scipy 기반 (offline 학습 단계). 학습 완료 후에는 고정된 선형 비용함수만
서비스에 배포된다(§4.2) — 서빙 시점에 이 모듈이나 teacher 호출은 없다.

구성:
    route 위험 집계 (§4.5-3)
        aggregate() / route_risk()  : edge 사고확률 -> route 위험도(hazard-rate 등)
    Bradley-Terry 가중치 학습 (§4.2)
        route_features()            : route 원시 지표 -> 5-차원 feature 벡터
        make_preference_pairs()     : route 목록 -> (X_A, X_B, prefer) 선호쌍
        fit_bradley_terry()         : 선호쌍 -> 비용 가중치 w1~w5 (nonneg)
        learn_weights_from_routes() : 위 단계를 잇는 편의 함수
        BTResult                    : 학습 결과 dataclass
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.optimize import minimize

# --------------------------------------------------------------------------- #
# route 위험 집계 (§4.5-3)
#
# edge 단위 사고 위험확률을 route(경로) 단위 위험도로 집계. hazard-rate 기반
# 생존모델을 기본(권장)으로, 비교용으로 mean/max/sum/count 베이스라인도 제공.
#
#     route_risk = 1 - exp(-Σ h_i * L_i),   h_i = -ln(1 - p_i) / L_i
#                = 1 - Π (1 - p_i)
#
# - p_i : edge i 의 사고확률(teacher 모델 출력, [0,1))
# - L_i : edge i 의 길이(m). hazard 형태에서는 h_i*L_i = -ln(1-p_i) 로 상쇄되어
#         route_risk 계산에는 길이가 다시 등장하지 않지만(닫힌 형태가 곱으로 축약),
#         길이는 각 edge 의 "노출량"을 표현하는 개념적 근거로 남겨둔다.
# --------------------------------------------------------------------------- #

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
        "mean"                  : 평균 - 위험구간이 경로 길이에 희석됨
        "max"                   : 최댓값 - 위험구간 개수 정보 손실
        "sum"                   : 합 - 경로 길이(엣지 수)에 비례해 왜곡
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


# --------------------------------------------------------------------------- #
# Bradley-Terry 가중치 학습 (§4.2)
#
#     P(A ≻ B) = sigmoid(w·x_A - w·x_B)
#     Loss = -Σ log P(선호된 경로 ≻ 비선호 경로) + l2*||w||^2
#
# 로지스틱 회귀와 동일한 convex 최적화. w >= 0 제약을 걸어 해석 가능한(가중합)
# 형태를 유지한다(거리/차도/전환/교차로/버스 페널티가 비용을 늘리는 방향으로만).
# 학습된 w 는 고정 선형 비용함수로 실서비스(A*)에 주입된다.
# --------------------------------------------------------------------------- #

# feature 순서: [거리, 차도, 전환, 교차로, 버스겹침] — kt.dinjae.pm_safeline.PmCostWeights(w1..w5)와 대응
FEATURE_NAMES = ("distance", "arterial", "transition", "crossing", "bus")
N_FEATURES = len(FEATURE_NAMES)


@dataclass
class BTResult:
    """fit_bradley_terry 결과."""

    weights: np.ndarray  # shape (5,), w1..w5 (nonneg 제약 시 모두 >= 0)
    loss: float
    n_pairs: int
    converged: bool


def route_features(
    distance_km: float,
    arterial: float,
    transition_count: float,
    crossing_count: float,
    bus_overlap: float,
) -> np.ndarray:
    """route 의 원시 지표를 비용함수 feature 벡터 [거리, 차도, 전환, 교차로, 버스] 로 매핑.

    - distance_km       : 경로 총 거리(km)
    - arterial          : 차도구간 비율 또는 길이(호출 측에서 단위 통일해 전달)
    - transition_count  : 도로유형 전환 횟수
    - crossing_count    : 교차로/횡단보도 통과 횟수
    - bus_overlap       : 버스노선과 겹치는 구간(비율 또는 길이, 호출 측 단위 통일)

    단순 항등 매핑(입력 자체가 이미 비용함수의 5개 항에 대응) — 필요 시 이 함수에서만
    스케일링/정규화를 조정하면 나머지 IRL 파이프라인은 그대로 재사용 가능.
    """
    return np.array(
        [distance_km, arterial, transition_count, crossing_count, bus_overlap],
        dtype=float,
    )


def _bt_neg_log_likelihood(w: np.ndarray, diff: np.ndarray, l2: float) -> float:
    """diff = x_other - x_preferred. score = w·diff, P(preferred) = sigmoid(score).

    x 는 비용(페널티) feature — 값이 클수록 위험/비용이 큼. 선호(preferred)된 경로는
    cost(=w·x) 가 더 낮으므로, score = w·x_other - w·x_preferred = cost(other) - cost(preferred)
    는 preferred 가 실제로 더 안전할 때 양수가 되고, sigmoid(score) 가 P(preferred) 를 높게
    준다(비용이 작을수록 선호될 확률이 커지는 표준 로지스틱 회귀와 동일한 부호 규약).
    """
    score = diff @ w
    # log(sigmoid(score)) = -softplus(-score) — 수치적으로 안정적인 형태
    log_p = -np.logaddexp(0.0, -score)
    nll = -np.sum(log_p)
    return float(nll + l2 * np.sum(w**2))


def _bt_grad(w: np.ndarray, diff: np.ndarray, l2: float) -> np.ndarray:
    score = diff @ w
    p = 1.0 / (1.0 + np.exp(-score))  # sigmoid
    grad = -diff.T @ (1.0 - p) + 2.0 * l2 * w
    return grad


def fit_bradley_terry(
    X_pairs: np.ndarray | None = None,
    prefer: np.ndarray | None = None,
    *,
    X_A: np.ndarray | None = None,
    X_B: np.ndarray | None = None,
    nonneg: bool = True,
    l2: float = 1e-4,
    w0: np.ndarray | None = None,
) -> BTResult:
    """Bradley-Terry 가중치 학습.

    두 가지 호출 방식 지원:
        1) fit_bradley_terry(X_pairs, prefer) : X_pairs 는 이미 (x_other - x_preferred) 로
           계산된 (N,5) feature 차이(비용 감소 방향, _bt_neg_log_likelihood 참고).
           prefer 는 무시(호환용, None 허용).
        2) fit_bradley_terry(X_A=X_A, X_B=X_B, prefer=prefer) : X_A/X_B 는 (N,5) 원본 feature,
           prefer[i]=1 이면 A 가 선호(더 안전, risk 더 낮음), 0 이면 B 가 선호.
           내부에서 (x_other - x_preferred) 차이를 계산.

    nonneg=True 면 L-BFGS-B 로 w>=0 제약 하에 최소화(§4.2 해석 가능성 요구).
    """
    if X_A is not None and X_B is not None:
        if prefer is None:
            raise ValueError("X_A/X_B 사용 시 prefer 배열이 필요합니다.")
        X_A = np.asarray(X_A, dtype=float)
        X_B = np.asarray(X_B, dtype=float)
        prefer = np.asarray(prefer)
        # diff = x_other - x_preferred (비용 감소 방향, docstring/_bt_neg_log_likelihood 참고)
        diff = np.where(prefer[:, None] == 1, X_B - X_A, X_A - X_B)
    elif X_pairs is not None:
        diff = np.asarray(X_pairs, dtype=float)
    else:
        raise ValueError("X_pairs 또는 (X_A, X_B, prefer) 중 하나는 필요합니다.")

    n_pairs = diff.shape[0]
    if n_pairs == 0:
        raise ValueError("학습할 pair 가 없습니다.")

    n_features = diff.shape[1]
    w0 = np.zeros(n_features) if w0 is None else np.asarray(w0, dtype=float)

    bounds = [(0.0, None)] * n_features if nonneg else None
    result = minimize(
        _bt_neg_log_likelihood,
        w0,
        args=(diff, l2),
        jac=_bt_grad,
        method="L-BFGS-B",
        bounds=bounds,
    )

    return BTResult(
        weights=result.x,
        loss=float(result.fun),
        n_pairs=n_pairs,
        converged=bool(result.success),
    )


def make_preference_pairs(
    routes: list,
    route_risks: np.ndarray,
    n_pairs: int,
    seed: int | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """route 목록에서 (X_A, X_B, prefer) 선호쌍 샘플링.

    routes[i] 는 route_features() 로 만든 (5,) feature 벡터(또는 그렇게 변환 가능한 배열)여야
    하고, route_risks[i] 는 teacher 로 계산한 해당 route 의 route_risk(낮을수록 안전).
    prefer[k]=1 이면 route A 가 더 안전(risk 더 낮음)해서 선호됨, 0 이면 B 가 선호됨.
    """
    rng = np.random.default_rng(seed)
    routes_arr = np.asarray(routes, dtype=float)
    risks = np.asarray(route_risks, dtype=float)
    n_routes = routes_arr.shape[0]
    if n_routes < 2:
        raise ValueError("선호쌍을 만들려면 route 가 최소 2개 필요합니다.")

    idx_a = rng.integers(0, n_routes, size=n_pairs)
    idx_b = rng.integers(0, n_routes, size=n_pairs)
    # A==B 인 쌍은 재추첨(비교 불가능한 자기쌍 방지)
    same = idx_a == idx_b
    while np.any(same):
        idx_b[same] = rng.integers(0, n_routes, size=int(same.sum()))
        same = idx_a == idx_b

    X_A = routes_arr[idx_a]
    X_B = routes_arr[idx_b]
    prefer = (risks[idx_a] < risks[idx_b]).astype(int)
    return X_A, X_B, prefer


def learn_weights_from_routes(
    routes: list,
    edge_risk_fn,
    *,
    n_pairs: int = 200,
    seed: int | None = None,
    nonneg: bool = True,
    l2: float = 1e-4,
) -> np.ndarray:
    """route_risk 집계 + 선호쌍 샘플링 + Bradley-Terry 학습을 잇는 편의 함수.

    routes: 각 원소가 (feature_vector(5,), edge_probs, edge_lengths) 튜플인 리스트.
    edge_risk_fn: (edge_probs, edge_lengths) -> route_risk 스칼라 (예: route_risk).

    반환: 학습된 weights (shape (5,)).
    """
    feats = np.array([r[0] for r in routes], dtype=float)
    risks = np.array([edge_risk_fn(r[1], r[2]) for r in routes], dtype=float)
    X_A, X_B, prefer = make_preference_pairs(feats, risks, n_pairs, seed=seed)
    result = fit_bradley_terry(X_A=X_A, X_B=X_B, prefer=prefer, nonneg=nonneg, l2=l2)
    return result.weights
