"""스트리트뷰/로드뷰 이미지 제공자(provider) 추상화.

PROJECT.md §4.5-(5): 네이버 로드뷰 대량수집의 이용약관 허용범위 **미확인**.
따라서 특정 사설 파노라마 엔드포인트를 하드코딩하지 않고, 교체 가능한
provider 인터페이스로 둔다. 각 provider 구현 시 해당 서비스 약관/과금을 반드시 확인.

기본 제공:
    - MockProvider   : 네트워크 없이 파이프라인 검증용(지점별 결정적 색상 이미지).
    - GoogleProvider : Street View Static API(문서화된 공식 REST, 키·과금 필요).
    - NaverProvider  : 스텁 — 공식 정적 파노라마 REST 부재. 승인된 방식 확정 후 구현.

공통 계약:
    fetch(lat, lon, heading, cfg) -> bytes(JPEG/PNG)  또는  None(해당 지점 커버리지 없음)
"""

from __future__ import annotations

import hashlib
import io
import time
from abc import ABC, abstractmethod

from .config import Config, StreetViewConfig, DEFAULT_CONFIG


class StreetViewProvider(ABC):
    """지점 좌표 -> 이미지 바이트."""

    name: str = "base"

    def __init__(self, sv: StreetViewConfig):
        self.sv = sv
        self._last_call = 0.0

    def _throttle(self) -> None:
        if self.sv.requests_per_sec <= 0:
            return
        min_gap = 1.0 / self.sv.requests_per_sec
        now = time.monotonic()
        wait = min_gap - (now - self._last_call)
        if wait > 0:
            time.sleep(wait)
        self._last_call = time.monotonic()

    @abstractmethod
    def fetch(self, lat: float, lon: float, heading: float) -> bytes | None:
        ...

    def available(self) -> bool:
        """설정상 사용 가능한지(키 존재 등)."""
        return True


class MockProvider(StreetViewProvider):
    """네트워크·키 없이 파이프라인을 end-to-end 검증하기 위한 더미 이미지 생성기.

    좌표+헤딩 해시로 결정적 단색 이미지를 만들어, 동일 지점은 항상 같은 이미지가
    나오도록 한다(캐시/재현성 테스트에 유용). Pillow 필요.
    """

    name = "mock"

    def fetch(self, lat: float, lon: float, heading: float) -> bytes | None:
        from PIL import Image

        key = f"{lat:.6f},{lon:.6f},{heading:.1f}".encode()
        h = hashlib.sha256(key).digest()
        color = (h[0], h[1], h[2])
        img = Image.new("RGB", (self.sv.width, self.sv.height), color)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=85)
        return buf.getvalue()


class GoogleProvider(StreetViewProvider):
    """Google Street View Static API.

    https://developers.google.com/maps/documentation/streetview
    metadata 엔드포인트로 커버리지를 먼저 확인해 과금·빈이미지를 줄인다.
    키는 cfg.streetview.api_key (env PM_SV_API_KEY).
    """

    name = "google"
    _IMG_URL = "https://maps.googleapis.com/maps/api/streetview"
    _META_URL = "https://maps.googleapis.com/maps/api/streetview/metadata"

    def available(self) -> bool:
        return bool(self.sv.api_key)

    def fetch(self, lat: float, lon: float, heading: float) -> bytes | None:
        import requests

        params = {
            "location": f"{lat},{lon}",
            "heading": round(heading, 1),
            "fov": self.sv.fov,
            "pitch": self.sv.pitch,
            "key": self.sv.api_key,
        }
        # 1) 커버리지 확인(무료)
        self._throttle()
        meta = requests.get(self._META_URL, params=params, timeout=10).json()
        if meta.get("status") != "OK":
            return None
        # 2) 이미지
        self._throttle()
        size = f"{self.sv.width}x{self.sv.height}"
        r = requests.get(self._IMG_URL, params={**params, "size": size}, timeout=15)
        if r.status_code != 200 or not r.content:
            return None
        return r.content


class NaverProvider(StreetViewProvider):
    """네이버 로드뷰 — 스텁.

    네이버 지도 파노라마는 공식 '정적 이미지 REST'가 없고 JS SDK 중심이라,
    약관상 허용되는 수집 방식(승인 API/제휴)이 확정되기 전에는 구현하지 않는다.
    §4.5-(5) 약관 확인 완료 후 이 클래스의 fetch 를 채운다.
    """

    name = "naver"

    def available(self) -> bool:
        return False

    def fetch(self, lat: float, lon: float, heading: float) -> bytes | None:
        raise NotImplementedError(
            "NaverProvider 미구현: 로드뷰 대량수집 약관(§4.5-5) 확인 후 승인된 방식으로 구현하세요."
        )


_REGISTRY: dict[str, type[StreetViewProvider]] = {
    "mock": MockProvider,
    "google": GoogleProvider,
    "naver": NaverProvider,
}


def get_provider(cfg: Config = DEFAULT_CONFIG) -> StreetViewProvider:
    """cfg.streetview.provider 이름으로 provider 인스턴스 생성."""
    name = cfg.streetview.provider
    if name not in _REGISTRY:
        raise ValueError(f"알 수 없는 provider: {name}. 가능: {list(_REGISTRY)}")
    provider = _REGISTRY[name](cfg.streetview)
    if not provider.available():
        raise RuntimeError(
            f"provider '{name}' 사용 불가(키 누락 또는 미지원). "
            "PM_SV_PROVIDER / PM_SV_API_KEY 환경변수를 확인하세요."
        )
    return provider
