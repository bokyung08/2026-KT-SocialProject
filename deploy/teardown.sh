#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PM 세이프라인 배포 서버에서 제거 (멱등).
#
#   sudo bash deploy/teardown.sh            # 서비스·타이머·유닛만 제거(앱/데이터 보존)
#   sudo bash deploy/teardown.sh --purge    # 앱 디렉토리까지 완전 제거
#
# 환경변수로 재정의 가능: PM_APP_DIR
# ---------------------------------------------------------------------------
set -euo pipefail

APP_DIR="${PM_APP_DIR:-/opt/pm-safeline/app}"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

if [ "$(id -u)" -ne 0 ]; then
  echo "root 권한이 필요합니다:  sudo bash deploy/teardown.sh [--purge]" >&2
  exit 1
fi

echo "[teardown] 1/3 타이머·서비스 중지 및 비활성화"
systemctl disable --now pm-safeline-deploy.timer 2>/dev/null || true
systemctl stop    pm-safeline-deploy.service 2>/dev/null || true
systemctl disable --now pm-safeline.service 2>/dev/null || true

echo "[teardown] 2/3 유닛 파일 제거"
rm -f /etc/systemd/system/pm-safeline.service \
      /etc/systemd/system/pm-safeline-deploy.service \
      /etc/systemd/system/pm-safeline-deploy.timer
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

if [ "$PURGE" -eq 1 ]; then
  PARENT="$(dirname "$APP_DIR")"   # 예: /opt/pm-safeline
  echo "[teardown] 3/3 --purge: 앱 디렉토리($PARENT) 제거"
  rm -rf "$PARENT"
  echo "[teardown] 완전 제거 완료 ✅"
else
  echo "[teardown] 3/3 서비스 제거 완료 ✅ — 앱 디렉토리($APP_DIR)와 .env/data 는 보존됨."
  echo "           완전 삭제하려면:  sudo bash deploy/teardown.sh --purge"
fi
