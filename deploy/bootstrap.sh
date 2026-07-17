#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PM 세이프라인 배포 서버 최초 1회 부트스트랩 (멱등 — 재실행 안전).
#
#   sudo bash deploy/bootstrap.sh
#
# 하는 일:
#   1) systemd 유닛(앱 서비스 + 자동배포 타이머) 등록
#   2) 최초 빌드(installDist)
#   3) 서비스·타이머 활성화(부팅 시 자동 시작 포함)
#
# 이후에는 main 에 merge 될 때마다 타이머가 자동으로 pull·빌드·재시작하며,
# 유닛 파일이 바뀌어도 deploy.sh 가 자동 동기화한다. systemd 특성상 "최초 등록"만
# 이렇게 사람이 한 번 실행하면 된다.
#
# 환경변수로 재정의 가능: PM_APP_DIR
# ---------------------------------------------------------------------------
set -euo pipefail

APP_DIR="${PM_APP_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
UNIT_SRC="$APP_DIR/deploy/systemd"

if [ "$(id -u)" -ne 0 ]; then
  echo "root 권한이 필요합니다:  sudo bash deploy/bootstrap.sh" >&2
  exit 1
fi

git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true
cd "$APP_DIR"

echo "[bootstrap] 1/3 systemd 유닛 등록 ($UNIT_SRC -> /etc/systemd/system)"
cp -f "$UNIT_SRC"/pm-safeline*.service "$UNIT_SRC"/pm-safeline*.timer /etc/systemd/system/
systemctl daemon-reload

echo "[bootstrap] 2/3 최초 빌드 (installDist)"
./gradlew --no-daemon clean installDist

echo "[bootstrap] 3/3 서비스·타이머 활성화"
systemctl enable --now pm-safeline.service
systemctl enable --now pm-safeline-deploy.timer

echo "[bootstrap] 완료 ✅"
systemctl --no-pager status pm-safeline.service | head -4 || true
echo "   자동배포 타이머:"
systemctl --no-pager list-timers pm-safeline-deploy.timer || true
