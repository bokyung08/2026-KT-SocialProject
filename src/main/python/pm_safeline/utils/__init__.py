"""utils — 데이터셋/모델에 종속되지 않는 공통 코드의 집.

데이터 파이프라인 전용 도구(config/geo/negatives/streetview)는 여기가 아니라
`pm_safeline.datasets.primitives` 에 있다. 이 패키지는 학습 루프(training),
평가(evaluation), 시각화 등 여러 곳에서 공유되는 범용 코드를 담는다(추후 추가).
"""
