# pm_safeline — PM 로드뷰 위험도 학습 데이터셋 구축

PROJECT.md §4.4 "Street-view 기반 파인튜닝 + 지식 증류"의 **teacher 모델 학습 데이터셋**을
구축하는 파이썬 패키지. TAAS 사고 지점과 대조 지점에 대한 스트리트뷰 이미지를 모아
torchvision 포맷 PyTorch `Dataset`으로 제공한다.

## 패키지 구조

`src/main/python/` 가 소스 루트이며, 단일 패키지 `pm_safeline` 아래 3개 서브패키지로 구성:

```
pm_safeline/
├── datasets/    # 데이터셋
│   ├── accidents.py    AccidentDataset — 사고 지점(KoROAD 오픈API + TAAS 수동 CSV 통합, 스키마 검증)
│   ├── roadview.py     PMRoadviewDataset/build_roadview_dataset — 로드뷰 이미지 수집(torchvision, +분할)
│   └── primitives/     # 데이터 파이프라인 저수준 도구
│       ├── config.py       설정(대전 BBOX·경로·스트리트뷰/샘플링) + .env 로더
│       ├── geo.py          OSM 도로망 → 고정간격 지점 + 방위각, 사고점 스냅
│       ├── negatives.py    exposure-matched negative 샘플링(§4.5-2)
│       └── streetview.py   스트리트뷰 provider(mock/google/naver/kakao)
├── models/      # teacher 위험도 모델 (HF 스타일)
│   └── pm_risk_vit/     modeling_pm_risk_vit.py — ViT 로드뷰→사고위험 (§4.4)
├── utils/       # 데이터셋/모델에 안 묶이는 공통 코드
│   ├── training.py      teacher 학습 루프·k-fold·calibration·checkpoint
│   └── irl.py           역강화학습(§4.2·4.4): edge→route 위험 집계(hazard-rate, §4.5-3) + 경로쌍 선호→Bradley-Terry w1~w5 학습
└── __main__.py  # CLI (python -m pm_safeline)
```
학습·IRL 노트북: `src/test/ipython/{test_datasets,train_teacher,train_irl}.ipynb`

| 단계 | 모듈 | torch |
|---|---|---|
| 1. 사고 로드(KoROAD/TAAS, 다지역) | `pm_safeline.datasets.accidents` | ❌ |
| 2. OSM 지점 샘플링·스냅 | `pm_safeline.datasets.primitives.geo` | ❌ |
| 3. exposure-matched negative | `pm_safeline.datasets.primitives.negatives` | ❌ |
| 4. 로드뷰 이미지 수집(4방향) | `...primitives.streetview`, `datasets.roadview` | ❌ |
| 5. PyTorch Dataset | `pm_safeline.datasets.roadview` | ✅ |
| 6. teacher ViT 학습 | `pm_safeline.models.pm_risk_vit` + `utils.training` | ✅ |
| 7. IRL 가중치 학습 | `pm_safeline.utils.irl` | ❌ (numpy/scipy) |

## 사용법

`uv sync` 하면 `pm_safeline` 이 editable 로 설치되어(빌드 대상: `src/main/python/pm_safeline`)
어느 디렉토리에서든 `import pm_safeline` 가 된다. sys.path 조작이 필요 없다.

```bash
# 0) 설정 점검
python -m pm_safeline check

# 1) 사고 데이터: KoROAD 이륜차 다발지역 오픈API 자동 다운로드 (기본 소스)
#    인증키는 https://opendata.koroad.or.kr 에서 발급 -> 환경변수로 지정.
KOROAD_API_KEY=<KEY> python -m pm_safeline download            # data/raw/ 에 캐시
#    (수동 소스를 쓰려면 대신 data/raw/ 에 TAAS CSV/XLSX 를 넣고 collect --source taas)

# 2) 수집 파이프라인 — 사고(koroad) + OSM + negative + 이미지
#    네트워크/키 없이 이미지 단계만 검증하려면 mock provider:
KOROAD_API_KEY=<KEY> PM_SV_PROVIDER=mock python -m pm_safeline collect --limit 50

# 2') 실제 이미지 수집 (Google Street View Static API)
KOROAD_API_KEY=<KEY> PM_SV_PROVIDER=google PM_SV_API_KEY=<SV_KEY> python -m pm_safeline collect

# 3) 통계
python -m pm_safeline stats
```

