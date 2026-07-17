"""수집 오케스트레이터: 라벨 지점 -> 이미지 다운로드 + torchvision ImageFolder 레이아웃 + manifest.

디스크 레이아웃(torchvision.datasets.ImageFolder 호환):
    <data>/streetview/accident/<point_id>[_h###].jpg
    <data>/streetview/control/<point_id>[_h###].jpg
    <data>/manifest.csv   # point_id,label,class,lat,lon,heading,severity,mode,path

캐시: 이미 파일이 존재하면 재다운로드하지 않음(중단 후 재개 안전).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pandas as pd

from ..utils.config import Config, DEFAULT_CONFIG
from ..utils.streetview import StreetViewProvider, get_provider

if TYPE_CHECKING:
    import geopandas as gpd

CLASS_NAMES = {1: "accident", 0: "control"}


def _headings_for(row, cfg: Config) -> list[float]:
    base = row.get("heading")
    configured = cfg.streetview.headings
    if configured:
        return [float(h) for h in configured]
    if base is None or pd.isna(base):
        # 방위각 미상 지점: 4방위로 촬영
        return [0.0, 90.0, 180.0, 270.0]
    return [float(base)]


def collect_images(
    labeled_points: "gpd.GeoDataFrame",
    cfg: Config = DEFAULT_CONFIG,
    provider: StreetViewProvider | None = None,
    *,
    limit: int | None = None,
) -> pd.DataFrame:
    """labeled_points(build_labeled_points 출력) 를 순회하며 이미지 수집 + manifest 작성.

    반환: manifest DataFrame. 실패/커버리지 없음 지점은 manifest 에서 제외.
    """
    cfg.ensure_dirs()
    for cls in CLASS_NAMES.values():
        (cfg.images_dir / cls).mkdir(parents=True, exist_ok=True)

    provider = provider or get_provider(cfg)

    records: list[dict] = []
    rows = labeled_points.iloc[:limit] if limit else labeled_points
    total = len(rows)
    for i, (_, row) in enumerate(rows.iterrows(), 1):
        label = int(row["label"])
        cls = CLASS_NAMES[label]
        for heading in _headings_for(row, cfg):
            pid = str(row["point_id"])
            fname = f"{pid}_h{int(round(heading)):03d}.jpg"
            out_path = cfg.images_dir / cls / fname

            if not out_path.exists():
                try:
                    img = provider.fetch(float(row["lat"]), float(row["lon"]), heading)
                except Exception as e:  # noqa: BLE001
                    print(f"[collect] {pid} h{heading} 실패: {e}")
                    continue
                if img is None:
                    continue  # 커버리지 없음
                out_path.write_bytes(img)

            records.append(
                {
                    "point_id": pid,
                    "label": label,
                    "class": cls,
                    "lat": float(row["lat"]),
                    "lon": float(row["lon"]),
                    "heading": round(float(heading), 1),
                    "severity": row.get("severity"),
                    "mode": row.get("mode"),
                    "path": str(out_path.relative_to(cfg.data_dir)),
                }
            )
        if i % 100 == 0 or i == total:
            print(f"[collect] {i}/{total} 지점 처리")

    manifest = pd.DataFrame.from_records(records)
    if not manifest.empty:
        manifest.to_csv(cfg.manifest_path, index=False, encoding="utf-8-sig")
        print(f"[collect] manifest 저장: {cfg.manifest_path} ({len(manifest)} 이미지)")
    else:
        print("[collect] 수집된 이미지가 없습니다(커버리지/키/약관 확인).")
    return manifest


def run_pipeline(
    cfg: Config = DEFAULT_CONFIG,
    *,
    source: str = "koroad",
    pm_only: bool = True,
    limit: int | None = None,
) -> pd.DataFrame:
    """전체 수집 파이프라인 원샷 실행.

    사고 로드 -> OSM edge -> 지점 샘플링 -> negative 매칭 -> 라벨결합 -> 이미지 수집.
    각 단계 산출물은 data/ 에 캐시된다.

    source:
        "koroad" (기본) — KoROAD 이륜차 교통사고 다발지역 오픈API 자동 다운로드.
        "taas"          — data/raw/ 의 수동 다운로드 CSV/XLSX 사용.
    """
    from ..utils import geo, negatives

    print(f"[pipeline] 1/5 사고 로드 (source={source})")
    if source == "koroad":
        from ..utils import koroad
        accidents = koroad.download_to_raw(cfg, kind="motorcycle")
    elif source == "taas":
        from ..utils import taas
        accidents = taas.load_taas_files(cfg, pm_only=pm_only)
    else:
        raise ValueError(f"알 수 없는 source: {source} (koroad|taas)")

    print("[pipeline] 2/5 OSM 도로망 로드")
    edges = geo.load_drive_edges(cfg)

    print("[pipeline] 3/5 사고 스냅 + 도로 지점 샘플링")
    acc_snapped = geo.snap_accidents_to_edges(accidents, edges, cfg)
    candidates = geo.sample_points_along_edges(edges, cfg)

    print("[pipeline] 4/5 exposure-matched negative 샘플링")
    negs = negatives.sample_negatives(acc_snapped, candidates, cfg)
    labeled = negatives.build_labeled_points(acc_snapped, negs)
    cfg.ensure_dirs()
    labeled.to_file(cfg.points_path, driver="GPKG")
    print(f"[pipeline] 라벨 지점 저장: {cfg.points_path} "
          f"(pos={int((labeled.label==1).sum())}, neg={int((labeled.label==0).sum())})")

    print("[pipeline] 5/5 이미지 수집")
    return collect_images(labeled, cfg, limit=limit)
