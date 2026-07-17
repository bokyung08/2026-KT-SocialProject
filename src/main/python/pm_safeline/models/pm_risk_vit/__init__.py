"""pm_risk_vit — teacher 위험도 모델(ZenSVI ViT 대체 백본, §4.4).

`PMRiskViTConfig` 는 torch 없이도 임포트 가능하지만, `PMRiskViT`/`build_pm_risk_vit`
는 torch/torchvision 이 필요하다(modeling 파일 최상단 import). 이 패키지는 모듈
`__getattr__` 로 지연 임포트해 torch 미설치 환경에서도 `import pm_safeline` 및
`from pm_safeline.models.pm_risk_vit import PMRiskViTConfig` 가 안전하도록 한다.
실제로 `PMRiskViT`/`build_pm_risk_vit` 를 사용하는 시점에만 torch 가 필요하다.
"""

from __future__ import annotations

from .configuration_pm_risk_vit import PMRiskViTConfig

__all__ = ["PMRiskViT", "PMRiskViTConfig", "build_pm_risk_vit"]


def __getattr__(name: str):
    if name in ("PMRiskViT", "build_pm_risk_vit"):
        try:
            from . import modeling_pm_risk_vit as _m
        except ImportError as e:
            raise ImportError(
                f"'{name}' 사용에는 torch/torchvision 이 필요합니다. 별도 학습 env 를 사용하세요 "
                "(README: `pip install -e \".[train]\"`)."
            ) from e
        return getattr(_m, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
