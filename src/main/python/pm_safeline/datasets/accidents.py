"""사고 지점 데이터셋 (AccidentDataset) — torchvision 표준.

KoROAD 오픈API / TAAS 수동 CSV 등 여러 소스를 **하나의 표준 스키마**로 통합한다.

- [AccidentDataset] : torchvision 관례를 따르는 Dataset
  (`root, transform, target_transform, download` 생성자 · `__getitem__`→(sample, target) · `__len__`).
  MNIST 처럼 `download=True` 로 소스에서 받아 `root` 에 캐시한다.

표준 스키마(GeoDataFrame, WGS84):
    accident_id:int, datetime:datetime|NaT, lat:float, lon:float,
    severity:{경상,중상,사망}, mode:str, geometry:Point
    (소스별 부가 컬럼 — 예: KoROAD occrrnc_cnt/spot_nm — 은 그대로 보존된다.)
"""

from __future__ import annotations

import glob
import os
import re
import time
from pathlib import Path
from typing import Any, Callable, Iterable, TYPE_CHECKING

import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset
from urllib.parse import unquote

from .primitives.config import default_regions, raw_dir, ensure_dirs, REGIONS

if TYPE_CHECKING:
    import geopandas as gpd

CORE_COLUMNS = ["accident_id", "datetime", "lat", "lon", "severity", "mode", "geometry"]
SEVERITY_LEVELS = ("경상", "중상", "사망")
WGS84 = "EPSG:4326"


class SchemaError(ValueError):
    """사고 데이터가 표준 스키마를 만족하지 않을 때."""


# --------------------------------------------------------------------------- #
# KoROAD(도로교통공단) 교통사고 다발지역 오픈API 자동 다운로더.
#
# PROJECT.md §4.4 step 1 의 사고 지점 확보를, 수동 CSV 대신 공식 오픈API 로 자동화한다.
# PM/자전거 전용 다발지역 API 는 없으므로, 가장 근접한 **이륜차(motorcycle) 교통사고
# 다발지역**을 기본 소스로 사용한다(자전거(bicycle) 엔드포인트도 지원).
#
# 엔드포인트:
#     https://opendata.koroad.or.kr/data/rest/frequentzone/{kind}
#     kind ∈ {motorcycle, bicycle, ...}
#
# 요청 변수(표준):
#     authKey       인증키 (env KOROAD_API_KEY)
#     searchYearCd  연도 (예: 2024)
#     siDo          시도 코드 (대전 = 30)
#     guGun         시군구 코드 (대전: 동구110/중구140/서구170/유성구200/대덕구230)
#     type          json | xml
#     numOfRows     페이지당 개수
#     pageNo        페이지 번호
#
# 응답(예시):
#     {resultCode:"00", items:{item:[{afos_id, sido_sgg_nm, spot_nm, occrrnc_cnt,
#      caslt_cnt, dth_dnv_cnt, se_dnv_cnt, sl_dnv_cnt, wnd_dnv_cnt, geom_json,
#      lo_crd, la_crd}, ...]}, totalCount, numOfRows, pageNo}
#
# 각 item 은 '개별 사고'가 아니라 '다발지역(폴리곤)'이며, 중심좌표(lo_crd,la_crd)와
# 사고건수(occrrnc_cnt)를 갖는다. 이를 위험 positive 지점으로 사용한다.
# --------------------------------------------------------------------------- #
_KOROAD_BASE_URL = "https://opendata.koroad.or.kr/data/rest/frequentzone"

# 시도/시군구 코드는 config.REGIONS 에 정의(전국 확장은 거기 추가).
_KOROAD_DEFAULT_YEARS = tuple(range(2017, 2025))  # 2017~2024


def _api_key(explicit: str | None) -> str:
    key = explicit or os.environ.get("KOROAD_API_KEY")
    if not key:
        raise RuntimeError(
            "KoROAD 인증키가 필요합니다. https://opendata.koroad.or.kr 에서 발급 후 "
            "환경변수 KOROAD_API_KEY 로 지정하세요 (또는 api_key 인자)."
        )
    # 포털이 주는 키는 URL 인코딩(%2B,%2F)되어 있을 수 있다. requests 가 params dict 를
    # 다시 인코딩하므로, 여기서 한 번 디코딩해 이중 인코딩(%252B)을 방지한다.
    # 이미 디코딩된 키(+,/ 포함)는 unquote 가 그대로 두므로 양쪽 모두 안전.
    return unquote(key)


