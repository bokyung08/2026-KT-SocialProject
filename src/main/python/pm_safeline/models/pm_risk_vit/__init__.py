"""pm_risk_vit — teacher 위험도 모델(ZenSVI ViT 대체 백본, §4.4).

`PMRiskViTConfig` 는 하이퍼파라미터를 담는 순수 dataclass이고, `PMRiskViT`/
`build_pm_risk_vit` 는 torchvision ViT 백본을 사용하는 실제 모델 구현이다
(modeling 파일 최상단 import).
"""

from __future__ import annotations

from .configuration_pm_risk_vit import PMRiskViTConfig
from .modeling_pm_risk_vit import PMRiskViT, build_pm_risk_vit

__all__ = ["PMRiskViT", "PMRiskViTConfig", "build_pm_risk_vit"]
