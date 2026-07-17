"""수집·데이터셋 전역 설정.

값은 대부분 파일럿(`docs/resources/pilot/pmrisk.py`)의 대전 중심부 설정과
일치시키되, 이 패키지는 파일럿에 의존하지 않는 독립 모듈로 유지한다.
환경변수로 민감정보(스트리트뷰 API 키)를 주입한다.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

# 대전 중심부 bbox (W, S, E, N) — 파일럿과 동일(충남대/KAIST/한밭대/배재대/우송대/둔산)
DAEJEON_BBOX: tuple[float, float, float, float] = (127.30, 36.31, 127.43, 36.39)

# 미터 단위 연산용 투영 (UTM 52N)
METRIC_CRS = "EPSG:32652"
WGS84 = "EPSG:4326"

# 프로젝트 루트 = .../src/main/python/pm_proj/utils/config.py 기준 5단계 상위
_PROJECT_ROOT = Path(__file__).resolve().parents[5]


def _default_data_dir() -> Path:
    """데이터 다운로드 루트. 환경변수 PM_DATA_DIR 우선, 없으면 프로젝트 루트의 data/.

    CWD 와 무관하게 항상 프로젝트 루트의 data/ 로 저장된다(gitignore 대상).
    """
    env = os.environ.get("PM_DATA_DIR")
    return Path(env) if env else _PROJECT_ROOT / "data"

# TAAS 심각도 라벨 정규화 매핑
SEVERITY_ORDER = ["경상", "중상", "사망"]


@dataclass(frozen=True)
class StreetViewConfig:
    """스트리트뷰 이미지 요청 파라미터.

    provider: "google" | "naver" | "kakao" | "mock"
      - google: Street View Static API (문서화된 REST, 헤딩/피치/fov 지원)
      - naver : 로드뷰. 공개 정적 이미지 REST가 없어 ToS 확인 필요(§4.5-5).
      - mock  : 네트워크 없이 파이프라인 검증용 플레이스홀더 이미지.
    """

    provider: str = os.environ.get("PM_SV_PROVIDER", "mock")
    api_key: str | None = os.environ.get("PM_SV_API_KEY")
    # 이미지 크기 (ViT 백본 입력 고려; 224 배수 여유)
    width: int = 512
    height: int = 512
    fov: int = 90
    pitch: int = 0
    # 한 지점에서 여러 방위각으로 촬영(도로 구조를 넓게 포착). None이면 도로 진행방향만.
    headings: tuple[int, ...] | None = None
    # 초당 요청 상한(레이트리밋 + 캐시로 ToS/과금 보호)
    requests_per_sec: float = 2.0


@dataclass(frozen=True)
class Config:
    """패키지 전역 설정."""

    bbox: tuple[float, float, float, float] = DAEJEON_BBOX
    metric_crs: str = METRIC_CRS

    # 데이터 루트. 기본은 저장소 상대 경로.
    data_dir: Path = field(default_factory=lambda: _default_data_dir())

    # 도로 위 지점 샘플링 간격(m) — §4.5 부가설계: 30~50m 고정간격 권장
    sample_interval_m: float = 40.0
    # negative:positive 비율
    negative_ratio: float = 3.0
    # exposure 매칭 허용 오차(분위수 bin 개수)
    exposure_bins: int = 5

    streetview: StreetViewConfig = field(default_factory=StreetViewConfig)

    # 재현성
    seed: int = 42

    # ---- 파생 경로 --------------------------------------------------------
    @property
    def raw_dir(self) -> Path:
        return self.data_dir / "raw"

    @property
    def images_dir(self) -> Path:
        """torchvision ImageFolder 호환 루트: images/<class>/<id>.jpg"""
        return self.data_dir / "streetview"

    @property
    def manifest_path(self) -> Path:
        return self.data_dir / "manifest.csv"

    @property
    def points_path(self) -> Path:
        """수집 대상 지점(사고+대조) GeoPackage."""
        return self.data_dir / "sample_points.gpkg"

    def ensure_dirs(self) -> None:
        for p in (self.data_dir, self.raw_dir, self.images_dir):
            p.mkdir(parents=True, exist_ok=True)


DEFAULT_CONFIG = Config()
