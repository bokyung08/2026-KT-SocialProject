"""PMRiskViT 설정.

ZenSVI perception(안전 인지) teacher 와 동일 계열의 백본을 쓴다: torchvision
`vit_b_16` + SWAG 사전학습(`IMAGENET1K_SWAG_E2E_V1`, 384 입력) + 3-Linear/ReLU 헤드
(ZenSVI/Place Pulse ViT 구조). 단, 헤드 출력은 perception 점수가 아니라 **사고 위험
로짓**이며, TAAS 사고 라벨로 파인튜닝한다(§4.4). 데이터 희소(§4.5-1) 대응으로 기본은
backbone 고정 + 헤드만 학습.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass
class PMRiskViTConfig:
    """PMRiskViT 모델 설정.

    backbone       : torchvision ViT 이름(고정: vit_b_16).
    weights        : torchvision `ViT_B_16_Weights` 이름. 기본은 ZenSVI teacher 와 같은
                     "IMAGENET1K_SWAG_E2E_V1"(384). None 이면 랜덤 초기화.
    image_size     : 입력 한 변 크기(SWAG 가중치는 384).
    freeze_backbone: True 면 백본 고정, 헤드만 학습(linear probe, §4.5-1).
    num_labels     : 출력 로짓 개수. 이진 사고 위험은 1(sigmoid 전 로짓).
    head_hidden    : 3-Linear/ReLU 헤드의 은닉 차원(Place Pulse ViT 스타일).
    dropout        : 헤드 드롭아웃 비율.
    """

    backbone: str = "vit_b_16"
    weights: str | None = "IMAGENET1K_SWAG_E2E_V1"
    image_size: int = 384
    freeze_backbone: bool = True
    num_labels: int = 1
    head_hidden: tuple[int, ...] = (512, 128)
    dropout: float = 0.2

    def to_dict(self) -> dict:
        """설정을 dict 로 직렬화(저장용)."""
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "PMRiskViTConfig":
        """dict 로부터 설정 복원(로드용). 알 수 없는 키는 무시한다."""
        known = {f for f in cls.__dataclass_fields__}
        kw = {k: v for k, v in d.items() if k in known}
        if "head_hidden" in kw:
            kw["head_hidden"] = tuple(kw["head_hidden"])
        return cls(**kw)