데이터 저장 위치: 항상 **프로젝트 루트의 `data/`** (CWD 무관, gitignore 됨). `PM_DATA_DIR` 로 재정의 가능.

산출물(`<repo>/data/`):
- `raw/` — KoROAD 다운로드 캐시(`koroad_motorcycle_frequentzone.csv`) 또는 수동 TAAS 원본
- `sample_points.gpkg` — 라벨 지점(사고=1/대조=0, heading 포함)
- `streetview/{accident,control}/<point_id>_h###.jpg` — torchvision ImageFolder 레이아웃
- `manifest.csv` — `point_id,label,class,lat,lon,heading,severity,mode,path`

## PyTorch Dataset

`uv sync` 로 패키지가 설치되어 있으면 어디서든:

```python
from pm_safeline.datasets.roadview import PMRoadviewDataset, default_transform

ds = PMRoadviewDataset(transform=default_transform(train=True))   # (image, label)
ds_meta = PMRoadviewDataset(return_meta=True)                     # (image, label, meta)
ds_sev = PMRoadviewDataset(target_key="severity")                # 심각도 회귀/다중클래스

from pm_safeline.datasets.roadview import image_folder
folder_ds = image_folder()                                        # 순수 ImageFolder
```

- torchvision 관례 준수: `(sample, target)` 반환, `transform`/`target_transform`, `.targets`, `.classes`.
- 클래스 불균형(§4.5-1) 대응 `ds.class_weights()` 제공.

### train/valid 분할 (지점 누수 방지 + 라벨 stratify)

```python
from pm_safeline.datasets.roadview import make_train_valid, split_indices, kfold_indices

# 학습용 (train=증강, valid=결정적 transform 자동 적용)
train_ds, valid_ds = make_train_valid(valid_frac=0.2, seed=42)

# 인덱스만 필요하면 (sklearn)
train_idx, valid_idx = split_indices(manifest_or_dataset, valid_frac=0.2)
folds = kfold_indices(manifest_or_dataset, n_splits=5)   # 적은 데이터 신뢰도 추정용
```

- **같은 `point_id`(여러 heading)는 한쪽에만** 들어가 누수를 막고, 사고/대조 비율을 유지(StratifiedGroupKFold).
- 데이터가 적어 **별도 test 분할은 두지 않음** — 필요 시 `kfold_indices`로 교차검증(대화 결정, §4.5-1).

## 학습 (teacher + IRL)

프로젝트는 **Python 3.12 단일 venv**(`.venv`)를 쓴다. torch 포함 모든 의존성이 여기 들어있어
수집·학습·IRL 전부 같은 env 에서 돈다.

```bash
uv sync            # .venv (Py3.12) 생성 + 전체 의존성(torch 포함) 설치

# 노트북: teacher 학습 / IRL  (src/test/ipython/)
#   train_teacher.ipynb  (실 manifest 필요 → 먼저 python -m pm_safeline collect)
#   train_irl.ipynb      (합성 데모 → 학습된 w1~w5 출력)
```

- **teacher**: `build_pm_risk_vit(PMRiskViTConfig(freeze_backbone=True))` + `utils.training.train_teacher` (BCE+pos_weight, k-fold, temperature calibration).
- **IRL**: teacher가 매긴 edge 위험 → `utils.irl.route_risk` 집계 → 경로쌍 선호 → `utils.irl.fit_bradley_terry` 로 w1~w5 학습 → 서버 `PmCostWeights` 에 주입.

## 환경 주의

- venv는 **Python 3.12 단일 `.venv`**. `uv sync` 로 torch(CUDA) 포함 전체 의존성이 설치되어 수집·학습·IRL 이 모두 같은 env 에서 돈다.
- 의존성 추가는 `uv add` 사용(`uv pip install` 금지).

## 미확정 이슈 (PROJECT.md §4.5, 코드에 훅만 마련)

- **네이버 로드뷰 약관(§4.5-5)**: 공식 정적 REST 부재 → `NaverProvider`는 스텁. 약관 확인 후 구현.
- **Route risk 집계(§4.5-3)**: 본 패키지는 지점 단위 이미지까지. 경로 집계는 별도.
- **exposure 대리지표**: 실 KT 이동량 부재 → 기본은 도로 위계(highway rank). `exposure_col`로 실측 주입 가능.
- **촬영-사고 시간차(§4.5-4)**: 오래된 사고 필터링은 호출측에서 `datetime` 기준 사전 필터 권장.
