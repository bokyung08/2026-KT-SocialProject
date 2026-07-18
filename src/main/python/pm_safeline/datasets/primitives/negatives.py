"""Exposure-matched negative 샘플링 (PROJECT.md §4.5-(2)).

문제: 단순 랜덤 지점으로 negative 를 뽑으면 '노출(통행량) 편향' 발생 —
통행 많은 번화가가 사고도 많고 이미지도 번화가처럼 보여, 모델이 도로 위험구조
대신 '번화가처럼 보이는지'를 학습할 위험.

완화: positive(사고) 지점의 exposure 분포를 대리지표로 층화(stratify)해,
같은 exposure bin 에서 negative 를 뽑는다. 실제 KT 이동량 데이터가 없으므로
대리 exposure 로 **도로 위계(highway rank)** 를 기본 사용하고, 옵션으로 외부
exposure 컬럼(예: 통행량 join 결과)이 있으면 그 값을 사용한다.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np
import pandas as pd

from .config import EXPOSURE_BINS, METRIC_CRS, NEGATIVE_RATIO, SEED

if TYPE_CHECKING:
    import geopandas as gpd

# 도로 위계 -> 대리 exposure 순위(클수록 통행량 많다고 가정)
_HIGHWAY_RANK = {
    "motorway": 6, "trunk": 6, "primary": 5, "primary_link": 5,
    "secondary": 4, "secondary_link": 4, "tertiary": 3, "tertiary_link": 3,
    "residential": 2, "living_street": 2, "unclassified": 2,
    "service": 1, "cycleway": 1, "footway": 1, "path": 1, "pedestrian": 1,
}


def _exposure_score(highway: str, override: float | None = None) -> float:
    if override is not None and not (isinstance(override, float) and np.isnan(override)):
        return float(override)
    return float(_HIGHWAY_RANK.get(str(highway), 2))


def sample_negatives(
    accidents: "gpd.GeoDataFrame",
    candidate_points: "gpd.GeoDataFrame",
    *,
    min_dist_m: float = 60.0,
    exposure_col: str | None = None,
    exposure_bins: int = EXPOSURE_BINS,
    negative_ratio: float = NEGATIVE_RATIO,
    seed: int = SEED,
    metric_crs: str = METRIC_CRS,
) -> "gpd.GeoDataFrame":
    """사고 지점의 exposure 분포에 맞춰 candidate_points 에서 negative 추출.

    인자:
        accidents        : snap_accidents_to_edges 결과 (highway/exposure 포함 권장)
        candidate_points : sample_points_along_edges 결과 (highway 포함)
        min_dist_m       : 사고 지점 인접 완충거리 — 이 안의 후보는 negative 제외
        exposure_col     : 명시 exposure 컬럼명(있으면 highway rank 대신 사용)

    반환: candidate_points 부분집합 + label=0, exposure_bin 컬럼.
    """
    rng = np.random.default_rng(seed)

    # 1) 사고 인접 완충대 제거 (positive 근처를 negative 로 오분류 방지)
    cand = _drop_near_accidents(candidate_points, accidents, min_dist_m, metric_crs=metric_crs)
    if cand.empty:
        raise ValueError("완충대 제거 후 negative 후보가 없습니다. min_dist_m 를 줄이세요.")

    # 2) exposure 점수 계산
    acc_exp = accidents.apply(
        lambda r: _exposure_score(r.get("highway"), r.get(exposure_col) if exposure_col else None),
        axis=1,
    ).to_numpy()
    cand_exp = cand.apply(
        lambda r: _exposure_score(r.get("highway"), r.get(exposure_col) if exposure_col else None),
        axis=1,
    ).to_numpy()

    # 3) 사고 exposure 분포를 분위수 bin 으로 -> bin 별 목표 개수 산정
    edges = _quantile_edges(acc_exp, exposure_bins)
    acc_bin = np.clip(np.digitize(acc_exp, edges[1:-1]), 0, exposure_bins - 1)
    cand_bin = np.clip(np.digitize(cand_exp, edges[1:-1]), 0, exposure_bins - 1)

    n_pos = len(accidents)
    target_total = int(round(n_pos * negative_ratio))
    bin_frac = np.bincount(acc_bin, minlength=exposure_bins) / max(1, n_pos)

    chosen_idx: list[int] = []
    cand_reset = cand.reset_index(drop=True)
    for b in range(exposure_bins):
        pool = np.where(cand_bin == b)[0]
        if pool.size == 0:
            continue
        want = int(round(target_total * bin_frac[b]))
        want = min(want, pool.size)
        if want <= 0:
            continue
        chosen_idx.extend(rng.choice(pool, size=want, replace=False).tolist())

    neg = cand_reset.iloc[sorted(set(chosen_idx))].copy()
    neg["label"] = 0
    neg["exposure_bin"] = np.clip(
        np.digitize(
            neg.apply(
                lambda r: _exposure_score(r.get("highway"), r.get(exposure_col) if exposure_col else None),
                axis=1,
            ).to_numpy(),
            edges[1:-1],
        ),
        0,
        exposure_bins - 1,
    )
    return neg.reset_index(drop=True)


def _quantile_edges(values: np.ndarray, bins: int) -> np.ndarray:
    qs = np.linspace(0, 1, bins + 1)
    edges = np.quantile(values, qs)
    # 동일값 반복 시 단조증가 보장
    return np.maximum.accumulate(edges)


def _drop_near_accidents(
    candidates: "gpd.GeoDataFrame",
    accidents: "gpd.GeoDataFrame",
    min_dist_m: float,
    *,
    metric_crs: str = METRIC_CRS,
) -> "gpd.GeoDataFrame":
    import geopandas as gpd

    cand_m = candidates.to_crs(metric_crs)
    acc_m = accidents.to_crs(metric_crs)
    buffer = acc_m.geometry.buffer(min_dist_m).union_all() if hasattr(
        acc_m.geometry, "union_all"
    ) else acc_m.geometry.buffer(min_dist_m).unary_union
    keep = ~cand_m.geometry.intersects(buffer)
    return candidates.loc[keep.values].copy()


def build_labeled_points(
    accidents: "gpd.GeoDataFrame",
    negatives: "gpd.GeoDataFrame",
) -> "gpd.GeoDataFrame":
    """positive(label=1) + negative(label=0) 을 하나의 수집대상 테이블로 결합.

    공통 스키마: point_id, label, lat, lon, heading, severity, mode, geometry
    """
    import geopandas as gpd

    pos = accidents.copy()
    pos["label"] = 1
    pos["point_id"] = ["acc_%06d" % i for i in range(len(pos))]

    neg = negatives.copy()
    neg["severity"] = neg.get("severity", "none")
    neg["mode"] = neg.get("mode", "none")
    neg["point_id"] = ["neg_%06d" % i for i in range(len(neg))]

    common = ["point_id", "label", "heading", "severity", "mode", "geometry"]
    for col in common:
        if col not in pos.columns:
            pos[col] = np.nan
        if col not in neg.columns:
            neg[col] = np.nan

    out = pd.concat([pos[common], neg[common]], ignore_index=True)
    out = gpd.GeoDataFrame(out, geometry="geometry", crs="EPSG:4326")
    out["lat"] = out.geometry.y
    out["lon"] = out.geometry.x
    return out
