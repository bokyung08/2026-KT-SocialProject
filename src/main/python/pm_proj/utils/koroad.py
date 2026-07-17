"""KoROAD(도로교통공단) 교통사고 다발지역 오픈API 자동 다운로더.

PROJECT.md §4.4 step 1 의 사고 지점 확보를, 수동 CSV 대신 공식 오픈API 로 자동화한다.
PM/자전거 전용 다발지역 API 는 없으므로, 가장 근접한 **이륜차(motorcycle) 교통사고
다발지역**을 기본 소스로 사용한다(자전거 자전거(bicycle) 엔드포인트도 지원).

엔드포인트:
    https://opendata.koroad.or.kr/data/rest/frequentzone/{kind}
    kind ∈ {motorcycle, bicycle, ...}

요청 변수(표준):
    authKey       인증키 (env KOROAD_API_KEY)
    searchYearCd  연도 (예: 2024)
    siDo          시도 코드 (대전 = 30)
    guGun         시군구 코드 (대전: 동구110/중구140/서구170/유성구200/대덕구230)
    type          json | xml
    numOfRows     페이지당 개수
    pageNo        페이지 번호

응답(예시):
    {resultCode:"00", items:{item:[{afos_id, sido_sgg_nm, spot_nm, occrrnc_cnt,
     caslt_cnt, dth_dnv_cnt, se_dnv_cnt, sl_dnv_cnt, wnd_dnv_cnt, geom_json,
     lo_crd, la_crd}, ...]}, totalCount, numOfRows, pageNo}

각 item 은 '개별 사고'가 아니라 '다발지역(폴리곤)'이며, 중심좌표(lo_crd,la_crd)와
사고건수(occrrnc_cnt)를 갖는다. 이를 위험 positive 지점으로 사용한다.
"""

from __future__ import annotations

import json
import os
import time
from typing import TYPE_CHECKING, Iterable

import pandas as pd

from .config import Config, DEFAULT_CONFIG

if TYPE_CHECKING:
    import geopandas as gpd

BASE_URL = "https://opendata.koroad.or.kr/data/rest/frequentzone"

# 대전광역시 시도/시군구 코드 (KoROAD 오픈API 기준)
DAEJEON_SIDO = "30"
DAEJEON_GUGUN = {
    "동구": "110",
    "중구": "140",
    "서구": "170",
    "유성구": "200",
    "대덕구": "230",
}

DEFAULT_YEARS = tuple(range(2017, 2025))  # 2017~2024


def _api_key(explicit: str | None) -> str:
    key = explicit or os.environ.get("KOROAD_API_KEY")
    if not key:
        raise RuntimeError(
            "KoROAD 인증키가 필요합니다. https://opendata.koroad.or.kr 에서 발급 후 "
            "환경변수 KOROAD_API_KEY 로 지정하세요 (또는 api_key 인자)."
        )
    return key


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
        "authKey": key,
        "searchYearCd": str(year),
        "siDo": sido,
        "type": "json",
        "numOfRows": str(rows),
        "pageNo": str(page),
    }
    if gugun:
        params["guGun"] = gugun
    r = session.get(f"{BASE_URL}/{kind}", params=params, timeout=timeout)
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


