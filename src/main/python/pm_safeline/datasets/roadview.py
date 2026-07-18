"""torchvision 포맷 PyTorch Dataset.

두 가지 진입점을 제공한다.
    1) PMRoadviewDataset : manifest.csv 기반 커스텀 Dataset.
       - torchvision datasets 관례 준수: (sample, target) 반환, transform/target_transform 지원,
         root/transform 시그니처. 추가로 지리 메타데이터(lat/lon/heading/severity)를 함께 노출.
    2) image_folder()    : 순수 torchvision.datasets.ImageFolder 로 열기(디렉토리 레이아웃만 사용).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable, TYPE_CHECKING

import pandas as pd
import torch
from torch.utils.data import Dataset

from .primitives.config import (
    NEGATIVE_RATIO,
    SAMPLE_INTERVAL_M,
    SEED,
    data_root,
    ensure_dirs,
    images_dir,
    manifest_path,
    points_path,
)
from .primitives.streetview import StreetViewProvider, get_provider

if TYPE_CHECKING:  # 타입 힌트용(런타임 임포트 아님)
    import geopandas as gpd


# --------------------------------------------------------------------------- #
# 수집 오케스트레이터: 라벨 지점 -> 이미지 다운로드 + torchvision ImageFolder 레이아웃 + manifest.
#
# 디스크 레이아웃(torchvision.datasets.ImageFolder 호환):
#     <data>/streetview/accident/<point_id>[_h###].jpg
#     <data>/streetview/control/<point_id>[_h###].jpg
#     <data>/manifest.csv   # point_id,label,class,lat,lon,heading,severity,mode,path
#
# 캐시: 이미 파일이 존재하면 재다운로드하지 않음(중단 후 재개 안전).
# --------------------------------------------------------------------------- #
CLASS_NAMES = {1: "accident", 0: "control"}


def _headings_for(row, headings: tuple[int, ...] | None) -> list[float]:
    """한 지점에서 촬영할 방위각 목록. 기본은 **4방향**(도로 진행방향 기준 전/우/후/좌).

    ZenSVI 처럼 한 지점의 파노라마를 방향별 perspective 이미지로 분해해 도로 구조를
    사방으로 포착한다(자전거도로 단절·차도 합류·측면 위험 등은 한 방향으로 안 보임).
    headings 로 방향 집합을 재정의할 수 있다.
    """
    if headings:
        return [float(h) for h in headings]
    base = row.get("heading")
    base = 0.0 if (base is None or pd.isna(base)) else float(base)
    return [(base + d) % 360.0 for d in (0.0, 90.0, 180.0, 270.0)]


def _is_real_image(data: bytes, min_bytes: int = 8000, min_detail: float = 3.0) -> bool:
    """실제 로드뷰 사진인지 판별(단색 mock·회색 placeholder·커버리지 부족 거부).

    실사진은 인접 픽셀 변화(디테일)가 크다. 단색은 JPEG 아티팩트로 표준편차는 있어도
    인접 픽셀 차이는 0 에 가깝다 → 디테일로 구분. 크기 하한도 함께 사용.
    """
    if not data or len(data) < min_bytes:
        return False
    try:
        import io
        import numpy as np
        from PIL import Image

        arr = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((64, 64)), dtype="int16")
        detail = float(np.abs(np.diff(arr, axis=0)).mean() + np.abs(np.diff(arr, axis=1)).mean()) / 2.0
        return detail >= min_detail
    except Exception:
        return False


def collect_images(
    labeled_points: "gpd.GeoDataFrame",
    *,
    root: str | Path | None = None,
    provider: StreetViewProvider | None = None,
    headings: tuple[int, ...] | None = None,
    limit: int | None = None,
) -> pd.DataFrame:
    """labeled_points(build_labeled_points 출력) 를 순회하며 이미지 수집 + manifest 작성.

    반환: manifest DataFrame. 실패/커버리지 없음 지점은 manifest 에서 제외.
    """
    ensure_dirs(root)
    img_dir = images_dir(root)
    for cls in CLASS_NAMES.values():
        (img_dir / cls).mkdir(parents=True, exist_ok=True)

    provider = provider or get_provider()
    # mock 은 테스트용(단색) 이라 유효성 검사 우회. 실제 provider 는 placeholder/단색을 거부.
    validate = getattr(provider, "name", "") != "mock"

    records: list[dict] = []
    rows = labeled_points.iloc[:limit] if limit else labeled_points
    total = len(rows)
    for i, (_, row) in enumerate(rows.iterrows(), 1):
        label = int(row["label"])
        cls = CLASS_NAMES[label]
        for heading in _headings_for(row, headings):
            pid = str(row["point_id"])
            fname = f"{pid}_h{int(round(heading)):03d}.jpg"
            out_path = img_dir / cls / fname

            if out_path.exists():
                img = out_path.read_bytes()
            else:
                try:
                    img = provider.fetch(float(row["lat"]), float(row["lon"]), heading)
                except Exception as e:  # noqa: BLE001
                    print(f"[collect] {pid} h{heading} 실패: {e}")
                    continue
                if img is None:
                    continue  # 커버리지 없음

            # 실사진 검증: 단색(mock)·회색 placeholder·커버리지 부족 이미지는 데이터셋에서 제외
            if validate and not _is_real_image(img):
                print(f"[collect] {pid} h{int(round(heading)):03d} 실사진 아님 → 제외")
                if out_path.exists():
                    out_path.unlink()
                continue
            if not out_path.exists():
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
                    "path": str(out_path.relative_to(data_root(root))),
                }
            )
        if i % 100 == 0 or i == total:
            print(f"[collect] {i}/{total} 지점 처리")

    manifest = pd.DataFrame.from_records(records)
    mpath = manifest_path(root)
    if not manifest.empty:
        manifest.to_csv(mpath, index=False, encoding="utf-8-sig")
        print(f"[collect] manifest 저장: {mpath} ({len(manifest)} 이미지)")
    else:
        print("[collect] 수집된 이미지가 없습니다(커버리지/키/약관 확인).")
    return manifest


def build_roadview_dataset(
    root: str | Path | None = None,
    *,
    source: str = "koroad",
    pm_only: bool = True,
    limit: int | None = None,
    regions: tuple[str, ...] | None = None,
    provider: str | None = None,
    api_key: str | None = None,
    sample_interval_m: float = SAMPLE_INTERVAL_M,
    negative_ratio: float = NEGATIVE_RATIO,
    seed: int = SEED,
    headings: tuple[int, ...] | None = None,
) -> pd.DataFrame:
    """전체 수집 파이프라인 원샷 실행.

    사고 로드 -> OSM edge -> 지점 샘플링 -> negative 매칭 -> 라벨결합 -> 이미지 수집.
    각 단계 산출물은 data/ 에 캐시된다.

    source:
        "koroad" (기본) — KoROAD 이륜차 교통사고 다발지역 오픈API 자동 다운로드.
        "taas"          — data/raw/ 의 수동 다운로드 CSV/XLSX 사용.
    """
    from .primitives import geo, negatives
    from .accidents import AccidentDataset

    print(f"[pipeline] 1/5 사고 로드 (source={source})")
    accidents = AccidentDataset(
        root=root, source=source, download=True, pm_only=pm_only, regions=regions
    ).to_geodataframe()
    print(f"[pipeline]   {len(accidents)}건 · severity={accidents['severity'].value_counts().to_dict()}")

    # OSM·negative 는 **지역별로** 처리한다. 여러 도시를 하나의 bbox 로 묶으면 도시 사이
    # 빈 공간까지 포함한 거대 OSM 다운로드가 되므로, 지역마다 그 지역 사고 범위에서만 뽑는다.
    import geopandas as gpd

    print("[pipeline] 2~4/5 지역별 OSM·지점·negative")
    groups = (list(accidents.groupby("region")) if "region" in accidents.columns
              else [("all", accidents)])
    parts = []
    for rname, acc_r in groups:
        if len(acc_r) == 0:
            continue
        minx, miny, maxx, maxy = acc_r.total_bounds
        m = 0.01  # 약 1km 여유
        bbox = (minx - m, miny - m, maxx + m, maxy + m)
        print(f"[pipeline]   [{rname}] 사고 {len(acc_r)}건 · 영역 {tuple(round(v,3) for v in bbox)}")
        edges = geo.load_drive_edges(bbox)
        acc_snapped = geo.snap_accidents_to_edges(acc_r, edges)
        candidates = geo.sample_points_along_edges(edges, sample_interval_m=sample_interval_m)
        negs = negatives.sample_negatives(acc_snapped, candidates, negative_ratio=negative_ratio, seed=seed)
        labeled_r = negatives.build_labeled_points(acc_snapped, negs)
        labeled_r["point_id"] = rname + "_" + labeled_r["point_id"].astype(str)  # 지역 prefix 로 고유화
        parts.append(labeled_r)

    labeled = gpd.GeoDataFrame(pd.concat(parts, ignore_index=True), geometry="geometry", crs="EPSG:4326")
    ensure_dirs(root)
    ppath = points_path(root)
    labeled.to_file(ppath, driver="GPKG")
    print(f"[pipeline] 라벨 지점 저장: {ppath} "
          f"(pos={int((labeled.label==1).sum())}, neg={int((labeled.label==0).sum())}, 총 {len(labeled)})")

    print("[pipeline] 5/5 이미지 수집")
    sv_provider = get_provider(provider, api_key=api_key)
    return collect_images(labeled, root=root, provider=sv_provider, headings=headings, limit=limit)


class PMRoadviewDataset(Dataset):
    """manifest.csv 로 정의된 로드뷰 위험도 데이터셋.

    각 항목: (image, target)
        image  : transform 적용 결과(기본 미적용 시 PIL.Image)
        target : 기본은 int label(1=accident, 0=control).
                 target_transform 또는 target_key 로 커스터마이즈 가능.

    인자:
        root            : data_root (manifest.csv, streetview/ 를 포함). None 이면 기본 data_root().
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
        target_key: str = "label",
        return_meta: bool = False,
        source: str = "koroad",
        pm_only: bool = True,
        limit: int | None = None,
    ):
        self.root = data_root(root)
        mpath = self.root / "manifest.csv"
        if download:
            build_roadview_dataset(root, source=source, pm_only=pm_only, limit=limit)
        if not mpath.exists():
            raise FileNotFoundError(
                f"manifest 가 없습니다: {mpath}. 먼저 수집 파이프라인을 실행하세요 "
                "(`python -m pm_safeline collect`) 또는 download=True 를 사용하세요."
            )
        self.frame = pd.read_csv(mpath)
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
        labels = self.frame["label"].to_numpy()
        counts = [max(1, int((labels == c).sum())) for c in (0, 1)]
        w = torch.tensor([sum(counts) / c for c in counts], dtype=torch.float32)
        return w / w.sum()


