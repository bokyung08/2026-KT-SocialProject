"""teacher(PMRiskViT) 학습 루프 (PROJECT.md §4.4~§4.5).

이 모듈은 torch 를 모듈 최상단에서 임포트한다(모델링 파일과 동일 관례).

제공 기능:
    TrainConfig       : 학습 하이퍼파라미터.
    train_teacher()   : BCEWithLogitsLoss(+pos_weight) + AdamW + early stopping(valid AUC).
    evaluate()        : 데이터셋에 대한 loss/AUC/AP 산출.
    cross_validate()  : StratifiedGroupKFold(kfold_indices) 기반 teacher 신뢰도 추정(§4.5-1).
    calibrate()       : temperature scaling(§4.5 과신 보정).
    save_checkpoint() / load_checkpoint() : 모델 가중치 저장/복원.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset
from sklearn.metrics import average_precision_score, roc_auc_score


@dataclass
class TrainConfig:
    """teacher 학습 하이퍼파라미터.

    device 는 기본값으로 cuda 가용 시 자동 선택한다.
    patience: 이 횟수만큼 연속으로 valid AUC 개선이 없으면 조기 종료.
    amp     : True 면 torch.autocast + GradScaler 로 혼합정밀 학습(GPU 전용, 데이터 희소해
              배치가 작으므로 기본은 False 로 둬도 무방).
    """

    epochs: int = 20
    lr: float = 1e-4
    weight_decay: float = 1e-2
    batch_size: int = 16
    device: str = field(default_factory=lambda: "cuda" if torch.cuda.is_available() else "cpu")
    num_workers: int = 0
    patience: int = 5
    amp: bool = False


def _make_loader(ds: Dataset, cfg: TrainConfig, *, shuffle: bool) -> DataLoader:
    return DataLoader(
        ds,
        batch_size=cfg.batch_size,
        shuffle=shuffle,
        num_workers=cfg.num_workers,
        pin_memory=(cfg.device == "cuda"),
    )


def _unpack_batch(batch) -> tuple['torch.Tensor', 'torch.Tensor']:
    """(image, target) 또는 (image, target, meta) 배치를 (x, y) 로 정규화."""
    x, y = batch[0], batch[1]
    return x, y


@torch.no_grad()
def _collect_logits_targets(model: nn.Module, ds: Dataset, cfg: TrainConfig):
    model.eval()
    loader = _make_loader(ds, cfg, shuffle=False)
    all_logits, all_targets = [], []
    for batch in loader:
        x, y = _unpack_batch(batch)
        x = x.to(cfg.device)
        logits = model(x).squeeze(-1)  # [B, 1] -> [B]
        all_logits.append(logits.detach().cpu())
        all_targets.append(y.detach().float().cpu())
    return torch.cat(all_logits), torch.cat(all_targets)


def evaluate(model: nn.Module, ds: Dataset, cfg: TrainConfig, *, pos_weight=None) -> dict:
    """ds 전체에 대한 loss/ROC-AUC/AP(average precision) 산출."""
    model = model.to(cfg.device)
    logits, targets = _collect_logits_targets(model, ds, cfg)

    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_weight)
    loss = loss_fn(logits, targets).item()

    targets_np = targets.numpy()
    probs_np = torch.sigmoid(logits).numpy()
    if len(set(targets_np.tolist())) < 2:
        # 단일 클래스 배치/데이터셋에서는 AUC 정의 불가 -> NaN 으로 표시
        auc = float("nan")
        ap = float("nan")
    else:
        auc = float(roc_auc_score(targets_np, probs_np))
        ap = float(average_precision_score(targets_np, probs_np))

    return {'loss': loss, 'auc': auc, 'ap': ap}


def train_teacher(
    model: nn.Module,
    train_ds: Dataset,
    valid_ds: Dataset,
    *,
    cfg: TrainConfig,
    pos_weight: "torch.Tensor | float | None" = None,
) -> dict:
    """teacher(ViT) 학습 루프.

    class 불균형(§4.5-1) 은 BCEWithLogitsLoss(pos_weight=...) 로 보정한다. optimizer 는
    model.trainable_parameters() 만 사용(freeze_backbone=True 면 헤드만 학습).
    valid ROC-AUC 기준 early stopping, 최고 성능 시점의 state_dict 를 best_state 로 반환.

    반환: {"history": {...}, "best_state": state_dict, "best_epoch": int, "best_auc": float}
    """
    model = model.to(cfg.device)
    train_loader = _make_loader(train_ds, cfg, shuffle=True)

    if pos_weight is not None and not isinstance(pos_weight, torch.Tensor):
        pos_weight = torch.tensor(float(pos_weight))
    pos_weight_dev = pos_weight.to(cfg.device) if pos_weight is not None else None
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_weight_dev)

    optimizer = torch.optim.AdamW(
        model.trainable_parameters(), lr=cfg.lr, weight_decay=cfg.weight_decay
    )
    scaler = torch.amp.GradScaler(enabled=(cfg.amp and cfg.device == "cuda"))

    history = {'train_loss': [], 'valid_loss': [], 'valid_auc': [], 'valid_ap': []}
    best_auc = float("-inf")
    best_state = copy.deepcopy(model.state_dict())
    best_epoch = -1
    epochs_since_improve = 0

    for epoch in range(cfg.epochs):
        model.train()
        running_loss = 0.0
        n_samples = 0
        for batch in train_loader:
            x, y = _unpack_batch(batch)
            x = x.to(cfg.device)
            y = y.to(cfg.device).float()

            optimizer.zero_grad(set_to_none=True)
            with torch.autocast(device_type=cfg.device, enabled=(cfg.amp and cfg.device == "cuda")):
                logits = model(x).squeeze(-1)
                loss = loss_fn(logits, y)

            if scaler.is_enabled():
                scaler.scale(loss).backward()
                scaler.step(optimizer)
                scaler.update()
            else:
                loss.backward()
                optimizer.step()

            running_loss += loss.item() * x.size(0)
            n_samples += x.size(0)

        train_loss = running_loss / max(1, n_samples)
        valid_metrics = evaluate(model, valid_ds, cfg, pos_weight=pos_weight_dev)

        history['train_loss'].append(train_loss)
        history['valid_loss'].append(valid_metrics['loss'])
        history['valid_auc'].append(valid_metrics['auc'])
        history['valid_ap'].append(valid_metrics['ap'])

        print(
            f"[train_teacher] epoch {epoch + 1}/{cfg.epochs} "
            f"train_loss={train_loss:.4f} valid_loss={valid_metrics['loss']:.4f} "
            f"valid_auc={valid_metrics['auc']:.4f}"
        )

        cur_auc = valid_metrics['auc']
        if cur_auc == cur_auc and cur_auc > best_auc:  # NaN 이 아니고 개선됨
            best_auc = cur_auc
            best_state = copy.deepcopy(model.state_dict())
            best_epoch = epoch
            epochs_since_improve = 0
        else:
            epochs_since_improve += 1
            if epochs_since_improve >= cfg.patience:
                print(f"[train_teacher] early stopping (patience={cfg.patience}) @ epoch {epoch + 1}")
                break

    return {
        'history': history,
        'best_state': best_state,
        'best_epoch': best_epoch,
        'best_auc': best_auc,
    }


def cross_validate(
    build_model_fn: Callable[[], nn.Module],
    dataset,
    *,
    n_splits: int = 5,
    cfg: TrainConfig,
    pos_weight: "torch.Tensor | float | None" = None,
) -> dict:
    """StratifiedGroupKFold(kfold_indices) 기반 k-fold 교차검증(§4.5-1: 데이터 희소 -> 고정 test 대신).

    build_model_fn: 매 fold 마다 새 모델을 만드는 콜백(가중치 누수 방지를 위해 fold마다 새로 생성).
    dataset       : PMRoadviewDataset(또는 .frame 속성을 가진 객체). transform 은 이미 적용돼 있어야 함.

    반환: {"fold_aucs": [...], "mean_auc": float, "std_auc": float}
    """
    from ..datasets.roadview import kfold_indices
    from torch.utils.data import Subset

    folds = kfold_indices(dataset, n_splits=n_splits, seed=42)
    fold_aucs = []
    for i, (train_idx, valid_idx) in enumerate(folds):
        print(f"[cross_validate] fold {i + 1}/{n_splits}")
        train_sub = Subset(dataset, train_idx)
        valid_sub = Subset(dataset, valid_idx)

        model = build_model_fn()
        result = train_teacher(model, train_sub, valid_sub, cfg=cfg, pos_weight=pos_weight)
        fold_aucs.append(result['best_auc'])

    import statistics

    finite = [a for a in fold_aucs if a == a]  # NaN 제외
    mean_auc = statistics.fmean(finite) if finite else float("nan")
    std_auc = statistics.pstdev(finite) if len(finite) > 1 else 0.0

    return {'fold_aucs': fold_aucs, 'mean_auc': mean_auc, 'std_auc': std_auc}


class _TemperatureCalibrator:
    """1-parameter temperature scaling 캘리브레이터(§4.5 과신 보정).

    사용법: calibrator(logits) -> 보정된 확률. 또는 calibrator.predict_proba(model, x)."""

    def __init__(self, temperature: float):
        self.temperature = float(temperature)

    def __call__(self, logits: "torch.Tensor") -> "torch.Tensor":
        return torch.sigmoid(logits / self.temperature)

    def predict_proba(self, model: nn.Module, pixel_values: "torch.Tensor") -> "torch.Tensor":
        model.eval()
        with torch.no_grad():
            logits = model(pixel_values).squeeze(-1)
        return self(logits)


def calibrate(model: nn.Module, valid_ds: Dataset, cfg: TrainConfig, method: str = "temperature"):
    """valid_ds 의 로짓으로 온도 T 를 학습해 과신(overconfidence)을 보정(§4.5).

    LBFGS 로 NLL(BCE) 을 최소화하는 단일 스칼라 T>0 를 찾는다. 반환은 logits -> 보정확률
    을 계산하는 호출 가능 캘리브레이터(_TemperatureCalibrator).
    """
    if method != "temperature":
        raise ValueError(f"지원하지 않는 calibration method: {method}")

    model = model.to(cfg.device)
    logits, targets = _collect_logits_targets(model, valid_ds, cfg)
    logits = logits.to(cfg.device)
    targets = targets.to(cfg.device)

    log_temperature = torch.zeros(1, device=cfg.device, requires_grad=True)
    optimizer = torch.optim.LBFGS([log_temperature], lr=0.01, max_iter=50)
    loss_fn = nn.BCEWithLogitsLoss()

    def _closure():
        optimizer.zero_grad()
        temperature = torch.exp(log_temperature)
        loss = loss_fn(logits / temperature, targets)
        loss.backward()
        return loss

    optimizer.step(_closure)
    temperature = torch.exp(log_temperature).item()
    print(f"[calibrate] temperature={temperature:.4f}")
    return _TemperatureCalibrator(temperature)


def save_checkpoint(model: nn.Module, path: "str | Path", extra: dict | None = None) -> None:
    """모델 state_dict(+옵션 부가정보) 저장."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload: dict[str, Any] = {'state_dict': model.state_dict()}
    if extra:
        payload.update(extra)
    torch.save(payload, path)
    print(f"[save_checkpoint] 저장: {path}")


def load_checkpoint(model: nn.Module, path: "str | Path", *, strict: bool = True) -> nn.Module:
    """save_checkpoint() 로 저장한 체크포인트를 model 에 로드."""
    payload = torch.load(Path(path), map_location="cpu")
    state_dict = payload.get("state_dict", payload) if isinstance(payload, dict) else payload
    model.load_state_dict(state_dict, strict=strict)
    return model