def fetch_frequent_zones(
    cfg: Config = DEFAULT_CONFIG,
    *,
    kind: str = "motorcycle",
    years: Iterable[int] = DEFAULT_YEARS,
    api_key: str | None = None,
    gugun: dict[str, str] | None = None,
    rows: int = 100,
    pause: float = 0.2,
    timeout: float = 15.0,
) -> "gpd.GeoDataFrame":
    """대전 지역 {kind} 교통사고 다발지역을 연도×구 순회로 모두 받아 GeoDataFrame 반환.

    반환 스키마(WGS84): accident_id, datetime(NaT), lat, lon, severity, mode,
        occrrnc_cnt, caslt_cnt, dth_dnv_cnt, se_dnv_cnt, sl_dnv_cnt, wnd_dnv_cnt,
        year, sido_sgg_nm, spot_nm, geom_json, geometry(Point)
    """
    import geopandas as gpd
    import requests
    from shapely.geometry import Point

    key = _api_key(api_key)
    gu = gugun or DAEJEON_GUGUN
    rows_out: list[dict] = []

    with requests.Session() as session:
        for year in years:
            for gu_nm, gu_cd in gu.items():
                page = 1
                while True:
                    payload = _fetch_page(session, kind, key, year, DAEJEON_SIDO, gu_cd, page, rows, timeout)
                    items = _iter_items(payload)
                    for it in items:
                        try:
                            lon = float(it["lo_crd"])
                            lat = float(it["la_crd"])
                        except (KeyError, TypeError, ValueError):
                            continue
                        dth = int(it.get("dth_dnv_cnt", 0) or 0)
                        se = int(it.get("se_dnv_cnt", 0) or 0)
                        sl = int(it.get("sl_dnv_cnt", 0) or 0)
                        rows_out.append({
                            "datetime": pd.NaT,
                            "lat": lat,
                            "lon": lon,
                            "severity": _severity_from_counts(dth, se, sl),
                            "mode": f"{kind}_frequentzone",
                            "occrrnc_cnt": int(it.get("occrrnc_cnt", 0) or 0),
                            "caslt_cnt": int(it.get("caslt_cnt", 0) or 0),
                            "dth_dnv_cnt": dth,
                            "se_dnv_cnt": se,
                            "sl_dnv_cnt": sl,
                            "wnd_dnv_cnt": int(it.get("wnd_dnv_cnt", 0) or 0),
                            "year": year,
                            "sido_sgg_nm": it.get("sido_sgg_nm"),
                            "spot_nm": it.get("spot_nm"),
                            "geom_json": it.get("geom_json"),
                        })
                    total = int(payload.get("totalCount", 0) or 0)
                    got = page * rows
                    if got >= total or not items:
                        break
                    page += 1
                    time.sleep(pause)
                print(f"[koroad] {kind} {year} {gu_nm}: 누적 {len(rows_out)}개 지역")

    if not rows_out:
        raise ValueError("KoROAD 응답에서 다발지역을 하나도 받지 못했습니다(연도/코드/인증키 확인).")

    df = pd.DataFrame(rows_out)
    # bbox 클리핑(대전 중심부)
    w, s, e, n = cfg.bbox
    in_box = df["lat"].between(s, n) & df["lon"].between(w, e)
    dropped = int((~in_box).sum())
    if dropped:
        print(f"[koroad] bbox 밖 {dropped}개 제외")
    df = df[in_box].reset_index(drop=True)
    df["accident_id"] = range(1, len(df) + 1)

    return gpd.GeoDataFrame(
        df,
        geometry=[Point(xy) for xy in zip(df["lon"], df["lat"])],
        crs="EPSG:4326",
    )


def download_to_raw(
    cfg: Config = DEFAULT_CONFIG,
    *,
    kind: str = "motorcycle",
    years: Iterable[int] = DEFAULT_YEARS,
    api_key: str | None = None,
) -> "gpd.GeoDataFrame":
    """다발지역을 받아 `data/raw/koroad_{kind}_frequentzone.csv` 로 캐시하고 반환.

    이후 파이프라인은 이 GeoDataFrame(또는 CSV)을 사고 positive 소스로 사용한다.
    """
    cfg.ensure_dirs()
    gdf = fetch_frequent_zones(cfg, kind=kind, years=years, api_key=api_key)
    out = cfg.raw_dir / f"koroad_{kind}_frequentzone.csv"
    gdf.drop(columns="geometry").to_csv(out, index=False, encoding="utf-8-sig")
    print(f"[koroad] 저장: {out} ({len(gdf)}개 다발지역)")
    return gdf