def image_folder(root: str | Path | None = None, transform: Callable | None = None):
    """순수 torchvision.datasets.ImageFolder 로 streetview/ 디렉토리를 연다.

    메타데이터가 필요없고 표준 (image, class_index) 만 쓸 때 간편.
    """
    from torchvision import datasets

    img_dir = images_dir(root)
    if not img_dir.exists():
        raise FileNotFoundError(f"이미지 디렉토리가 없습니다: {img_dir}. 먼저 수집을 실행하세요.")
    return datasets.ImageFolder(str(img_dir), transform=transform)


def default_transform(train: bool = True):
    """ZenSVI/ViT 백본(§4.4)에 맞춘 기본 전처리(ImageNet 정규화, 224)."""
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
# 필요하면 kfold_indices() 로 교차검증한다.
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
    train_transform: Callable | None = None,
    valid_transform: Callable | None = None,
    target_key: str = "label",
    return_meta: bool = False,
):
    """학습에 바로 쓸 (train_subset, valid_subset) 반환.

    train/valid 는 서로 다른 transform 을 갖는다(train=증강, valid=결정적). 내부적으로
    같은 manifest 로 두 Dataset 을 만들고 [split_indices] 로 나눈 뒤 Subset 으로 감싼다.
    """
    from torch.utils.data import Subset

    tr_t = train_transform if train_transform is not None else default_transform(train=True)
    va_t = valid_transform if valid_transform is not None else default_transform(train=False)

    train_ds = PMRoadviewDataset(root, transform=tr_t, target_key=target_key, return_meta=return_meta)
    valid_ds = PMRoadviewDataset(root, transform=va_t, target_key=target_key, return_meta=return_meta)

    train_idx, valid_idx = split_indices(train_ds.frame, valid_frac=valid_frac, seed=seed)
    return Subset(train_ds, train_idx), Subset(valid_ds, valid_idx)
