"""pmdata — PM 안전경로 프로젝트의 로드뷰 위험도 학습 데이터셋 구축 패키지.

파이프라인(§4.4 PROJECT.md):
    1. TAAS 사고 지점 로드            -> pmdata.taas
    2. exposure-matched negative 샘플 -> pmdata.negatives
    3. 도로 위 고정간격 지점 + 방위각  -> pmdata.geo
    4. 스트리트뷰 이미지 수집          -> pmdata.streetview + pmdata.collect
    5. torchvision 포맷 PyTorch Dataset -> pmdata.dataset

수집 단계(1~4)는 torch 없이 동작한다. torch/torchvision은
pmdata.dataset 을 실제로 사용할 때만 필요하며 지연 임포트된다.
"""

from __future__ import annotations

from .config import Config, DEFAULT_CONFIG

__all__ = ["Config", "DEFAULT_CONFIG"]
__version__ = "0.1.0"
