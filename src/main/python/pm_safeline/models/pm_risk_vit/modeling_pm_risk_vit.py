"""PMRiskViT 모델링 (PROJECT.md §4.4 teacher).

로드뷰(단일 perspective) 이미지 -> 사고 위험도(확률) 예측. 백본은 torchvision ViT
(ZenSVI ViT 의 대체/부트스트랩)이며, 데이터 희소성(§4.5-1)을 고려해 기본값은
**backbone 고정 + 소형 헤드만 학습**(linear probe)이다.

이 모듈은 torch/torchvision 을 모듈 최상단에서 임포트한다(HF 관례).
"""

from __future__ import annotations

import torch
from torch import nn
from torchvision import models

from .configuration_pm_risk_vit import PMRiskViTConfig


class PMRiskViT(nn.Module):
    """ViT 백본 + 이진 위험도 헤드.

    forward() 는 sigmoid 적용 전 로짓([B, num_labels])을 반환한다. 학습 시
    BCEWithLogitsLoss(+ pos_weight)로 클래스 불균형(§4.5-1)을 보정하고,
    추론 확률은 predict_proba() 를 사용한다.
    """

    def __init__(self, config: PMRiskViTConfig):
        super().__init__()
        self.config = config

        weights = "DEFAULT" if config.pretrained else None
        backbone = getattr(models, config.backbone)(weights=weights)

        # torchvision ViT 는 heads.head 가 최종 분류층. 이를 위험도 헤드로 교체.
        in_features = backbone.heads.head.in_features
        backbone.heads.head = nn.Sequential(
            nn.Dropout(config.dropout),
            nn.Linear(in_features, config.num_labels),
        )
        self.backbone = backbone

        if config.freeze_backbone:
            for name, p in self.backbone.named_parameters():
                if not name.startswith("heads."):
                    p.requires_grad_(False)

    def forward(self, pixel_values: "torch.Tensor") -> "torch.Tensor":
        """pixel_values: [B, 3, H, W] (ImageNet 정규화). 반환: 로짓 [B, num_labels]."""
        return self.backbone(pixel_values)

    @torch.no_grad()
    def predict_proba(self, pixel_values: "torch.Tensor") -> "torch.Tensor":
        """추론용 사고 위험 확률. num_labels==1 이면 [B] 로 squeeze, 아니면 [B, num_labels]."""
        logits = self.forward(pixel_values)
        proba = torch.sigmoid(logits)
        if proba.shape[-1] == 1:
            return proba.squeeze(-1)
        return proba

    def load_backbone_state_dict(self, path_or_state, strict: bool = False):
        """ZenSVI 사전학습 가중치를 백본에 로드(헤드 제외 가능).

        ZenSVI 배포 가중치의 키 네이밍은 버전마다 다를 수 있어 기본 strict=False 로
        로드하고 불일치 키를 로깅한다. path_or_state 는 파일 경로(str/Path) 또는
        이미 로드된 state_dict 모두 허용한다.
        """
        if isinstance(path_or_state, dict):
            sd = path_or_state
        else:
            sd = torch.load(path_or_state, map_location="cpu")
        sd = sd.get("state_dict", sd) if isinstance(sd, dict) else sd

        missing, unexpected = self.backbone.load_state_dict(sd, strict=strict)
        if missing or unexpected:
            print(
                f"[pm_risk_vit] ZenSVI 백본 로드: missing={len(missing)} "
                f"unexpected={len(unexpected)} (헤드/네이밍 차이 예상)"
            )
        return self

    def trainable_parameters(self):
        """requires_grad=True 인 파라미터만 순회(옵티마이저 구성용)."""
        for p in self.parameters():
            if p.requires_grad:
                yield p


def build_pm_risk_vit(config: PMRiskViTConfig | None = None) -> PMRiskViT:
    """PMRiskViT 인스턴스 생성 편의 함수."""
    return PMRiskViT(config or PMRiskViTConfig())
