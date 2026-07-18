"""스트리트뷰/로드뷰 이미지 제공자(provider) 추상화.

PROJECT.md §4.5-(5): 네이버 로드뷰 대량수집의 이용약관 허용범위 **미확인**.
따라서 특정 사설 파노라마 엔드포인트를 하드코딩하지 않고, 교체 가능한
provider 인터페이스로 둔다. 각 provider 구현 시 해당 서비스 약관/과금을 반드시 확인.

기본 제공:
    - MockProvider   : 네트워크 없이 파이프라인 검증용(지점별 결정적 색상 이미지).
    - GoogleProvider : Street View Static API(문서화된 공식 REST, 키·과금 필요).
    - NaverProvider  : 네이버 지도 로드뷰 공개 파노라마 엔드포인트(키 불필요, 내부 REST).

공통 계약:
    fetch(lat, lon, heading) -> bytes(JPEG/PNG)  또는  None(해당 지점 커버리지 없음)
"""

from __future__ import annotations

import hashlib
import io
import time
from abc import ABC, abstractmethod

from .config import (
    SV_FOV,
    SV_HEADINGS,
    SV_HEIGHT,
    SV_PITCH,
    SV_REQUESTS_PER_SEC,
    SV_WIDTH,
    default_provider,
    default_sv_api_key,
)


class StreetViewProvider(ABC):
    """지점 좌표 -> 이미지 바이트."""

    name: str = "base"

    def __init__(
        self,
        *,
        api_key: str | None = None,
        width: int = SV_WIDTH,
        height: int = SV_HEIGHT,
        fov: int = SV_FOV,
        pitch: int = SV_PITCH,
        headings: tuple[int, ...] | None = SV_HEADINGS,
        requests_per_sec: float = SV_REQUESTS_PER_SEC,
    ):
        self.api_key = api_key
        self.width = width
        self.height = height
        self.fov = fov
        self.pitch = pitch
        self.headings = headings
        self.requests_per_sec = requests_per_sec
        self._last_call = 0.0

    def _throttle(self) -> None:
        if self.requests_per_sec <= 0:
            return
        min_gap = 1.0 / self.requests_per_sec
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
        img = Image.new("RGB", (self.width, self.height), color)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=85)
        return buf.getvalue()


class GoogleProvider(StreetViewProvider):
    """Google Street View Static API.

    https://developers.google.com/maps/documentation/streetview
    metadata 엔드포인트로 커버리지를 먼저 확인해 과금·빈이미지를 줄인다.
    키는 api_key (env PM_SV_API_KEY).
    """

    name = "google"
    _IMG_URL = "https://maps.googleapis.com/maps/api/streetview"
    _META_URL = "https://maps.googleapis.com/maps/api/streetview/metadata"

    def available(self) -> bool:
        return bool(self.api_key)

    def fetch(self, lat: float, lon: float, heading: float) -> bytes | None:
        import requests

        params = {
            'location': f"{lat},{lon}",
            'heading': round(heading, 1),
            'fov': self.fov,
            'pitch': self.pitch,
            'key': self.api_key,
        }
        # 1) 커버리지 확인(무료)
        self._throttle()
        meta = requests.get(self._META_URL, params=params, timeout=10).json()
        if meta.get("status") != "OK":
            return None
        # 2) 이미지
        self._throttle()
        size = f"{self.width}x{self.height}"
        r = requests.get(self._IMG_URL, params={**params, 'size': size}, timeout=15)
        if r.status_code != 200 or not r.content:
            return None
        return r.content


