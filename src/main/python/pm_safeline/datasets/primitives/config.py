"""수집·데이터셋 기본값과 지역 레지스트리·경로 헬퍼.

독립 모듈(다른 패키지에 의존하지 않음)로 유지한다. 환경변수로 민감정보
(스트리트뷰 API 키 등)를 주입한다.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

# 대전시 전역 범위 (W, S, E, N) — 사고 좌표 '유효성 필터'용(대전 밖 좌표=데이터 오류 제외).
# 사고 지점을 임의로 자르는 게 아니라, 실제 작업 영역은 사고 좌표 분포에서 도출된다.
DAEJEON_BBOX: tuple[float, float, float, float] = (127.24, 36.17, 127.57, 36.51)

# 미터 단위 연산용 투영 (UTM 52N)
METRIC_CRS = "EPSG:32652"
WGS84 = "EPSG:4326"

# 프로젝트 루트 = .../src/main/python/pm_safeline/datasets/primitives/config.py 기준 5단계 상위
_PROJECT_ROOT = Path(__file__).resolve().parents[6]


def _load_dotenv() -> None:
    """프로젝트 루트의 .env 를 os.environ 에 주입(의존성 없는 경량 로더).

    - 이미 설정된 환경변수는 덮어쓰지 않는다(실제 셸 값 우선).
    - `KEY=VALUE` 형식, `#` 주석과 빈 줄 무시, 양끝 따옴표 제거.
    없으면 조용히 무시. 민감정보(.env)는 gitignore 대상.
    """
    path = _PROJECT_ROOT / ".env"
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


# 아래 헬퍼가 os.environ 을 읽기 전에 .env 를 먼저 로드.
_load_dotenv()

# TAAS 심각도 라벨 정규화 매핑
SEVERITY_ORDER = ["경상", "중상", "사망"]


@dataclass(frozen=True)
class Region:
    """수집 대상 행정구역 — KoROAD siDo/guGun 코드 + 좌표 유효성 bbox.

    전국 전이(§4.4/§6)가 목표라, teacher 학습 데이터는 여러 지역의 도로 구조를
    다양하게 담는 게 좋다. 새 지역은 REGIONS 에 코드를 추가하면 된다(guGun 필수).
    """

    name: str
    sido: str
    gugun: dict[str, str]                    # {구이름: KoROAD guGun 코드}
    bbox: tuple[float, float, float, float]  # (W, S, E, N) 좌표 유효성 필터


# KoROAD 실 API 로 코드 검증 완료(siDo+guGun = 법정동 시군구 5자리 분할, siDo 만으론 조회 불가).
# 광역시는 확장 준비용으로 등록(코드 API 검증됨). 실제 수집은 PM_REGIONS 로 선택.
REGIONS: dict[str, Region] = {
    'daejeon': Region("daejeon", "30",
                      {'동구': "110", '중구': "140", '서구': "170", '유성구': "200", '대덕구': "230"},
                      (127.24, 36.17, 127.57, 36.51)),
    'sejong': Region("sejong", "36", {'세종': "110"},
                     (127.15, 36.40, 127.42, 36.75)),
    'cheongju': Region("cheongju", "43",
                       {'상당구': "111", '서원구': "112", '흥덕구': "113", '청원구': "114"},
                       (127.30, 36.45, 127.75, 36.90)),
    # ---- 확장 준비: 광역시(코드 KoROAD API 검증 완료, 2017~2024 이륜차 다발지역 존재 확인) ----
    'seoul': Region("seoul", "11",
                    {'종로구': "110", '중구': "140", '용산구': "170", '성동구': "200", '광진구': "215",
                     '동대문구': "230", '중랑구': "260", '성북구': "290", '강북구': "305", '도봉구': "320",
                     '노원구': "350", '은평구': "380", '서대문구': "410", '마포구': "440", '양천구': "470",
                     '강서구': "500", '구로구': "530", '금천구': "545", '영등포구': "560", '동작구': "590",
                     '관악구': "620", '서초구': "650", '강남구': "680", '송파구': "710", '강동구': "740"},
                    (126.76, 37.42, 127.19, 37.70)),
    'busan': Region("busan", "26",
                    {'중구': "110", '서구': "140", '동구': "170", '영도구': "200", '부산진구': "230",
                     '동래구': "260", '남구': "290", '북구': "320", '해운대구': "350", '사하구': "380",
                     '금정구': "410", '강서구': "440", '연제구': "470", '수영구': "500", '사상구': "530",
                     '기장군': "710"},
                    (128.78, 35.03, 129.31, 35.40)),
    'daegu': Region("daegu", "27",
                    {'중구': "110", '동구': "140", '서구': "170", '남구': "200", '북구': "230",
                     '수성구': "260", '달서구': "290", '달성군': "710"},
                    (128.34, 35.60, 128.77, 36.02)),
    'incheon': Region("incheon", "28",
                      {'중구': "110", '동구': "140", '미추홀구': "177", '연수구': "185", '남동구': "200",
                       '부평구': "237", '계양구': "245", '서구': "260", '강화군': "710", '옹진군': "720"},
                      (126.37, 37.34, 126.80, 37.64)),
    'gwangju': Region("gwangju", "29",
                      {'동구': "110", '서구': "140", '남구': "155", '북구': "170", '광산구': "200"},
                      (126.78, 35.09, 126.97, 35.27)),
    'ulsan': Region("ulsan", "31",
                    {'중구': "110", '남구': "140", '동구': "170", '북구': "200", '울주군': "710"},
                    (129.14, 35.43, 129.48, 35.73)),
}

# ---- 수집 기본값 ------------------------------------------------------------

# 도로 위 지점 샘플링 간격(m) — §4.5 부가설계: 30~50m 고정간격 권장
SAMPLE_INTERVAL_M = 40.0
# negative:positive 비율
NEGATIVE_RATIO = 3.0
# exposure 매칭 허용 오차(분위수 bin 개수)
EXPOSURE_BINS = 5
# 재현성
SEED = 42

# ---- 스트리트뷰 기본값 -------------------------------------------------------
# 이미지 크기 (ViT 백본 입력 고려; 224 배수 여유)
SV_WIDTH = 512
SV_HEIGHT = 512
SV_FOV = 90
SV_PITCH = 0
# 한 지점에서 여러 방위각으로 촬영(도로 구조를 넓게 포착). None이면 도로 진행방향만.
SV_HEADINGS: tuple[int, ...] | None = None
# 초당 요청 상한(레이트리밋 + 캐시로 ToS/과금 보호)
SV_REQUESTS_PER_SEC = 2.0


def default_regions() -> tuple[str, ...]:
    """수집 대상 지역(REGIONS 키). 환경변수 PM_REGIONS="daejeon,sejong" 로 지정 가능."""
    return tuple(r.strip() for r in os.environ.get("PM_REGIONS", "daejeon").split(",") if r.strip())


def default_provider() -> str:
    """스트리트뷰 provider 이름. 환경변수 PM_SV_PROVIDER 우선, 기본 "mock"."""
    return os.environ.get("PM_SV_PROVIDER", "mock")


def default_sv_api_key() -> str | None:
    """스트리트뷰 API 키. 환경변수 PM_SV_API_KEY."""
    return os.environ.get("PM_SV_API_KEY")


def data_root(root: str | Path | None = None) -> Path:
    """데이터 다운로드 루트. root 명시 시 그 경로, 아니면 env PM_DATA_DIR, 없으면 프로젝트 루트의 data/."""
    if root is not None:
        return Path(root)
    env = os.environ.get("PM_DATA_DIR")
    return Path(env) if env else _PROJECT_ROOT / "data"


def raw_dir(root: str | Path | None = None) -> Path:
    return data_root(root) / "raw"


def images_dir(root: str | Path | None = None) -> Path:
    """torchvision ImageFolder 호환 루트: images/<class>/<id>.jpg"""
    return data_root(root) / "streetview"


def manifest_path(root: str | Path | None = None) -> Path:
    return data_root(root) / "manifest.csv"


def points_path(root: str | Path | None = None) -> Path:
    """수집 대상 지점(사고+대조) GeoPackage."""
    return data_root(root) / "sample_points.gpkg"


def ensure_dirs(root: str | Path | None = None) -> None:
    for p in (data_root(root), raw_dir(root), images_dir(root)):
        p.mkdir(parents=True, exist_ok=True)
