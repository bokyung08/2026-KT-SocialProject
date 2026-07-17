"""torchvision 포맷 PyTorch Dataset.

두 가지 진입점을 제공한다.
    1) PMRoadviewDataset : manifest.csv 기반 커스텀 Dataset.
       - torchvision datasets 관례 준수: (sample, target) 반환, transform/target_transform 지원,
         root/transform 시그니처. 추가로 지리 메타데이터(lat/lon/heading/severity)를 함께 노출.
    2) image_folder()    : 순수 torchvision.datasets.ImageFolder 로 열기(디렉토리 레이아웃만 사용).

torch / torchvision 은 이 모듈을 실제로 쓸 때만 필요하므로 **함수/클래스 내부에서 지연 임포트**한다.
수집 파이프라인(pmdata.collect 등)은 torch 없이 동작한다.

참고(메모리): 현재 venv(Py3.14)에는 torch 미설치. torch 휠이 없는 환경에서는
학습 전용 별도 env(예: Py3.12 + torch)에서 이 모듈을 사용하는 것을 권장.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable, TYPE_CHECKING

import pandas as pd

from .primitives.config import Config, DEFAULT_CONFIG
from .primitives.streetview import StreetViewProvider, get_provider

if TYPE_CHECKING:  # 타입 힌트용(런타임 임포트 아님)
    import geopandas as gpd
    import torch
    from torch.utils.data import Dataset as _TorchDataset
else:
    _TorchDataset = object  # 런타임엔 torch 없이도 클래스 정의 가능하도록


def _require_torch():
    try:
        import torch  # noqa: F401
        import torchvision  # noqa: F401
    except ImportError as e:  # pragma: no cover
        raise ImportError(
            "PMRoadviewDataset 사용에는 torch/torchvision 이 필요합니다. "
            "현재 venv(Py3.14)에 torch 휠이 없으면 별도 학습 env 를 만드세요. "
            "예: `uv venv --python 3.12 .venv-train && uv pip install torch torchvision`"
        ) from e


# --------------------------------------------------------------------------- #
# 수집 오케스트레이터: 라벨 지점 -> 이미지 다운로드 + torchvision ImageFolder 레이아웃 + manifest.
#
# 디스크 레이아웃(torchvision.datasets.ImageFolder 호환):
#     <data>/streetview/accident/<point_id>[_h###].jpg
#     <data>/streetview/control/<point_id>[_h###].jpg
#     <data>/manifest.csv   # point_id,label,class,lat,lon,heading,severity,mode,path
#
# 캐시: 이미 파일이 존재하면 재다운로드하지 않음(중단 후 재개 안전).
# 이 로직은 torch 불필요(수집 파이프라인은 torch 없이 동작해야 함).
# --------------------------------------------------------------------------- #
CLASS_NAMES = {1: "accident", 0: "control"}


def _headings_for(row, cfg: Config) -> list[float]:
    base = row.get("heading")
    configured = cfg.streetview.headings
    if configured:
        return [float(h) for h in configured]
    if base is None or pd.isna(base):
        # 방위각 미상 지점: 4방위로 촬영
        return [0.0, 90.0, 180.0, 270.0]
    return [float(base)]


def collect_images(
    labeled_points: "gpd.GeoDataFrame",
    cfg: Config = DEFAULT_CONFIG,
    provider: StreetViewProvider | None = None,
    *,
    limit: int | None = None,
) -> pd.DataFrame:
    """labeled_points(build_labeled_points 출력) 를 순회하며 이미지 수집 + manifest 작성.

    반환: manifest DataFrame. 실패/커버리지 없음 지점은 manifest 에서 제외.
    """
    cfg.ensure_dirs()
    for cls in CLASS_NAMES.values():
        (cfg.images_dir / cls).mkdir(parents=True, exist_ok=True)

    provider = provider or get_provider(cfg)

    records: list[dict] = []
    rows = labeled_points.iloc[:limit] if limit else labeled_points
    total = len(rows)
    for i, (_, row) in enumerate(rows.iterrows(), 1):
        label = int(row["label"])
        cls = CLASS_NAMES[label]
        for heading in _headings_for(row, cfg):
            pid = str(row["point_id"])
            fname = f"{pid}_h{int(round(heading)):03d}.jpg"
            out_path = cfg.images_dir / cls / fname

            if not out_path.exists():
                try:
                    img = provider.fetch(float(row["lat"]), float(row["lon"]), heading)
                except Exception as e:  # noqa: BLE001
                    print(f"[collect] {pid} h{heading} 실패: {e}")
                    continue
                if img is None:
                    continue  # 커버리지 없음
                out_path.write_bytes(img)

            records.append(
                {
                    "point_id": pid,
                    "label": label,
                    "class": cls,
                    "lat": float(row["lat"]),
                    "lon": float(row["lon"]),
                    "heading": round(float(heading), 1),
                    "severity": row.get("severity"),
                    "mode": row.get("mode"),
                    "path": str(out_path.relative_to(cfg.data_dir)),
                }
            )
        if i % 100 == 0 or i == total:
            print(f"[collect] {i}/{total} 지점 처리")

    manifest = pd.DataFrame.from_records(records)
    if not manifest.empty:
        manifest.to_csv(cfg.manifest_path, index=False, encoding="utf-8-sig")
        print(f"[collect] manifest 저장: {cfg.manifest_path} ({len(manifest)} 이미지)")
    else:
        print("[collect] 수집된 이미지가 없습니다(커버리지/키/약관 확인).")
    return manifest


def build_roadview_dataset(
    cfg: Config = DEFAULT_CONFIG,
    *,
    source: str = "koroad",
    pm_only: bool = True,
    limit: int | None = None,
) -> pd.DataFrame:
    """전체 수집 파이프라인 원샷 실행(torch 불필요).

    사고 로드 -> OSM edge -> 지점 샘플링 -> negative 매칭 -> 라벨결합 -> 이미지 수집.
    각 단계 산출물은 data/ 에 캐시된다.

    source:
        "koroad" (기본) — KoROAD 이륜차 교통사고 다발지역 오픈API 자동 다운로드.
        "taas"          — data/raw/ 의 수동 다운로드 CSV/XLSX 사용.
    """
    from .primitives import geo, negatives
    from .accidents import load_accidents

    print(f"[pipeline] 1/5 사고 로드 (source={source})")
    accidents = load_accidents(source, cfg, pm_only=pm_only)
    print(f"[pipeline]   {len(accidents)}건 · severity={accidents['severity'].value_counts().to_dict()}")

    # OSM·negative 영역은 하드코딩 bbox 가 아니라 '사고 좌표들의 실제 범위(+여유)'로 잡는다.
    import dataclasses
    minx, miny, maxx, maxy = accidents.total_bounds        # (W, S, E, N)
    margin = 0.01  # 약 1km — negative 를 사고 주변에서 뽑을 여지
    region = (minx - margin, miny - margin, maxx + margin, maxy + margin)
    cfg = dataclasses.replace(cfg, bbox=region)
    print(f"[pipeline]   작업 영역=사고 범위+여유 {tuple(round(v, 3) for v in region)}")

    print("[pipeline] 2/5 OSM 도로망 로드")
    edges = geo.load_drive_edges(cfg)

    print("[pipeline] 3/5 사고 스냅 + 도로 지점 샘플링")
    acc_snapped = geo.snap_accidents_to_edges(accidents, edges, cfg)
    candidates = geo.sample_points_along_edges(edges, cfg)

    print("[pipeline] 4/5 exposure-matched negative 샘플링")
    negs = negatives.sample_negatives(acc_snapped, candidates, cfg)
    labeled = negatives.build_labeled_points(acc_snapped, negs)
    cfg.ensure_dirs()
    labeled.to_file(cfg.points_path, driver="GPKG")
    print(f"[pipeline] 라벨 지점 저장: {cfg.points_path} "
          f"(pos={int((labeled.label==1).sum())}, neg={int((labeled.label==0).sum())})")

    print("[pipeline] 5/5 이미지 수집")
    return collect_images(labeled, cfg, limit=limit)


class PMRoadviewDataset(_TorchDataset):
    """manifest.csv 로 정의된 로드뷰 위험도 데이터셋.

    각 항목: (image, target)
        image  : transform 적용 결과(기본 미적용 시 PIL.Image)
        target : 기본은 int label(1=accident, 0=control).
                 target_transform 또는 target_key 로 커스터마이즈 가능.

    인자:
        root            : data_dir (manifest.csv, streetview/ 를 포함). None 이면 cfg.data_dir.
        transform       : 이미지 변환(torchvision.transforms 등).
        target_transform: 타깃 변환.
        target_key      : manifest 컬럼명. 기본 "label". "severity" 등 회귀/다중클래스 대응.
        return_meta     : True 면 (image, target, meta_dict) 3-튜플 반환.
    """

    def __init__(
        self,
        root: str | Path | None = None,
        transform: Callable | None = None,
        target_transform: Callable | None = None,
        download: bool = False,
        *,
        cfg: Config = DEFAULT_CONFIG,
        target_key: str = "label",
        return_meta: bool = False,
        source: str = "koroad",
        pm_only: bool = True,
        limit: int | None = None,
    ):
        _require_torch()
        import pandas as pd

        self.cfg = cfg
        self.root = Path(root) if root is not None else cfg.data_dir
        manifest_path = self.root / "manifest.csv"
        if download:
            build_roadview_dataset(cfg, source=source, pm_only=pm_only, limit=limit)
        if not manifest_path.exists():
            raise FileNotFoundError(
                f"manifest 가 없습니다: {manifest_path}. 먼저 수집 파이프라인을 실행하세요 "
                "(`python -m pmdata collect`) 또는 download=True 를 사용하세요."
            )
        self.frame = pd.read_csv(manifest_path)
        self.transform = transform
        self.target_transform = target_transform
        self.target_key = target_key
        self.return_meta = return_meta

        if target_key not in self.frame.columns:
            raise KeyError(f"target_key '{target_key}' 가 manifest 컬럼에 없습니다: {list(self.frame.columns)}")

    # torchvision 관례 -------------------------------------------------------
    def __len__(self) -> int:
        return len(self.frame)

    def __getitem__(self, index: int) -> tuple[Any, ...]:
        from PIL import Image

        row = self.frame.iloc[index]
        img_path = self.root / str(row["path"])
        image = Image.open(img_path).convert("RGB")

        target = row[self.target_key]
        if self.transform is not None:
            image = self.transform(image)
        if self.target_transform is not None:
            target = self.target_transform(target)

        if self.return_meta:
            meta = {
                "point_id": row.get("point_id"),
                "lat": row.get("lat"),
                "lon": row.get("lon"),
                "heading": row.get("heading"),
                "severity": row.get("severity"),
                "mode": row.get("mode"),
            }
            return image, target, meta
        return image, target

    # 편의 -------------------------------------------------------------------
    @property
    def targets(self) -> list:
        """torchvision 관례: 전체 타깃 리스트(층화 분할 등에 사용)."""
        return self.frame[self.target_key].tolist()

    @property
    def classes(self) -> list[str]:
        return ["control", "accident"]

    def class_weights(self):
        """클래스 불균형(§4.5-1) 대응용 역빈도 가중치 텐서."""
        import torch

        labels = self.frame["label"].to_numpy()
        counts = [max(1, int((labels == c).sum())) for c in (0, 1)]
        w = torch.tensor([sum(counts) / c for c in counts], dtype=torch.float32)
        return w / w.sum()


def image_folder(cfg: Config = DEFAULT_CONFIG, transform: Callable | None = None):
    """순수 torchvision.datasets.ImageFolder 로 streetview/ 디렉토리를 연다.

    메타데이터가 필요없고 표준 (image, class_index) 만 쓸 때 간편.
    """
    _require_torch()
    from torchvision import datasets

    root = cfg.images_dir
    if not root.exists():
        raise FileNotFoundError(f"이미지 디렉토리가 없습니다: {root}. 먼저 수집을 실행하세요.")
    return datasets.ImageFolder(str(root), transform=transform)


def default_transform(train: bool = True):
    """ZenSVI/ViT 백본(§4.4)에 맞춘 기본 전처리(ImageNet 정규화, 224)."""
    _require_torch()
    from torchvision import transforms

    norm = transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    if train:
        return transforms.Compose([
            transforms.Resize((256, 256)),
            transforms.RandomCrop(224),
            transforms.RandomHorizontalFlip(),
            transforms.ToTensor(),
            norm,
        ])
    return transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        norm,
    ])


# --------------------------------------------------------------------------- #
# 데이터 분할 (train/valid, k-fold)
#
# teacher(ViT) 학습용 분할. 두 가지를 반드시 지킨다(§4.5, 대화 결정):
#   1) 지점 단위 group 유지 — 한 지점(point_id)에서 여러 heading 으로 찍은 이미지들이
#      train 과 valid 에 나뉘면 같은 장소가 양쪽에 새서(leakage) 성능이 부풀려진다.
#   2) 라벨 stratify — 사고(1)/대조(0) 비율을 각 분할에 동일하게.
# sklearn StratifiedGroupKFold 가 이 둘을 한 번에 처리한다.
#
# 데이터가 적으므로(§4.5-1) 별도 test 분할은 두지 않는다. teacher 신뢰도 추정이
# 필요하면 kfold_indices() 로 교차검증한다. 분할 로직은 torch 불필요(sklearn만).
# --------------------------------------------------------------------------- #

def _frame_of(data):
    """dataset / DataFrame / manifest 경로 어느 것이 와도 manifest DataFrame 으로 정규화."""
    import pandas as pd

    if hasattr(data, "frame"):          # PMRoadviewDataset
        return data.frame
    if isinstance(data, pd.DataFrame):
        return data
    return pd.read_csv(data)            # 경로(str/Path)


def split_indices(data, valid_frac: float = 0.2, seed: int = 42,
                  label_col: str = "label", group_col: str = "point_id"):
    """train/valid 인덱스를 (train_idx, valid_idx) 로 반환.

    같은 `point_id` 는 한쪽에만(누수 방지), 라벨 비율 유지(stratify).
    단일 클래스면 stratify 불가 → 그룹 단위 무작위 분할로 폴백.
    """
    import numpy as np

    frame = _frame_of(data)
    y = frame[label_col].to_numpy()
    groups = frame[group_col].to_numpy()
    idx = np.arange(len(frame))

    if len(np.unique(y)) < 2:
        from sklearn.model_selection import GroupShuffleSplit
        splitter = GroupShuffleSplit(n_splits=1, test_size=valid_frac, random_state=seed)
        tr, va = next(splitter.split(idx, y, groups))
    else:
        from sklearn.model_selection import StratifiedGroupKFold
        n_splits = max(2, round(1.0 / valid_frac))
        sgkf = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)
        tr, va = next(sgkf.split(idx, y, groups))
    return tr.tolist(), va.tolist()


def kfold_indices(data, n_splits: int = 5, seed: int = 42,
                  label_col: str = "label", group_col: str = "point_id"):
    """StratifiedGroupKFold 로 [(train_idx, valid_idx), ...] (n_splits 개) 반환.

    적은 데이터에서 teacher 신뢰도를 추정할 때 고정 test 대신 사용(§4.5-1).
    """
    import numpy as np
    from sklearn.model_selection import StratifiedGroupKFold

    frame = _frame_of(data)
    y = frame[label_col].to_numpy()
    groups = frame[group_col].to_numpy()
    idx = np.arange(len(frame))
    sgkf = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)
    return [(tr.tolist(), va.tolist()) for tr, va in sgkf.split(idx, y, groups)]


def make_train_valid(
    root: str | Path | None = None,
    *,
    valid_frac: float = 0.2,
    seed: int = 42,
    cfg: Config = DEFAULT_CONFIG,
    train_transform: Callable | None = None,
    valid_transform: Callable | None = None,
    target_key: str = "label",
    return_meta: bool = False,
):
    """학습에 바로 쓸 (train_subset, valid_subset) 반환 (torch 필요).

    train/valid 는 서로 다른 transform 을 갖는다(train=증강, valid=결정적). 내부적으로
    같은 manifest 로 두 Dataset 을 만들고 [split_indices] 로 나눈 뒤 Subset 으로 감싼다.
    """
    _require_torch()
    from torch.utils.data import Subset

    tr_t = train_transform if train_transform is not None else default_transform(train=True)
    va_t = valid_transform if valid_transform is not None else default_transform(train=False)

    train_ds = PMRoadviewDataset(root, transform=tr_t, cfg=cfg, target_key=target_key, return_meta=return_meta)
    valid_ds = PMRoadviewDataset(root, transform=va_t, cfg=cfg, target_key=target_key, return_meta=return_meta)

    train_idx, valid_idx = split_indices(train_ds.frame, valid_frac=valid_frac, seed=seed)
    return Subset(train_ds, train_idx), Subset(valid_ds, valid_idx)