def _severity_from_counts(dth: int, se: int, sl: int) -> str:
    """다발지역의 대표 심각도: 사망>0 이면 사망, 중상>경상 이면 중상, 아니면 경상."""
    if dth and dth > 0:
        return "사망"
    if se >= sl:
        return "중상"
    return "경상"


def _fetch_page(
    session, kind: str, key: str, year: int, sido: str, gugun: str | None,
    page: int, rows: int, timeout: float,
) -> dict:
    params = {
        'authKey': key,
        'searchYearCd': str(year),
        'siDo': sido,
        'type': "json",
        'numOfRows': str(rows),
        'pageNo': str(page),
    }
    if gugun:
        params['guGun'] = gugun
    r = session.get(f"{_KOROAD_BASE_URL}/{kind}", params=params, timeout=timeout)
    r.raise_for_status()
    return r.json()


def _iter_items(payload: dict) -> list[dict]:
    """응답에서 item 배열을 정규화(단일 dict 도 리스트로)."""
    code = str(payload.get("resultCode", ""))
    if code not in ("00", "0", ""):
        msg = payload.get("resultMsg", "")
        # 데이터 없음 코드는 조용히 빈 리스트
        if "NODATA" in str(msg).upper() or code in ("03", "04"):
            return []
        raise RuntimeError(f"KoROAD API 오류 resultCode={code} msg={msg}")
    items = (payload.get("items") or {}).get("item")
    if items is None:
        return []
    return items if isinstance(items, list) else [items]


def _koroad_fetch(
    *,
    regions: tuple[str, ...] | None = None,
    kind: str = "motorcycle",
    years: Iterable[int] = _KOROAD_DEFAULT_YEARS,
    api_key: str | None = None,
    rows: int = 100,
    pause: float = 0.2,
    timeout: float = 15.0,
) -> "gpd.GeoDataFrame":
    """regions 의 모든 지역 {kind} 교통사고 다발지역을 지역×연도×구 순회로 받아 반환.

    반환 스키마(WGS84): accident_id, region, datetime(NaT), lat, lon, severity, mode,
        occrrnc_cnt, caslt_cnt, dth_dnv_cnt, se_dnv_cnt, sl_dnv_cnt, wnd_dnv_cnt,
        year, sido_sgg_nm, spot_nm, geom_json, geometry(Point)
    """
    import geopandas as gpd
    import requests
    from shapely.geometry import Point

    region_names = regions or default_regions()
    key = _api_key(api_key)
    region_objs = [REGIONS[r] for r in region_names if r in REGIONS]
    unknown = [r for r in region_names if r not in REGIONS]
    if unknown:
        print(f"[koroad] 알 수 없는 지역 무시: {unknown} (가능: {list(REGIONS)})")
    if not region_objs:
        raise ValueError(f"수집할 지역이 없습니다: {region_names} (가능: {list(REGIONS)})")

    rows_out: list[dict] = []
    with requests.Session() as session:
        for region in region_objs:
            start = len(rows_out)
            for year in years:
                for gu_nm, gu_cd in region.gugun.items():
                    page = 1
                    while True:
                        try:
                            payload = _fetch_page(session, kind, key, year, region.sido, gu_cd, page, rows, timeout)
                            items = _iter_items(payload)
                        except RuntimeError as e:  # 잘못된 코드/일시 오류 → 해당 구만 건너뜀
                            print(f"[koroad] {region.name} {year} {gu_nm}: 건너뜀 ({str(e)[:50]})")
                            break
                        for it in items:
                            try:
                                lon = float(it['lo_crd'])
                                lat = float(it['la_crd'])
                            except (KeyError, TypeError, ValueError):
                                continue
                            dth = int(it.get("dth_dnv_cnt", 0) or 0)
                            se = int(it.get("se_dnv_cnt", 0) or 0)
                            sl = int(it.get("sl_dnv_cnt", 0) or 0)
                            rows_out.append({
                                'region': region.name,
                                'datetime': pd.NaT,
                                'lat': lat,
                                'lon': lon,
                                'severity': _severity_from_counts(dth, se, sl),
                                'mode': f"{kind}_frequentzone",
                                'occrrnc_cnt': int(it.get("occrrnc_cnt", 0) or 0),
                                'caslt_cnt': int(it.get("caslt_cnt", 0) or 0),
                                'dth_dnv_cnt': dth,
                                'se_dnv_cnt': se,
                                'sl_dnv_cnt': sl,
                                'wnd_dnv_cnt': int(it.get("wnd_dnv_cnt", 0) or 0),
                                'year': year,
                                'sido_sgg_nm': it.get("sido_sgg_nm"),
                                'spot_nm': it.get("spot_nm"),
                                'geom_json': it.get("geom_json"),
                            })
                        total = int(payload.get("totalCount", 0) or 0)
                        if page * rows >= total or not items:
                            break
                        page += 1
                        time.sleep(pause)
            print(f"[koroad] {region.name}: {len(rows_out) - start}개 지역")

    if not rows_out:
        raise ValueError("KoROAD 응답에서 다발지역을 하나도 받지 못했습니다(지역/연도/인증키 확인).")

    df = pd.DataFrame(rows_out).reset_index(drop=True)
    # 사고 좌표는 데이터가 정한다 — bbox 로 임의로 자르지 않는다(KoROAD 가 준 지점 전부 사용).
    df['accident_id'] = range(1, len(df) + 1)

    return gpd.GeoDataFrame(
        df,
        geometry=[Point(xy) for xy in zip(df['lon'], df['lat'])],
        crs="EPSG:4326",
    )


