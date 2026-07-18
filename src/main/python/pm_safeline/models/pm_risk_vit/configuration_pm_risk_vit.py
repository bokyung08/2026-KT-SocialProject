"""PMRiskViT 설정 (HF-style config).

teacher 위험도 모델(PROJECT.md §4.4 step 2)의 하이퍼파라미터를 담는 순수 dataclass.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass
class PMRiskViTConfig:
    """PMRiskViT 모델 설정.

    backbone       : torchvision 사전학습 ViT 이름 (ZenSVI ViT 의 대체/부트스트랩).
    pretrained     : ImageNet 사전학습 가중치 사용 여부.
    freeze_backbone: True 면 백본을 고정하고 헤드만 학습(§4.5-1: 데이터 희소 → linear probe 기본).
    num_labels     : 출력 로짓 개수. 이진 위험도는 1(sigmoid 전 로짓).
    dropout        : 헤드 드롭아웃 비율.
    image_size     : 입력 이미지 한 변 크기(정사각형, 기본 224).
    """

    backbone: str = "vit_b_16"
    pretrained: bool = True
    freeze_backbone: bool = True
    num_labels: int = 1
    dropout: float = 0.1
    image_size: int = 224

    def to_dict(self) -> dict:
        """설정을 dict 로 직렬화(저장용)."""
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "PMRiskViTConfig":
        """dict 로부터 설정 복원(로드용). 알 수 없는 키는 무시한다."""
        known = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in d.items() if k in known})
