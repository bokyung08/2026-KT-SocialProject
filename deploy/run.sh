#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 현재 계정에서 서버를 실행하고, main 변경을 감지하면 자동으로 새로고침한다.
# (권한/유닛/전용 사용자 불필요 — 그냥 실행해두면 됨)
#
#   bash deploy/run.sh
#
# 로그아웃해도 계속 돌리려면 tmux/screen 안에서 실행하거나:
#   nohup bash deploy/run.sh > run.log 2>&1 &
#
# 환경변수:
#   PM_BRANCH        추적 브랜치        (기본 main)
#   PM_POLL_SECONDS  변경 확인 주기(초) (기본 60)
# 서버 자체 설정(PM_OSM_FILE 등)은 프로젝트 루트 .env 에서 자동 로드된다.
# ---------------------------------------------------------------------------
set -euo pipefail

BRANCH="${PM_BRANCH:-main}"
INTERVAL="${PM_POLL_SECONDS:-60}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$APP_DIR/build/install/safety/bin/safety"   # rootProject.name=safety
cd "$APP_DIR"

SERVER_PID=""

build()  { echo "[run] 빌드 중..."; ./gradlew --no-daemon -q installDist; }

start_server() {
  "$LAUNCHER" &
  SERVER_PID=$!
  echo "[run] 서버 시작 (pid $SERVER_PID) -> http://localhost:8080"
}

stop_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[run] 서버 중지 (pid $SERVER_PID)"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
}

trap 'stop_server; exit 0' INT TERM

build
start_server

echo "[run] '$BRANCH' 변경 감시 중 (${INTERVAL}s 간격). 종료: Ctrl+C"
while true; do
  sleep "$INTERVAL"

  # 서버가 죽었으면 되살림
  if [ -n "$SERVER_PID" ] && ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[run] 서버가 종료되어 있음 -> 재시작"; start_server
  fi

  git fetch --quiet origin "$BRANCH" || { echo "[run] git fetch 실패, 다음 주기 재시도"; continue; }
  LOCAL="$(git rev-parse HEAD)"
  REMOTE="$(git rev-parse "origin/$BRANCH")"
  [ "$LOCAL" = "$REMOTE" ] && continue

  echo "[run] 새 커밋 감지 ${LOCAL:0:7} -> ${REMOTE:0:7} : 새로고침"
  git reset --hard "origin/$BRANCH"
  stop_server
  build
  start_server
done