def _koroad_download_to_raw(
    *,
    root: str | Path | None = None,
    regions: tuple[str, ...] | None = None,
    kind: str = "motorcycle",
    years: Iterable[int] = _KOROAD_DEFAULT_YEARS,
    api_key: str | None = None,
) -> "gpd.GeoDataFrame":
    """다발지역을 받아 `data/raw/koroad_{kind}_frequentzone.csv` 로 캐시하고 반환.

    이후 파이프라인은 이 GeoDataFrame(또는 CSV)을 사고 positive 소스로 사용한다.
    """
    ensure_dirs(root)
    gdf = _koroad_fetch(regions=regions, kind=kind, years=years, api_key=api_key)
    out = raw_dir(root) / f"koroad_{kind}_frequentzone.csv"
    gdf.drop(columns="geometry").to_csv(out, index=False, encoding="utf-8-sig")
    print(f"[koroad] 저장: {out} ({len(gdf)}개 다발지역)")
    return gdf


# --------------------------------------------------------------------------- #
# TAAS(교통사고분석시스템) PM/자전거 사고 지점 로더.
#
# 메모리(pm-pilot-study)·PROJECT.md §4.5 근거:
#     - data.go.kr / TAAS 직접 자동다운로드는 anti-bot 차단 -> **수동 다운로드** 전제.
#     - 사용자가 `data/raw/` 에 내려받은 CSV/XLSX 를 넣으면 이 모듈이 표준 스키마로 로드.
#
# TAAS 다운로드 CSV 는 연도·조회유형별로 컬럼명이 제각각이라, 위경도·일시·심각도
# 컬럼을 휴리스틱으로 탐지해 정규화한다. 좌표가 없고 주소만 있는 경우는 지오코딩이
# 필요하므로 경고 후 제외(별도 지오코딩은 범위 밖).
# --------------------------------------------------------------------------- #

# 컬럼 탐지용 후보(부분일치, 소문자/공백 제거 후 비교)
_TAAS_LAT_KEYS = ["위도", "lat", "ycoord", "y", "경도위도"]
_TAAS_LON_KEYS = ["경도", "lon", "lng", "xcoord", "x"]
_TAAS_TIME_KEYS = ["발생일시", "사고일시", "일시", "datetime", "발생년월일시"]
_TAAS_SEV_KEYS = ["사고내용", "상해정도", "심각도", "severity", "피해정도"]
# PM/자전거 필터에 쓸 컬럼(가해/피해 당사자종별 등)
_TAAS_MODE_KEYS = ["당사자종별", "차종", "가해자법규위반", "사고유형", "당사자"]

_TAAS_PM_PATTERNS = re.compile(r"(개인형이동|PM|전동킥보드|퍼스널모빌리티|원동기|이륜|자전거)", re.IGNORECASE)


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