class NaverProvider(StreetViewProvider):
    """네이버 지도 로드뷰(파노라마) still-image provider.

    네이버 지도 웹 클라이언트가 사용하는 공개 파노라마 엔드포인트를 이용한다
    (API 키 불필요, ``Referer: https://map.naver.com`` 헤더 필요).

    파이프라인:
      1) 좌표 -> 최근접 파노라마 조회
         GET https://map.naver.com/p/api/panorama/nearby/{lon}/{lat}
         -> GeoJSON. features[0].properties.id(파노ID), heading(차량 진행방위) 반환.
            features 가 비면 해당 지점 커버리지 없음 -> None.
      2) 파노라마 등거원통(equirectangular) 타일 조합
         GET https://panorama.pstatic.net/imageV3/{panoid}/{zoom}/{x}/{y}
         zoom 0 => 4x2 격자(512px 타일) = 2048x1024 전방위 이미지.
      3) 요청 heading 을 중심으로 fov 폭 창을 크롭 후 지정 크기로 리사이즈.

    heading 매핑: equirect 가로 중앙(W/2)이 파노라마 진행방위(metadata heading)에
    대응한다고 가정한다(네이버 웹뷰어 관측치). 절대 방위가 필요 없다면 이 근사로 충분.

    엔드포인트 출처(reverse-engineered, 커뮤니티 검증):
      - streetlevel(sk-zk) naver 모듈: nearby / imageV3 타일 URL.
    ToS: 공식 문서화된 REST 가 아니라 웹 클라이언트 내부 엔드포인트다. 대량수집 시
    §4.5-(5) 약관 확인 필요. requests_per_sec 레이트리밋으로 부하를 제한한다.
    """

    name = "naver"
    _NEARBY_URL = "https://map.naver.com/p/api/panorama/nearby/{lon}/{lat}"
    _TILE_URL = "https://panorama.pstatic.net/imageV3/{panoid}/{zoom}/{x}/{y}"
    # 큐브맵 6면 스트립(f,r,b,l,u,d 가로 배열, 각 256px). imageV3 미제공 파노 폴백용.
    _STRIP_URL = "https://panorama.pstatic.net/image/{panoid}/512/P"
    _FACE_PX = 256
    _HEADERS = {
        'Referer': "https://map.naver.com",
        'User-Agent': "Mozilla/5.0 (compatible; pm-proj/1.0)",
    }
    _TILE = 512  # 타일 한 변(px)

    def available(self) -> bool:
        # 공개 엔드포인트(키 불필요). 네트워크만 있으면 사용 가능.
        return True

    def _nearest(self, requests, lat: float, lon: float):
        """(panoid, pano_heading) 또는 None."""
        url = self._NEARBY_URL.format(lon=lon, lat=lat)
        self._throttle()
        r = requests.get(url, headers=self._HEADERS, timeout=10)
        if r.status_code != 200:
            return None
        feats = (r.json() or {}).get("features") or []
        if not feats:
            return None
        props = feats[0].get("properties") or {}
        pid = props.get("id")
        if not pid:
            return None
        try:
            pano_heading = float(props.get("heading", 0.0))
        except (TypeError, ValueError):
            pano_heading = 0.0
        return pid, pano_heading

    def _equirect(self, requests, panoid: str, zoom: int = 0):
        """등거원통 전방위 이미지를 조합해 PIL.Image 로 반환. 실패 시 None."""
        from PIL import Image

        cols, rows = 4 * (2 ** zoom), 2 * (2 ** zoom)
        canvas = Image.new("RGB", (cols * self._TILE, rows * self._TILE))
        for cx in range(cols):
            for cy in range(rows):
                url = self._TILE_URL.format(
                    panoid=panoid, zoom=zoom, x=cx + 1, y=cy + 1
                )
                self._throttle()
                r = requests.get(url, headers=self._HEADERS, timeout=15)
                # imageV3 미제공 파노(구형 큐브맵 전용)는 첫 타일부터 404 -> 폴백 유도.
                if r.status_code != 200 or not r.content:
                    return None
                try:
                    tile = Image.open(io.BytesIO(r.content)).convert("RGB")
                except Exception:
                    return None
                canvas.paste(tile, (cx * self._TILE, cy * self._TILE))
        return canvas

    def _cubemap_face(self, requests, panoid: str, rel_heading: float):
        """imageV3 미제공 파노 폴백: 큐브맵 6면 스트립에서 요청 방위에 가장 가까운
        수평 면(f/r/b/l, 각 90°)을 골라 PIL.Image 로 반환. 실패 시 None.

        스트립은 f(정면=진행방위),r(+90),b(+180),l(+270),u,d 순 가로 배열.
        """
        from PIL import Image

        self._throttle()
        r = requests.get(
            self._STRIP_URL.format(panoid=panoid), headers=self._HEADERS, timeout=15
        )
        if r.status_code != 200 or not r.content:
            return None
        try:
            strip = Image.open(io.BytesIO(r.content)).convert("RGB")
        except Exception:
            return None
        # 진행방위 기준 상대 방위 -> 가장 가까운 수평 면 인덱스(0:f,1:r,2:b,3:l).
        idx = int(((rel_heading + 45.0) % 360.0) // 90.0)
        fw = self._FACE_PX
        return strip.crop((idx * fw, 0, (idx + 1) * fw, strip.size[1]))

    def fetch(self, lat: float, lon: float, heading: float) -> bytes | None:
        import requests
        from PIL import Image

        found = self._nearest(requests, lat, lon)
        if found is None:
            return None  # 커버리지 없음
        panoid, pano_heading = found

        rel = ((float(heading) - pano_heading) % 360.0)  # 진행방위 기준 상대 방위

        # 크롭 해상도가 출력보다 충분하도록 zoom 선택(zoom0=2048px 폭).
        zoom = 1 if self.width > 1024 else 0
        equi = self._equirect(requests, panoid, zoom=zoom)
        if equi is None:
            # imageV3 미제공 파노 -> 큐브맵 면 폴백(유효 이미지 확보 우선).
            face = self._cubemap_face(requests, panoid, rel)
            if face is None:
                return None
            face = face.resize((self.width, self.height), Image.LANCZOS)
            buf = io.BytesIO()
            face.save(buf, format="JPEG", quality=88)
            return buf.getvalue()
        W, H = equi.size

        # heading 중심 fov 폭 창을 가로 방향 wrap-around 로 크롭.
        fov = float(self.fov)
        center_x = (W / 2.0) + (rel / 360.0) * W
        crop_w = max(1, int(round(fov / 360.0 * W)))
        # 세로: 지평선(H/2) 중심, 출력 종횡비에 맞춘 각도 폭.
        aspect = self.height / max(1, self.width)
        crop_h = max(1, int(round(crop_w * aspect)))
        top = int(round(H / 2.0 - crop_h / 2.0))
        top = max(0, min(H - crop_h, top))

        # wrap 처리: 좌우로 이어붙인 뒤 잘라낸다.
        left = int(round(center_x - crop_w / 2.0)) % W
        if left + crop_w <= W:
            win = equi.crop((left, top, left + crop_w, top + crop_h))
        else:
            first = equi.crop((left, top, W, top + crop_h))
            second = equi.crop((0, top, (left + crop_w) - W, top + crop_h))
            win = Image.new("RGB", (crop_w, crop_h))
            win.paste(first, (0, 0))
            win.paste(second, (first.size[0], 0))

        win = win.resize((self.width, self.height), Image.LANCZOS)
        buf = io.BytesIO()
        win.save(buf, format="JPEG", quality=88)
        return buf.getvalue()


_REGISTRY: dict[str, type[StreetViewProvider]] = {
    'mock': MockProvider,
    'google': GoogleProvider,
    'naver': NaverProvider,
}


def get_provider(
    provider: str | None = None,
    *,
    api_key: str | None = None,
    width: int = SV_WIDTH,
    height: int = SV_HEIGHT,
    fov: int = SV_FOV,
    pitch: int = SV_PITCH,
    headings: tuple[int, ...] | None = SV_HEADINGS,
    requests_per_sec: float = SV_REQUESTS_PER_SEC,
) -> StreetViewProvider:
    """provider 이름으로 provider 인스턴스 생성."""
    name = provider or default_provider()
    if name not in _REGISTRY:
        raise ValueError(f"알 수 없는 provider: {name}. 가능: {list(_REGISTRY)}")
    key = api_key if api_key is not None else default_sv_api_key()
    inst = _REGISTRY[name](
        api_key=key,
        width=width,
        height=height,
        fov=fov,
        pitch=pitch,
        headings=headings,
        requests_per_sec=requests_per_sec,
    )
    if not inst.available():
        raise RuntimeError(
            f"provider '{name}' 사용 불가(키 누락 또는 미지원). "
            "PM_SV_PROVIDER / PM_SV_API_KEY 환경변수를 확인하세요."
        )
    return inst
