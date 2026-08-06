"""PMRiskViT 모델링 (PROJECT.md §4.4 teacher).

로드뷰(단일 perspective 384 이미지) -> 사고 위험 로짓. 백본은 **torchvision
`vit_b_16`** 이며, ZenSVI perception teacher 와 동일하게 SWAG 사전학습
(`IMAGENET1K_SWAG_E2E_V1`)을 기본으로 쓴다. 헤드는 Place Pulse ViT 와 같은
3-Linear/ReLU 구조이되 출력은 **사고 위험(이진 로짓)** 이고 TAAS 라벨로 학습한다.
데이터 희소(§4.5-1) 대응으로 기본은 backbone 고정 + 헤드만 학습.
"""

from __future__ import annotations

import torch
from torch import nn
from torchvision import models

from .configuration_pm_risk_vit import PMRiskViTConfig


def _build_backbone(config: PMRiskViTConfig):
    """torchvision vit_b_16 백본 생성. weights 지정 시 사전학습 로드(SWAG 는 384)."""
    if config.weights:
        weights = getattr(models.ViT_B_16_Weights, config.weights)
        backbone = models.vit_b_16(weights=weights)
    else:
        backbone = models.vit_b_16(image_size=config.image_size)
    if backbone.image_size != config.image_size:
        raise ValueError(
            f"백본 image_size({backbone.image_size}) != config.image_size({config.image_size}). "
            f"weights={config.weights} 는 {backbone.image_size} 입력용입니다."
        )
    return backbone


class PMRiskViT(nn.Module):
    """torchvision ViT 백본 + 3-Linear/ReLU 이진 위험 헤드.

    forward() 는 sigmoid 적용 전 로짓([B, num_labels])을 반환한다. 학습 시
    BCEWithLogitsLoss(+ pos_weight, + severity 가중)로 클래스 불균형·심각도(§4.5-1)를
    반영하고, 추론 확률은 predict_proba() 를 사용한다.
    """

    def __init__(self, config: PMRiskViTConfig):
        super().__init__()
        self.config = config

        backbone = _build_backbone(config)
        in_features = backbone.heads.head.in_features  # 768
        backbone.heads = nn.Identity()                 # 기본 분류 헤드 제거(백본=특징추출기)
        self.backbone = backbone

        # 3-Linear/ReLU 위험 헤드 (Place Pulse ViT 스타일). 출력=사고 위험 로짓.
        dims = [in_features, *config.head_hidden]
        layers: list[nn.Module] = []
        for i in range(len(dims) - 1):
            layers += [nn.Linear(dims[i], dims[i + 1]), nn.ReLU(inplace=True), nn.Dropout(config.dropout)]
        layers.append(nn.Linear(dims[-1], config.num_labels))
        self.head = nn.Sequential(*layers)

        if config.freeze_backbone:
            for p in self.backbone.parameters():
                p.requires_grad_(False)

    def forward(self, pixel_values: "torch.Tensor") -> "torch.Tensor":
        """pixel_values: [B, 3, 384, 384] (ImageNet 정규화). 반환: 로짓 [B, num_labels]."""
        feats = self.backbone(pixel_values)  # heads=Identity -> [B, in_features]
        return self.head(feats)

    @torch.no_grad()
    def predict_proba(self, pixel_values: "torch.Tensor") -> "torch.Tensor":
        """추론용 사고 위험 확률. num_labels==1 이면 [B] 로 squeeze, 아니면 [B, num_labels]."""
        proba = torch.sigmoid(self.forward(pixel_values))
        if proba.shape[-1] == 1:
            return proba.squeeze(-1)
        return proba

    def trainable_parameters(self):
        """requires_grad=True 인 파라미터만 순회(옵티마이저 구성용)."""
        return (p for p in self.parameters() if p.requires_grad)

    def load_backbone_state_dict(self, path_or_state, strict: bool = False):
        """백본에 외부 가중치(예: ZenSVI safety.pth) 로드(헤드 제외).

        path_or_state 는 파일 경로 / state_dict / 피클된 nn.Module 모두 허용한다.
        네이밍 차이를 감안해 기본 strict=False 로 로드하고 불일치 키를 로깅한다.
        """
        obj = path_or_state
        if not isinstance(obj, (dict, nn.Module)):
            obj = torch.load(obj, map_location="cpu", weights_only=False)
        if isinstance(obj, nn.Module):
            obj = getattr(obj, "backbone", obj).state_dict()
        sd = obj.get("state_dict", obj) if isinstance(obj, dict) else obj
        sd = {k.replace("backbone.", "", 1): v for k, v in sd.items()}

        missing, unexpected = self.backbone.load_state_dict(sd, strict=strict)
        if missing or unexpected:
            print(
                f"[pm_risk_vit] 백본 가중치 로드: missing={len(missing)} "
                f"unexpected={len(unexpected)} (헤드/네이밍 차이 예상)"
            )
        return self


def build_pm_risk_vit(config: PMRiskViTConfig | None = None) -> PMRiskViT:
    """PMRiskViT 인스턴스 생성 편의 함수."""
    return PMRiskViT(config or PMRiskViTConfig())