def _taas_load(*, root: str | Path | None = None, pm_only: bool = True) -> "gpd.GeoDataFrame":
    """`data/raw/` 의 모든 TAAS 파일을 병합·정규화해 GeoDataFrame 반환.

    파일이 하나도 없으면 FileNotFoundError. bbox 밖 지점은 제외.
    """
    import geopandas as gpd
    from shapely.geometry import Point

    raw = raw_dir(root)
    patterns = ["*.csv", "*.xlsx", "*.xls"]
    files: list[Path] = []
    for pat in patterns:
        files += [Path(p) for p in glob.glob(str(raw / pat))]
    files = sorted(f for f in files if not f.name.startswith("~"))
    if not files:
        raise FileNotFoundError(
            f"TAAS 원본이 없습니다: {raw}/*.csv|xlsx 를 수동 다운로드해 넣으세요 "
            "(koroad.or.kr TAAS, 지점 조회/다운로드)."
        )

    frames: list[pd.DataFrame] = []
    for f in files:
        try:
            df = _read_any(f)
        except Exception as e:  # noqa: BLE001 — 파일별 실패는 건너뜀
            print(f"[taas] {f.name} 읽기 실패, 건너뜀: {e}")
            continue
        norm = _taas_normalize_frame(df, source=f.name, pm_only=pm_only)
        if norm is not None and len(norm):
            frames.append(norm)

    if not frames:
        raise ValueError("TAAS 파일에서 위경도/일시 컬럼을 찾지 못했습니다. 컬럼명을 확인하세요.")

    merged = pd.concat(frames, ignore_index=True)
    merged = merged.dropna(subset=["lat", "lon"]).reset_index(drop=True)
    # 사고 좌표는 데이터가 정한다 — bbox 로 자르지 않는다(좌표 있는 사고 전부 사용).
    merged['accident_id'] = np.arange(1, len(merged) + 1)
    gdf = gpd.GeoDataFrame(
        merged,
        geometry=[Point(xy) for xy in zip(merged['lon'], merged['lat'])],
        crs="EPSG:4326",
    )
    return gdf[['accident_id', 'datetime', 'lat', 'lon', 'severity', 'mode', 'geometry']]


def _taas_normalize_frame(df: pd.DataFrame, *, source: str, pm_only: bool) -> pd.DataFrame | None:
    cols = list(df.columns)
    lat_c, lon_c = _find_col(cols, _TAAS_LAT_KEYS), _find_col(cols, _TAAS_LON_KEYS)
    if lat_c is None or lon_c is None:
        print(f"[taas] {source}: 위경도 컬럼 미탐지 -> 건너뜀")
        return None

    out = pd.DataFrame()
    out['lat'] = pd.to_numeric(df[lat_c], errors="coerce")
    out['lon'] = pd.to_numeric(df[lon_c], errors="coerce")

    time_c = _find_col(cols, _TAAS_TIME_KEYS)
    out['datetime'] = pd.to_datetime(df[time_c], errors="coerce") if time_c else pd.NaT

    sev_c = _find_col(cols, _TAAS_SEV_KEYS)
    out['severity'] = df[sev_c].map(_norm_severity) if sev_c else "경상"

    mode_c = _find_col(cols, _TAAS_MODE_KEYS)
    if mode_c is not None:
        out['mode'] = df[mode_c].astype(str)
        if pm_only:
            mask = out['mode'].str.contains(_TAAS_PM_PATTERNS, na=False)
            out = out[mask]
    else:
        out['mode'] = "unknown"
        if pm_only:
            print(f"[taas] {source}: 당사자종별 컬럼 없음 -> PM 필터 미적용(전량 유지)")

    return out.reset_index(drop=True)


# --------------------------------------------------------------------------- #
# 수집 파이프라인·지오 연산용 로더(GeoDataFrame 반환)
# --------------------------------------------------------------------------- #
def _load_accident_gdf(
    source: str = "koroad",
    *,
    root: str | Path | None = None,
    regions: tuple[str, ...] | None = None,
    download: bool = True,
    pm_only: bool = True,
    **kw,
) -> "gpd.GeoDataFrame":
    """사고 지점을 표준 스키마 GeoDataFrame 으로 로드.

    download=True 면 소스에서 받아 `data/raw` 에 캐시, False 면 이미 받아둔 캐시를 읽는다.
    """
    if source == "koroad":
        if download:
            gdf = _koroad_download_to_raw(root=root, regions=regions, **kw)
        else:
            cache = raw_dir(root) / f"koroad_{kw.get('kind', 'motorcycle')}_frequentzone.csv"
            if not cache.exists():
                raise RuntimeError(
                    f"사고 데이터 캐시가 없습니다: {cache}. download=True 로 받으세요."
                )
            import geopandas as gpd

            df = pd.read_csv(cache)
            gdf = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df['lon'], df['lat']), crs=WGS84)
    elif source == "taas":
        gdf = _taas_load(root=root, pm_only=pm_only)
    else:
        raise ValueError(f"알 수 없는 source: {source} (koroad|taas)")
    gdf = _drop_out_of_region(gdf, regions=regions)
    return _validate(gdf)


