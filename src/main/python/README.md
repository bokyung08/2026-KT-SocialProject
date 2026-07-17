# pm_proj — PM 로드뷰 위험도 학습 데이터셋 구축

PROJECT.md §4.4 "Street-view 기반 파인튜닝 + 지식 증류"의 **teacher 모델 학습 데이터셋**을
구축하는 파이썬 패키지. TAAS 사고 지점과 대조 지점에 대한 스트리트뷰 이미지를 모아
torchvision 포맷 PyTorch `Dataset`으로 제공한다.

## 패키지 구조

`src/main/python/` 가 소스 루트이며, 단일 패키지 `pm_proj` 아래 3개 서브패키지로 구성:

```
pm_proj/
├── utils/       # 저수준 primitives
│   ├── config.py       설정(대전 BBOX·경로·스트리트뷰/샘플링)
│   ├── koroad.py       KoROAD 이륜차 교통사고 다발지역 오픈API 자동 다운로드(기본 사고 소스)
│   ├── taas.py         TAAS 사고 CSV/XLSX 로드(컬럼 자동탐지·PM 필터, 수동 소스)
│   ├── geo.py          OSM 도로망 → 고정간격 지점 + 방위각, 사고점 스냅
│   ├── negatives.py    exposure-matched negative 샘플링(§4.5-2)
│   └── streetview.py   스트리트뷰 provider(mock/google/naver-stub)
├── datasets/    # 오케스트레이션 + Dataset
│   ├── collect.py      수집 파이프라인 → ImageFolder 레이아웃 + manifest
│   └── dataset.py      torchvision 포맷 PMRoadviewDataset (torch 지연 임포트)
├── models/      # teacher 위험도 모델(ZenSVI ViT 파인튜닝, §4.4) — 다음 단계
└── __main__.py  # CLI (python -m pm_proj)
```

| 단계 | 모듈 | torch |
|---|---|---|
| 1. TAAS 사고 로드 | `pm_proj.utils.taas` | ❌ |
| 2. OSM 도로망/지점 샘플링·스냅 | `pm_proj.utils.geo` | ❌ |
| 3. exposure-matched negative | `pm_proj.utils.negatives` | ❌ |
| 4. 스트리트뷰 이미지 수집 | `pm_proj.utils.streetview`, `pm_proj.datasets.collect` | ❌ |
| 5. PyTorch Dataset | `pm_proj.datasets.dataset` | ✅ (학습 시에만) |

## 사용법

모든 명령은 `src/main/python/` 에서 실행한다.

```bash
cd src/main/python

# 0) 설정 점검 (torch 불필요)
python -m pm_proj check

# 1) 사고 데이터: KoROAD 이륜차 다발지역 오픈API 자동 다운로드 (기본 소스)
#    인증키는 https://opendata.koroad.or.kr 에서 발급 -> 환경변수로 지정.
KOROAD_API_KEY=<KEY> python -m pm_proj download            # data/raw/ 에 캐시
#    (수동 소스를 쓰려면 대신 data/raw/ 에 TAAS CSV/XLSX 를 넣고 collect --source taas)

# 2) 수집 파이프라인 — 사고(koroad) + OSM + negative + 이미지
#    네트워크/키 없이 이미지 단계만 검증하려면 mock provider:
KOROAD_API_KEY=<KEY> PM_SV_PROVIDER=mock python -m pm_proj collect --limit 50

# 2') 실제 이미지 수집 (Google Street View Static API)
KOROAD_API_KEY=<KEY> PM_SV_PROVIDER=google PM_SV_API_KEY=<SV_KEY> python -m pm_proj collect

# 3) 통계
python -m pm_proj stats
```

데이터 저장 위치: 항상 **프로젝트 루트의 `data/`** (CWD 무관, gitignore 됨). `PM_DATA_DIR` 로 재정의 가능.

산출물(`<repo>/data/`):
- `raw/` — KoROAD 다운로드 캐시(`koroad_motorcycle_frequentzone.csv`) 또는 수동 TAAS 원본
- `sample_points.gpkg` — 라벨 지점(사고=1/대조=0, heading 포함)
- `streetview/{accident,control}/<point_id>_h###.jpg` — torchvision ImageFolder 레이아웃
- `manifest.csv` — `point_id,label,class,lat,lon,heading,severity,mode,path`

## PyTorch Dataset

`src/main/python` 이 sys.path 에 있을 때(학습 스크립트를 이 디렉토리에서 실행):

```python
from pm_proj.datasets.dataset import PMRoadviewDataset, default_transform

ds = PMRoadviewDataset(transform=default_transform(train=True))   # (image, label)
ds_meta = PMRoadviewDataset(return_meta=True)                     # (image, label, meta)
ds_sev = PMRoadviewDataset(target_key="severity")                # 심각도 회귀/다중클래스

from pm_proj.datasets.dataset import image_folder
folder_ds = image_folder()                                        # 순수 ImageFolder
```

- torchvision 관례 준수: `(sample, target)` 반환, `transform`/`target_transform`, `.targets`, `.classes`.
- 클래스 불균형(§4.5-1) 대응 `ds.class_weights()` 제공.

## 환경 주의 (메모리 pm-pilot-study 근거)

- venv는 **Python 3.14** — `torch` 휠이 아직 불확실. 수집(1~4단계)은 torch 없이 동작하도록 설계됨.
- 학습(5단계)에는 torch 필요: `pip install -e ".[train]"`, 실패 시 Py3.12 별도 env 권장.
- 의존성 추가는 `uv add` 사용(`uv pip install` 금지).

## 미확정 이슈 (PROJECT.md §4.5, 코드에 훅만 마련)

- **네이버 로드뷰 약관(§4.5-5)**: 공식 정적 REST 부재 → `NaverProvider`는 스텁. 약관 확인 후 구현.
- **Route risk 집계(§4.5-3)**: 본 패키지는 지점 단위 이미지까지. 경로 집계는 별도.
- **exposure 대리지표**: 실 KT 이동량 부재 → 기본은 도로 위계(highway rank). `exposure_col`로 실측 주입 가능.
- **촬영-사고 시간차(§4.5-4)**: 오래된 사고 필터링은 호출측에서 `datetime` 기준 사전 필터 권장.
