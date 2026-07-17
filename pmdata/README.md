# pmdata — PM 로드뷰 위험도 학습 데이터셋 구축

PROJECT.md §4.4 "Street-view 기반 파인튜닝 + 지식 증류"의 **teacher 모델 학습 데이터셋**을
구축하는 파이썬 패키지. TAAS 사고 지점과 대조 지점에 대한 스트리트뷰 이미지를 모아
torchvision 포맷 PyTorch `Dataset`으로 제공한다.

## 파이프라인

```
TAAS 사고 CSV(수동 다운로드)  ─┐
                               ├─ 사고점 스냅(heading) ─┐
OSM 도로망(osmnx, 자동)      ─┤                        ├─ 라벨 지점 ─ 스트리트뷰 수집 ─ manifest + ImageFolder
                               └─ 도로 고정간격 지점 ──┘        (exposure-matched negative)
```

| 단계 | 모듈 | torch 필요 |
|---|---|---|
| 1. TAAS 사고 로드 | `pmdata.taas` | ❌ |
| 2. OSM 도로망/지점 샘플링·스냅 | `pmdata.geo` | ❌ |
| 3. exposure-matched negative | `pmdata.negatives` | ❌ |
| 4. 스트리트뷰 이미지 수집 | `pmdata.streetview`, `pmdata.collect` | ❌ |
| 5. PyTorch Dataset | `pmdata.dataset` | ✅ (학습 시에만) |

## 사용법

```bash
# 0) 설정 점검 (torch 불필요)
python -m pmdata check

# 1) TAAS 원본을 data/raw/ 에 수동 다운로드 (koroad.or.kr TAAS)
#    - data.go.kr/TAAS 자동 다운로드는 anti-bot 차단(메모리 확인). CSV/XLSX 수동 저장.

# 2) 수집 파이프라인 — 네트워크/키 없이 검증(mock 이미지)
PM_SV_PROVIDER=mock python -m pmdata collect --limit 50

# 2') 실제 수집 (Google Street View Static API)
PM_SV_PROVIDER=google PM_SV_API_KEY=<KEY> python -m pmdata collect

# 3) 통계
python -m pmdata stats
```

산출물(`data/`):
- `raw/` — 사용자가 넣는 TAAS 원본
- `sample_points.gpkg` — 라벨 지점(사고=1/대조=0, heading 포함)
- `streetview/{accident,control}/<point_id>_h###.jpg` — torchvision ImageFolder 레이아웃
- `manifest.csv` — `point_id,label,class,lat,lon,heading,severity,mode,path`

## PyTorch Dataset

```python
from pmdata.dataset import PMRoadviewDataset, default_transform

ds = PMRoadviewDataset(transform=default_transform(train=True))   # (image, label)
ds_meta = PMRoadviewDataset(return_meta=True)                     # (image, label, meta)

# 심각도 회귀/다중클래스로 쓰려면:
ds_sev = PMRoadviewDataset(target_key="severity")

# 순수 ImageFolder 가 필요하면:
from pmdata.dataset import image_folder
folder_ds = image_folder()
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