def _drop_out_of_region(gdf, *, regions: tuple[str, ...] | None = None):
    """선택 지역(regions) 범위 밖 좌표 = 데이터 입력 오류로 보고 제외.

    사고 지점을 임의로 자르는 게 아니라, '대전 데이터인데 좌표가 서울' 같은 명백한
    좌표 오류만 걸러낸다. 여러 지역이면 각 지역 bbox 의 합집합으로 판정.
    """
    region_names = regions or default_regions()
    bboxes = [REGIONS[r].bbox for r in region_names if r in REGIONS]
    inb = None
    for w, s, e, n in bboxes:
        cond = gdf['lat'].between(s, n) & gdf['lon'].between(w, e)
        inb = cond if inb is None else (inb | cond)
    dropped = int((~inb).sum())
    if dropped:
        print(f"[accidents] 선택 지역 범위 밖 좌표(오류 의심) {dropped}건 제외")
    return gdf[inb].reset_index(drop=True)


# --------------------------------------------------------------------------- #
# torchvision 표준 Dataset
# --------------------------------------------------------------------------- #
class AccidentDataset(Dataset):
    """사고 지점 Dataset (torchvision 관례).

    각 항목: (sample, target)
        sample : float tensor [lat, lon]  (transform 으로 커스터마이즈)
        target : severity 클래스 인덱스 (0=경상, 1=중상, 2=사망)

    인자(torchvision 관례):
        root             : 캐시 위치(기본 data_root()). 캐시 파일 raw/koroad_{kind}_frequentzone.csv.
        transform        : sample 변환.
        target_transform : target 변환.
        download         : True 면 source 에서 받아 root 에 캐시(MNIST 관례).
        source           : "koroad" | "taas".
    """

    classes = list(SEVERITY_LEVELS)

    def __init__(
        self,
        root: str | Path | None = None,
        transform: Callable | None = None,
        target_transform: Callable | None = None,
        download: bool = False,
        *,
        source: str = "koroad",
        pm_only: bool = True,
        regions: tuple[str, ...] | None = None,
        **kw,
    ):
        self.root = root
        self.transform = transform
        self.target_transform = target_transform
        self.source = source
        self.gdf = _load_accident_gdf(
            source, root=root, regions=regions, download=download, pm_only=pm_only, **kw
        )

    def __len__(self) -> int:
        return len(self.gdf)

    def __getitem__(self, index: int) -> tuple[Any, Any]:
        row = self.gdf.iloc[index]
        sample: Any = torch.tensor([float(row['lat']), float(row['lon'])], dtype=torch.float32)
        target: Any = self.classes.index(str(row['severity']))
        if self.transform is not None:
            sample = self.transform(sample)
        if self.target_transform is not None:
            target = self.target_transform(target)
        return sample, target

    @property
    def targets(self) -> list[int]:
        return [self.classes.index(s) for s in self.gdf['severity'].astype(str)]

    def to_geodataframe(self) -> "gpd.GeoDataFrame":
        return self.gdf


# --------------------------------------------------------------------------- #
def _validate(gdf) -> "gpd.GeoDataFrame":
    """코어 컬럼 존재·CRS·severity 값·좌표 유효성 검증 후 표준형으로 정규화."""
    import geopandas as gpd

    if not isinstance(gdf, gpd.GeoDataFrame):
        raise SchemaError("GeoDataFrame 이 아닙니다.")
    missing = [c for c in CORE_COLUMNS if c not in gdf.columns]
    if missing:
        raise SchemaError(f"필수 컬럼 누락: {missing} (필요: {CORE_COLUMNS})")

    out = gdf.copy()
    out['accident_id'] = pd.to_numeric(out['accident_id'], errors="coerce").astype("Int64")
    out['datetime'] = pd.to_datetime(out['datetime'], errors="coerce")
    out['lat'] = pd.to_numeric(out['lat'], errors="coerce")
    out['lon'] = pd.to_numeric(out['lon'], errors="coerce")
    out['severity'] = out['severity'].astype(str)
    out['mode'] = out['mode'].astype(str)

    bad_sev = set(out['severity'].unique()) - set(SEVERITY_LEVELS)
    if bad_sev:
        raise SchemaError(f"허용되지 않은 severity 값: {bad_sev} (허용: {SEVERITY_LEVELS})")
    if out[['lat', 'lon']].isna().any().any():
        raise SchemaError("lat/lon 에 결측/비수치 값이 있습니다.")

    if out.crs is None:
        out = out.set_crs(WGS84)
    elif out.crs.to_string() != WGS84:
        out = out.to_crs(WGS84)
    return out
