"""Teacher 위험도 모델 (PROJECT.md §4.4 step 2).

로드뷰 이미지 -> 사고 확률(위험도) 예측. ZenSVI 백본(ViT)을 재사용하되,
데이터 희소성(§4.5-1)을 고려해 **backbone 고정 + 소형 헤드만 학습**(linear probe)을 기본으로 한다.

이 모델은 IRL 가중치 학습(§4.4 step 5) 단계에서만 teacher 로 쓰이고,
배포 시에는 손을 뗀다(OSM feature 가중합 student 만 사용).

torch/torchvision 은 지연 임포트한다. 현재 venv(Py3.14)에 torch 미설치 시
별도 학습 env 필요(README 참고).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import torch
    from torch import nn


def _require_torch():
    try:
        import torch  # noqa: F401
        import torchvision  # noqa: F401
    except ImportError as e:  # pragma: no cover
        raise ImportError(
            "teacher 모델에는 torch/torchvision 이 필요합니다. 별도 학습 env 를 사용하세요 "
            "(README: `pip install -e \".[train]\"`)."
        ) from e


@dataclass(frozen=True)
class TeacherConfig:
    """teacher 파인튜닝 설정."""

    # 백본: torchvision 사전학습 ViT (ZenSVI 가중치 로드 전까지의 대체/부트스트랩).
    backbone: str = "vit_b_16"
    freeze_backbone: bool = True          # §4.5-1: linear probe 기본
    num_outputs: int = 1                  # 사고 확률(로짓) 1개
    dropout: float = 0.1
    pretrained: bool = True


def build_teacher(cfg: TeacherConfig = TeacherConfig()) -> "nn.Module":
    """ViT 백본 + 소형 위험도 헤드로 teacher 모델 구성.

    반환 모델의 출력은 로짓(sigmoid 전). 학습 시 BCEWithLogitsLoss + pos_weight 로
    클래스 불균형(§4.5-1)을 보정하고, 추론 확률은 이후 calibration(§4.5 부가) 대상.
    """
    _require_torch()
    import torch
    from torch import nn
    from torchvision import models

    weights = "DEFAULT" if cfg.pretrained else None
    backbone = getattr(models, cfg.backbone)(weights=weights)

    # torchvision ViT 는 heads.head 가 최종 분류층. 이를 위험도 헤드로 교체.
    in_features = backbone.heads.head.in_features
    backbone.heads.head = nn.Sequential(
        nn.Dropout(cfg.dropout),
        nn.Linear(in_features, cfg.num_outputs),
    )

    if cfg.freeze_backbone:
        for name, p in backbone.named_parameters():
            if not name.startswith("heads."):
                p.requires_grad_(False)

    return backbone


def load_zensvi_backbone(model: "nn.Module", state_dict_path: str) -> "nn.Module":
    """ZenSVI 사전학습 가중치를 백본에 로드(헤드 제외).

    ZenSVI 배포 가중치의 키 네이밍은 버전마다 다르므로 strict=False 로 로드하고
    불일치 키를 로깅한다. TODO(§4.4): 실제 ZenSVI 체크포인트 확보 후 키 매핑 확정.
    """
    _require_torch()
    import torch

    sd = torch.load(state_dict_path, map_location="cpu")
    sd = sd.get("state_dict", sd)
    missing, unexpected = model.load_state_dict(sd, strict=False)
    if missing or unexpected:
        print(f"[teacher] ZenSVI 로드: missing={len(missing)} unexpected={len(unexpected)} (헤드/네이밍 차이 예상)")
    return model
