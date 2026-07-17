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

from ..utils.config import Config, DEFAULT_CONFIG

if TYPE_CHECKING:  # 타입 힌트용(런타임 임포트 아님)
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
        *,
        cfg: Config = DEFAULT_CONFIG,
        target_key: str = "label",
        return_meta: bool = False,
    ):
        _require_torch()
        import pandas as pd

        self.cfg = cfg
        self.root = Path(root) if root is not None else cfg.data_dir
        manifest_path = self.root / "manifest.csv"
        if not manifest_path.exists():
            raise FileNotFoundError(
                f"manifest 가 없습니다: {manifest_path}. 먼저 수집 파이프라인을 실행하세요 "
                "(`python -m pmdata collect`)."
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
