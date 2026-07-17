"""pmdata CLI.

사용 예:
    # 네트워크 없이 파이프라인 검증(mock provider)
    PM_SV_PROVIDER=mock python -m pmdata collect --limit 50

    # 실제 수집(Google Street View Static, 키 필요)
    PM_SV_PROVIDER=google PM_SV_API_KEY=... python -m pmdata collect

    # manifest 통계
    python -m pmdata stats
"""

from __future__ import annotations

import argparse
import os
from .utils.config import Config


def _cfg_from_args(args) -> Config:
    if args.data_dir:
        os.environ["PM_DATA_DIR"] = args.data_dir
    # env 를 반영해 새 Config 생성
    return Config()


def cmd_collect(args) -> None:
    from .datasets import collect

    cfg = _cfg_from_args(args)
    collect.run_pipeline(cfg, source=args.source, pm_only=not args.all_modes, limit=args.limit)


def cmd_download(args) -> None:
    """KoROAD 다발지역 오픈API 만 받아 data/raw/ 에 캐시(수집/이미지 없이)."""
    from .utils import koroad

    cfg = _cfg_from_args(args)
    gdf = koroad.download_to_raw(cfg, kind=args.kind)
    print(f"[download] {len(gdf)}개 다발지역 -> {cfg.raw_dir}")


def cmd_stats(args) -> None:
    import pandas as pd

    cfg = _cfg_from_args(args)
    if not cfg.manifest_path.exists():
        print(f"manifest 없음: {cfg.manifest_path}")
        return
    df = pd.read_csv(cfg.manifest_path)
    print(f"이미지 {len(df)}장, 지점 {df['point_id'].nunique()}개")
    print(df["class"].value_counts().to_string())
    if "severity" in df:
        print("\n[severity]")
        print(df[df.label == 1]["severity"].value_counts().to_string())


def cmd_check(args) -> None:
    """수집 없이 import/설정 sanity check (torch 불필요)."""
    cfg = _cfg_from_args(args)
    from .utils import geo, negatives, streetview, taas  # noqa: F401
    from .datasets import collect  # noqa: F401

    print("[check] 수집 모듈 import OK (torch 불필요)")
    print(f"[check] bbox={cfg.bbox}  data_dir={cfg.data_dir}  provider={cfg.streetview.provider}")
    try:
        from .datasets import dataset  # noqa: F401
        import importlib.util

        has_torch = importlib.util.find_spec("torch") is not None
        print(f"[check] dataset 모듈 import OK / torch 설치됨={has_torch}")
    except Exception as e:  # noqa: BLE001
        print(f"[check] dataset 모듈 경고: {e}")


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

    k = sub.add_parser("check", help="import/설정 점검(torch 불필요)")
    k.set_defaults(func=cmd_check)
    return p


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
