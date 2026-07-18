"""OSM 도로망 로드 + 도로 위 고정간격 지점/방위각 생성.

핵심 함수:
    load_drive_edges(bbox)          -> GeoDataFrame(edge geometry, WGS84)
    sample_points_along_edges(...) -> GeoDataFrame(point, heading, edge_id)
    snap_points_to_edges(...)      -> 사고점을 최근접 edge에 스냅 + 방위각 부여

방위각(heading)은 스트리트뷰 카메라가 도로를 바라보도록 edge 진행방향으로 계산한다.
osmnx / geopandas / shapely 를 사용한다.
"""


from __future__ import annotations

import math
from typing import TYPE_CHECKING

import numpy as np

from .config import METRIC_CRS, SAMPLE_INTERVAL_M

WGS84_STR = "EPSG:4326"

if TYPE_CHECKING:  # 무거운 import 는 함수 안에서 지연
    import geopandas as gpd


def _bearing_deg(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """(lat1,lon1) -> (lat2,lon2) 초기 방위각(deg, 북=0, 시계방향)."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    x = math.sin(dl) * math.cos(p2)
    y = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(x, y)) + 360.0) % 360.0


def load_drive_graph(bbox: tuple[float, float, float, float]):
    """주어진 bbox 의 주행 가능 도로망을 osmnx 로 받아 edges GeoDataFrame 반환.

    자전거/PM 관점이지만 teacher 학습용 이미지 수집은 '차도 포함' 넓은 도로망을
    대상으로 한다(사고는 차도 합류 지점에서도 발생). network_type='drive'.
    """
    import osmnx as ox

    w, s, e, n = bbox
    # osmnx 2.x: bbox 는 (left, bottom, right, top) 튜플
    graph = ox.graph_from_bbox(bbox=(w, s, e, n), network_type="drive")
    return graph


def load_drive_edges(
    bbox: tuple[float, float, float, float], *, metric_crs: str = METRIC_CRS
) -> "gpd.GeoDataFrame":
    """edges GeoDataFrame(WGS84, geometry=LineString) 반환."""
    import osmnx as ox

    graph = load_drive_graph(bbox)
    edges = ox.graph_to_gdfs(graph, nodes=False, edges=True)
    edges = edges.reset_index()  # u, v, key 를 컬럼으로
    return edges.to_crs(metric_crs)


def sample_points_along_edges(
    edges: "gpd.GeoDataFrame",
    *,
    sample_interval_m: float = SAMPLE_INTERVAL_M,
    metric_crs: str = METRIC_CRS,
) -> "gpd.GeoDataFrame":
    """각 edge 를 따라 `sample_interval_m` 간격으로 지점 생성.

    반환(WGS84): geometry(Point), heading(deg), edge_id, highway
    - edge 를 미터 CRS 에서 등간격 보간 -> 각 지점의 접선 방위각 계산.
    """
    import geopandas as gpd

    step = sample_interval_m
    edges_m = edges if edges.crs and edges.crs.to_string() == metric_crs else edges.to_crs(metric_crs)

    rows: list[dict] = []
    for idx, row in edges_m.iterrows():
        geom = row.geometry
        if geom is None or geom.is_empty or geom.geom_type != "LineString":
            continue
        length = geom.length
        if length == 0:
            continue
        n = max(1, int(length // step))
        for i in range(n + 1):
            d = min(i * step, length)
            pt = geom.interpolate(d)
            # 접선 방위각: 지점 앞뒤 소구간으로 근사
            a = geom.interpolate(max(0.0, d - 1.0))
            b = geom.interpolate(min(length, d + 1.0))
            rows.append(
                {
                    'geometry': pt,
                    'heading_xy': math.degrees(math.atan2(b.x - a.x, b.y - a.y)) % 360.0,
                    'edge_id': f"{row.get('u', idx)}_{row.get('v', '')}_{row.get('key', 0)}",
                    'highway': _norm_highway(row.get("highway")),
                }
            )

    out = gpd.GeoDataFrame(rows, geometry="geometry", crs=metric_crs).to_crs(WGS84_STR)
    out['heading'] = out.pop("heading_xy").round(1)
    return out


def _norm_highway(v) -> str:
    """osmnx highway 태그(리스트일 수 있음)를 단일 문자열로 정규화."""
    if isinstance(v, (list, tuple)):
        return str(v[0]) if v else "unknown"
    return str(v) if v is not None else "unknown"


def snap_accidents_to_edges(
    accidents: "gpd.GeoDataFrame",
    edges: "gpd.GeoDataFrame",
    *,
    metric_crs: str = METRIC_CRS,
) -> "gpd.GeoDataFrame":
    """사고 지점을 최근접 edge 로 스냅하고 도로 방위각을 부여.

    반환: 원본 컬럼 + snapped geometry + heading + edge_id + snap_dist_m
    """
    import geopandas as gpd

    acc_m = accidents.to_crs(metric_crs)
    edges_m = edges.to_crs(metric_crs)

    joined = gpd.sjoin_nearest(acc_m, edges_m, how="left", distance_col="snap_dist_m")
    joined = joined[~joined.index.duplicated(keep="first")].copy()

    headings, edge_ids = [], []
    for _, r in joined.iterrows():
        line = None
        ridx = r.get("index_right")
        if ridx is not None and ridx in edges_m.index:
            line = edges_m.loc[ridx].geometry
        if line is not None and line.geom_type == "LineString":
            d = line.project(r.geometry)
            a = line.interpolate(max(0.0, d - 1.0))
            b = line.interpolate(min(line.length, d + 1.0))
            headings.append(math.degrees(math.atan2(b.x - a.x, b.y - a.y)) % 360.0)
            edge_ids.append(str(ridx))
        else:
            headings.append(float("nan"))
            edge_ids.append("")

    joined['heading'] = np.round(headings, 1)
    joined['edge_id'] = edge_ids
    return joined.to_crs(WGS84_STR)
