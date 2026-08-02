"""pm_safeline CLI.

사용 예:
    # 네트워크 없이 파이프라인 검증(mock provider)
    PM_SV_PROVIDER=mock python -m pm_safeline collect --limit 50

    # 실제 수집(Google Street View Static, 키 필요)
    PM_SV_PROVIDER=google PM_SV_API_KEY=... python -m pm_safeline collect

    # manifest 통계
    python -m pm_safeline stats
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from .datasets.primitives.config import data_root, default_provider, manifest_path


def _apply_data_dir(args) -> Path | None:
    if args.data_dir:
        os.environ['PM_DATA_DIR'] = args.data_dir
    return data_root()


def cmd_collect(args) -> None:
    from .datasets.roadview import build_roadview_dataset

    root = _apply_data_dir(args)
    build_roadview_dataset(root, source=args.source, pm_only=not args.all_modes, limit=args.limit)


def cmd_download(args) -> None:
    """KoROAD 다발지역 오픈API 만 받아 data/raw/ 에 캐시(수집/이미지 없이)."""
    from .datasets.accidents import AccidentDataset
    from .datasets.primitives.config import raw_dir

    root = _apply_data_dir(args)
    gdf = AccidentDataset(root=root, source="koroad", download=True, kind=args.kind).to_geodataframe()
    print(f"[download] {len(gdf)}개 다발지역 -> {raw_dir(root)}")


def cmd_stats(args) -> None:
    import pandas as pd

    root = _apply_data_dir(args)
    mpath = manifest_path(root)
    if not mpath.exists():
        print(f"manifest 없음: {mpath}")
        return
    df = pd.read_csv(mpath)
    print(f"이미지 {len(df)}장, 지점 {df['point_id'].nunique()}개")
    print(df['class'].value_counts().to_string())
    if "severity" in df:
        print("\n[severity]")
        print(df[df.label == 1]['severity'].value_counts().to_string())


def cmd_check(args) -> None:
    """수집 없이 import/설정 sanity check."""
    root = _apply_data_dir(args)
    from .datasets.primitives import geo, negatives, streetview  # noqa: F401
    from .datasets.accidents import AccidentDataset  # noqa: F401
    from .datasets.roadview import build_roadview_dataset  # noqa: F401

    print("[check] 수집 모듈 import OK")
    print(f"[check] data_root={root}  provider={default_provider()}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="pm_safeline", description="PM 로드뷰 위험도 데이터셋 구축")
    p.add_argument("--data-dir", help="데이터 루트(기본 env PM_DATA_DIR 또는 ./data)")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("collect", help="전체 수집 파이프라인 실행")
    c.add_argument("--source", choices=["koroad", "taas"], default="koroad",
                   help="사고 소스: koroad(오픈API 자동, 기본) | taas(수동 CSV)")
    c.add_argument("--limit", type=int, default=None, help="처리 지점 수 상한(테스트용)")
    c.add_argument("--all-modes", action="store_true", help="PM/자전거 외 전체 사고 포함(taas 소스)")
    c.set_defaults(func=cmd_collect)

    d = sub.add_parser("download", help="KoROAD 다발지역 오픈API 만 받아 캐시")
    d.add_argument("--kind", default="motorcycle", help="다발지역 종류(motorcycle|bicycle 등)")
    d.set_defaults(func=cmd_download)

    s = sub.add_parser("stats", help="manifest 통계 출력")
    s.set_defaults(func=cmd_stats)

    k = sub.add_parser("check", help="import/설정 점검")
    k.set_defaults(func=cmd_check)
    return p


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
