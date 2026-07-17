#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PM 세이프라인 자동 배포 스크립트 (폴링 방식, root 로 실행)
#
# origin/<branch> 에 새 커밋이 있으면:
#   reset -> systemd 유닛 동기화 -> 빌드 -> 앱 재시작.
# systemd 타이머(pm-safeline-deploy.timer)가 주기적으로 이 스크립트를 실행한다.
# 유닛 파일도 매번 git 최신본으로 동기화하므로, 배포 설정 변경도 자동 반영된다.
#
# 환경변수로 재정의 가능:
#   PM_APP_DIR   앱(git 체크아웃) 디렉토리   (기본 /opt/pm-safeline/app)
#   PM_BRANCH    추적 브랜치                 (기본 main)
#   PM_SERVICE   앱 systemd 서비스 이름      (기본 pm-safeline.service)
# ---------------------------------------------------------------------------
set -euo pipefail

APP_DIR="${PM_APP_DIR:-/opt/pm-safeline/app}"
BRANCH="${PM_BRANCH:-main}"
SERVICE="${PM_SERVICE:-pm-safeline.service}"
UNIT_SRC="$APP_DIR/deploy/systemd"

git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true
cd "$APP_DIR"

# 1) 원격 최신 커밋 확인
git fetch --quiet origin "$BRANCH"
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/$BRANCH")"

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "[deploy] up-to-date ($(git rev-parse --short HEAD)) — 변경 없음"
  exit 0
fi

echo "[deploy] 새 커밋 감지: ${LOCAL:0:7} -> ${REMOTE:0:7} — 배포 시작"

# 2) origin/<branch> 에 정확히 맞춤 (추적되지 않는 .env / data/ 는 보존됨)
git reset --hard "origin/$BRANCH"

# 3) systemd 유닛을 git 최신본으로 동기화(유닛/타이머 변경도 자동 반영)
cp -f "$UNIT_SRC"/pm-safeline*.service "$UNIT_SRC"/pm-safeline*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable pm-safeline-deploy.timer >/dev/null 2>&1 || true

# 4) 빌드 (설치 배포판 생성). JDK 21 필요.
./gradlew --no-daemon clean installDist

# 5) 앱 재시작
systemctl restart "$SERVICE"

echo "[deploy] 완료: $SERVICE @ $(git rev-parse --short HEAD)"
