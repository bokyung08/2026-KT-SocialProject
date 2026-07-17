# -*- coding: utf-8 -*-
"""PM 위험구역 파일럿 — 생성 노트북과 파일럿 노트북이 공유하는 상수·로더.

핵심: 날씨는 data/asos/ 의 실제 기상청 ASOS(대전 133) 시간자료를 사용한다.
사고는 합성이지만 (1) 실제 OSM 도로구조와 (2) 실제 날씨 타임라인에 결합되도록 생성한다.
"""
from __future__ import annotations
import glob
import os
import numpy as np
import pandas as pd

# ----------------------------------------------------------------- 경로/상수
DATA_DIR = "data"
ASOS_DIR = os.path.join(DATA_DIR, "asos")
CACHE_DIR = os.path.join(DATA_DIR, "cache")

GRID_GPKG = os.path.join(DATA_DIR, "grid_features.gpkg")
ACCIDENTS_CSV = os.path.join(DATA_DIR, "accidents_synth.csv")

# 대전 중심부 bbox (W,S,E,N) — 충남대/KAIST/한밭대/배재대/우송대/둔산 포함
BBOX = (127.30, 36.31, 127.43, 36.39)
PROJ = "EPSG:32652"      # UTM 52N (meter)
CELL_M = 500.0
GRID_CRS_WGS = "EPSG:4326"

# 모델링 대상 기간 (실제 ASOS 보유 연도와 일치)
YEARS = list(range(2019, 2024))   # 2019~2023 (5년)

UNIV = {
    "KAIST": (36.3741, 127.3604), "충남대": (36.3664, 127.3447),
    "한밭대": (36.3509, 127.3015), "배재대": (36.3215, 127.3565),
    "우송대": (36.3360, 127.4283),
}

SEVERITY = ["경상", "중상", "사망"]
SEVERITY_P = [0.80, 0.18, 0.02]

# ----------------------------------------------------------------- 생성 승수(보정값)
# 시간대 7구간 (PM 사고: 저녁 피크) — 문헌·공단 시범사업 패턴 보정
DAYPARTS = [("심야", 0, 6), ("아침", 6, 9), ("오전", 9, 12), ("오후", 12, 15),
            ("초저녁", 15, 18), ("저녁", 18, 21), ("밤", 21, 24)]
DP_MULT = {"심야": 0.30, "아침": 0.75, "오전": 0.60, "오후": 0.85,
           "초저녁": 1.05, "저녁": 1.65, "밤": 0.90}
WEEKEND_MULT = 1.20          # 주말 PM 레저 이용 증가
RAIN_MULT = 1.45             # 강수 시 위험 상승 (실제 날씨 is_rain에 결합)
YEAR_GROWTH = {2019: 1.0, 2020: 1.2, 2021: 1.5, 2022: 1.9, 2023: 2.3}  # 연 2.5배 증가 보정

ARTERIAL = {"primary", "secondary", "trunk", "primary_link",
            "secondary_link", "trunk_link", "tertiary"}
STRUCT_FEATURES = ["road_len", "arterial_len", "n_edges",
                   "n_intersections", "intersection_density", "n_poi", "dist_univ"]


def daypart_of(hour: int) -> str:
    for name, h0, h1 in DAYPARTS:
        if h0 <= hour < h1:
            return name
    return "밤"


DP_CODE = {d[0]: k for k, d in enumerate(DAYPARTS)}


def load_weather(years=YEARS) -> pd.DataFrame:
    """data/asos/ 의 실제 ASOS 시간자료(대전 133)를 합쳐 표준 스키마로 반환.

    반환 컬럼: datetime, temp(℃), precip(mm), wind, humidity, vis, is_rain
    강수량 결측(NaN) = 무강수 → 0.0 으로 채움.
    """
    files = sorted(glob.glob(os.path.join(ASOS_DIR, "SURFACE_ASOS_133_HR_*.csv")))
    if not files:
        raise FileNotFoundError(f"ASOS 파일이 없습니다: {ASOS_DIR}/SURFACE_ASOS_133_HR_*.csv")
    frames = [pd.read_csv(f, encoding="cp949") for f in files]
    w = pd.concat(frames, ignore_index=True)

    ren = {}
    for c in w.columns:
        if c.startswith("일시"):      ren[c] = "datetime"
        elif c.startswith("기온"):    ren[c] = "temp"
        elif c.startswith("강수량"):  ren[c] = "precip"
        elif c.startswith("풍속"):    ren[c] = "wind"
        elif c.startswith("습도"):    ren[c] = "humidity"
        elif c.startswith("시정"):    ren[c] = "vis"
    w = w.rename(columns=ren)
    keep = [c for c in ["datetime", "temp", "precip", "wind", "humidity", "vis"] if c in w.columns]
    w = w[keep].copy()
    w["datetime"] = pd.to_datetime(w["datetime"])
    w["precip"] = pd.to_numeric(w["precip"], errors="coerce").fillna(0.0)
    for c in ["temp", "wind", "humidity", "vis"]:
        if c in w.columns:
            w[c] = pd.to_numeric(w[c], errors="coerce")
    w["is_rain"] = (w["precip"] > 0).astype(int)
    w = w[w["datetime"].dt.year.isin(list(years))]
    w = w.drop_duplicates("datetime").sort_values("datetime").reset_index(drop=True)
    return w


def zscore(s) -> np.ndarray:
    s = np.asarray(s, dtype=float)
    return (s - s.mean()) / (s.std() + 1e-9)
