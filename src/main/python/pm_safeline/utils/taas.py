"""TAAS(교통사고분석시스템) PM/자전거 사고 지점 로더.

메모리(pm-pilot-study)·PROJECT.md §4.5 근거:
    - data.go.kr / TAAS 직접 자동다운로드는 anti-bot 차단 -> **수동 다운로드** 전제.
    - 사용자가 `data/raw/` 에 내려받은 CSV/XLSX 를 넣으면 이 모듈이 표준 스키마로 로드.

TAAS 다운로드 CSV 는 연도·조회유형별로 컬럼명이 제각각이라, 위경도·일시·심각도
컬럼을 휴리스틱으로 탐지해 정규화한다. 좌표가 없고 주소만 있는 경우는 지오코딩이
필요하므로 경고 후 제외(별도 지오코딩은 범위 밖).

표준 출력 스키마(GeoDataFrame, WGS84):
    accident_id, datetime, lat, lon, severity, mode, geometry(Point)
"""

from __future__ import annotations

import glob
import re
from pathlib import Path
from typing import TYPE_CHECKING

import numpy as np
import pandas as pd

from .config import Config, DEFAULT_CONFIG, SEVERITY_ORDER

if TYPE_CHECKING:
    import geopandas as gpd

# 컬럼 탐지용 후보(부분일치, 소문자/공백 제거 후 비교)
_LAT_KEYS = ["위도", "lat", "ycoord", "y", "경도위도"]
_LON_KEYS = ["경도", "lon", "lng", "xcoord", "x"]
_TIME_KEYS = ["발생일시", "사고일시", "일시", "datetime", "발생년월일시"]
_SEV_KEYS = ["사고내용", "상해정도", "심각도", "severity", "피해정도"]
# PM/자전거 필터에 쓸 컬럼(가해/피해 당사자종별 등)
_MODE_KEYS = ["당사자종별", "차종", "가해자법규위반", "사고유형", "당사자"]

_PM_PATTERNS = re.compile(r"(개인형이동|PM|전동킥보드|퍼스널모빌리티|원동기|이륜|자전거)", re.IGNORECASE)


def _canon(col: str) -> str:
    return re.sub(r"[\s_\-()]", "", str(col)).lower()


def _find_col(cols: list[str], keys: list[str]) -> str | None:
    canon = {c: _canon(c) for c in cols}
    for key in keys:
        k = _canon(key)
        for orig, cc in canon.items():
            if k in cc:
                return orig
    return None


def _read_any(path: Path) -> pd.DataFrame:
    """CSV(utf-8/cp949) 또는 XLSX 자동 판별 로드."""
    if path.suffix.lower() in {".xlsx", ".xls"}:
        return pd.read_excel(path)
    for enc in ("utf-8-sig", "cp949", "utf-8"):
        try:
            return pd.read_csv(path, encoding=enc)
        except (UnicodeDecodeError, pd.errors.ParserError):
            continue
    # 마지막 시도: 인코딩 오류 무시
    return pd.read_csv(path, encoding="cp949", encoding_errors="ignore")


def _norm_severity(v) -> str:
    s = str(v)
    if "사망" in s:
        return "사망"
    if "중상" in s:
        return "중상"
    if "경상" in s or "부상" in s or "경미" in s:
        return "경상"
    return "경상"  # 미상은 보수적으로 경상 처리


def load_taas_files(cfg: Config = DEFAULT_CONFIG, *, pm_only: bool = True) -> "gpd.GeoDataFrame":
    """`data/raw/` 의 모든 TAAS 파일을 병합·정규화해 GeoDataFrame 반환.

    파일이 하나도 없으면 FileNotFoundError. bbox 밖 지점은 제외.
    """
    import geopandas as gpd
    from shapely.geometry import Point

    patterns = ["*.csv", "*.xlsx", "*.xls"]
    files: list[Path] = []
    for pat in patterns:
        files += [Path(p) for p in glob.glob(str(cfg.raw_dir / pat))]
    files = sorted(f for f in files if not f.name.startswith("~"))
    if not files:
        raise FileNotFoundError(
            f"TAAS 원본이 없습니다: {cfg.raw_dir}/*.csv|xlsx 를 수동 다운로드해 넣으세요 "
            "(koroad.or.kr TAAS, 지점 조회/다운로드)."
        )

    frames: list[pd.DataFrame] = []
    for f in files:
        try:
            df = _read_any(f)
        except Exception as e:  # noqa: BLE001 — 파일별 실패는 건너뜀
            print(f"[taas] {f.name} 읽기 실패, 건너뜀: {e}")
            continue
        norm = _normalize_frame(df, source=f.name, pm_only=pm_only)
        if norm is not None and len(norm):
            frames.append(norm)

    if not frames:
        raise ValueError("TAAS 파일에서 위경도/일시 컬럼을 찾지 못했습니다. 컬럼명을 확인하세요.")

    merged = pd.concat(frames, ignore_index=True)
    merged = merged.dropna(subset=["lat", "lon"]).reset_index(drop=True)

    # bbox 클리핑
    w, s, e, n = cfg.bbox
    in_box = merged["lat"].between(s, n) & merged["lon"].between(w, e)
    dropped = int((~in_box).sum())
    if dropped:
        print(f"[taas] bbox 밖 {dropped}건 제외")
    merged = merged[in_box].reset_index(drop=True)

    merged["accident_id"] = np.arange(1, len(merged) + 1)
    gdf = gpd.GeoDataFrame(
        merged,
        geometry=[Point(xy) for xy in zip(merged["lon"], merged["lat"])],
        crs="EPSG:4326",
    )
    return gdf[["accident_id", "datetime", "lat", "lon", "severity", "mode", "geometry"]]


def _normalize_frame(df: pd.DataFrame, *, source: str, pm_only: bool) -> pd.DataFrame | None:
    cols = list(df.columns)
    lat_c, lon_c = _find_col(cols, _LAT_KEYS), _find_col(cols, _LON_KEYS)
    if lat_c is None or lon_c is None:
        print(f"[taas] {source}: 위경도 컬럼 미탐지 -> 건너뜀")
        return None

    out = pd.DataFrame()
    out["lat"] = pd.to_numeric(df[lat_c], errors="coerce")
    out["lon"] = pd.to_numeric(df[lon_c], errors="coerce")

    time_c = _find_col(cols, _TIME_KEYS)
    out["datetime"] = pd.to_datetime(df[time_c], errors="coerce") if time_c else pd.NaT

    sev_c = _find_col(cols, _SEV_KEYS)
    out["severity"] = df[sev_c].map(_norm_severity) if sev_c else "경상"

    mode_c = _find_col(cols, _MODE_KEYS)
    if mode_c is not None:
        out["mode"] = df[mode_c].astype(str)
        if pm_only:
            mask = out["mode"].str.contains(_PM_PATTERNS, na=False)
            out = out[mask]
    else:
        out["mode"] = "unknown"
        if pm_only:
            print(f"[taas] {source}: 당사자종별 컬럼 없음 -> PM 필터 미적용(전량 유지)")

    return out.reset_index(drop=True)
