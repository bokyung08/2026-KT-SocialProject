"""models — teacher 위험도 모델(ZenSVI ViT 파인튜닝, §4.4).

실제 모델 구현은 `pm_safeline.models.pm_risk_vit` (HF-style: configuration_/modeling_)
에 있다. torch 미설치 환경에서도 `import pm_safeline` 이 안전하도록 이 `__init__`
은 pm_risk_vit 를 eager 하게 임포트하지 않는다. 필요 시
`from pm_safeline.models.pm_risk_vit import PMRiskViT, PMRiskViTConfig, build_pm_risk_vit`.
"""
