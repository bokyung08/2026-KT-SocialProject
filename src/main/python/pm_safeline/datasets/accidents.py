"""사고 지점 데이터셋 (AccidentDataset).

KoROAD 오픈API / TAAS 수동 CSV 등 여러 소스를 **하나의 표준 스키마**로 통합하는
도메인 데이터셋 추상화. `utils/`(koroad API 클라이언트·taas 파서)는 "어떻게 가져오나"의
저수준 primitive 이고, 이 클래스는 "사고 데이터셋"이라는 계약을 명시적으로 강제한다.

주의: 이것은 torch 학습용 Dataset 이 아니다(배치로 학습하는 게 아니라 파이프라인 소스
데이터임). 로드뷰 이미지 학습셋은 [pm_safeline.datasets.roadview.PMRoadviewDataset] 이다.

표준 스키마(GeoDataFrame, WGS84):
    accident_id:int, datetime:datetime|NaT, lat:float, lon:float,
    severity:{경상,중상,사망}, mode:str, geometry:Point
    (소스별 부가 컬럼 — 예: KoROAD occrrnc_cnt/spot_nm — 은 그대로 보존된다.)
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

import pandas as pd

from ..utils.config import Config, DEFAULT_CONFIG

if TYPE_CHECKING:
    import geopandas as gpd

CORE_COLUMNS = ["accident_id", "datetime", "lat", "lon", "severity", "mode", "geometry"]
SEVERITY_LEVELS = ("경상", "중상", "사망")
WGS84 = "EPSG:4326"


class SchemaError(ValueError):
    """사고 데이터가 표준 스키마를 만족하지 않을 때."""


class AccidentDataset:
    """표준 스키마로 검증된 사고 지점 데이터셋."""

    def __init__(self, gdf: "gpd.GeoDataFrame", *, source: str = "unknown"):
        self.gdf = _validate(gdf)
        self.source = source

    # ---- 소스별 로더 ------------------------------------------------------
    @classmethod
    def from_koroad(
        cls, cfg: Config = DEFAULT_CONFIG, *, kind: str = "motorcycle", **kw
    ) -> "AccidentDataset":
        """KoROAD 교통사고 다발지역 오픈API 에서 로드(+ data/raw 캐시)."""
        from ..utils import koroad

        gdf = koroad.download_to_raw(cfg, kind=kind, **kw)
        return cls(gdf, source=f"koroad:{kind}")

    @classmethod
    def from_taas(
        cls, cfg: Config = DEFAULT_CONFIG, *, pm_only: bool = True, **kw
    ) -> "AccidentDataset":
        """data/raw/ 의 수동 다운로드 TAAS CSV/XLSX 에서 로드."""
        from ..utils import taas

        gdf = taas.load_taas_files(cfg, pm_only=pm_only, **kw)
        return cls(gdf, source="taas")

    @classmethod
    def load(cls, source: str = "koroad", cfg: Config = DEFAULT_CONFIG, **kw) -> "AccidentDataset":
        """source("koroad"|"taas") 로 로드하는 통합 진입점."""
        if source == "koroad":
            return cls.from_koroad(cfg, **kw)
        if source == "taas":
            return cls.from_taas(cfg, **kw)
        raise ValueError(f"알 수 없는 source: {source} (koroad|taas)")

    @classmethod
    def load_file(cls, path: str | Path) -> "AccidentDataset":
        """저장된 GeoPackage/CSV 에서 로드."""
        import geopandas as gpd

        path = Path(path)
        if path.suffix.lower() == ".gpkg":
            gdf = gpd.read_file(path)
        else:
            df = pd.read_csv(path)
            gdf = gpd.GeoDataFrame(
                df, geometry=gpd.points_from_xy(df["lon"], df["lat"]), crs=WGS84
            )
        return cls(gdf, source=str(path))

    # ---- 접근/변환 --------------------------------------------------------
    def to_geodataframe(self) -> "gpd.GeoDataFrame":
        return self.gdf

    def __len__(self) -> int:
        return len(self.gdf)

    def __repr__(self) -> str:
        return f"AccidentDataset(n={len(self)}, source={self.source!r})"

    def severity_counts(self) -> dict[str, int]:
        return self.gdf["severity"].value_counts().to_dict()

    def filter_recent(self, min_year: int) -> "AccidentDataset":
        """min_year 이후 사고만(§4.5-4 촬영-사고 시간차 완화). datetime 결측은 유지."""
        dt = pd.to_datetime(self.gdf["datetime"], errors="coerce")
        keep = dt.isna() | (dt.dt.year >= min_year)
        return AccidentDataset(self.gdf[keep].copy(), source=self.source)

    def save(self, path: str | Path | None = None, cfg: Config = DEFAULT_CONFIG) -> Path:
        """GeoPackage 로 저장(기본: data/accidents.gpkg)."""
        path = Path(path) if path else cfg.data_dir / "accidents.gpkg"
        path.parent.mkdir(parents=True, exist_ok=True)
        self.gdf.to_file(path, driver="GPKG")
        return path


def _validate(gdf) -> "gpd.GeoDataFrame":
    """코어 컬럼 존재·CRS·severity 값·좌표 유효성을 검증하고 표준형으로 정규화."""
    import geopandas as gpd

    if not isinstance(gdf, gpd.GeoDataFrame):
        raise SchemaError("GeoDataFrame 이 아닙니다.")
    missing = [c for c in CORE_COLUMNS if c not in gdf.columns]
    if missing:
        raise SchemaError(f"필수 컬럼 누락: {missing} (필요: {CORE_COLUMNS})")

    out = gdf.copy()
    out["accident_id"] = pd.to_numeric(out["accident_id"], errors="coerce").astype("Int64")
    out["datetime"] = pd.to_datetime(out["datetime"], errors="coerce")
    out["lat"] = pd.to_numeric(out["lat"], errors="coerce")
    out["lon"] = pd.to_numeric(out["lon"], errors="coerce")
    out["severity"] = out["severity"].astype(str)
    out["mode"] = out["mode"].astype(str)

    bad_sev = set(out["severity"].unique()) - set(SEVERITY_LEVELS)
    if bad_sev:
        raise SchemaError(f"허용되지 않은 severity 값: {bad_sev} (허용: {SEVERITY_LEVELS})")
    if out[["lat", "lon"]].isna().any().any():
        raise SchemaError("lat/lon 에 결측/비수치 값이 있습니다.")

    if out.crs is None:
        out = out.set_crs(WGS84)
    elif out.crs.to_string() != WGS84:
        out = out.to_crs(WGS84)
    return out
