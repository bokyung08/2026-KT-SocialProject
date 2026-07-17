# 배포 (자동 새로고침)

서버를 **현재 계정에서 그냥 실행해두면**, `main` 에 merge 될 때마다 알아서
**pull → 재빌드 → 재시작** 됩니다. 권한(root)·systemd·전용 사용자 전부 불필요합니다.

## 사용법

```bash
# 0) (최초 1회) JDK 21 · git 설치 + 클론 + .env 작성
sudo apt-get install -y git openjdk-21-jdk        # 예: Ubuntu
git clone -b main <REPO_URL> pm-safeline && cd pm-safeline
cp .env.default .env && nano .env                 # PM_OSM_FILE, KOROAD_API_KEY 등

# 1) 실행 (이게 전부)
bash deploy/run.sh
```

- 처음에 빌드 후 서버를 띄우고, 이후 60초마다 `main` 을 확인해 변경이 있으면 자동 새로고침합니다.
- 서버 설정(`PM_OSM_FILE` 등)은 프로젝트 루트 `.env` 에서 자동 로드됩니다.
- `http://localhost:8080` 에서 확인. 종료는 `Ctrl+C`.

### 로그아웃해도 계속 돌리기

터미널을 닫아도 유지하려면 `tmux`/`screen` 안에서 실행하거나 `nohup` 을 씁니다:

```bash
# tmux (권장) — 나중에 tmux attach 로 다시 붙을 수 있음
tmux new -s pm 'bash deploy/run.sh'

# 또는 nohup 백그라운드
nohup bash deploy/run.sh > run.log 2>&1 &
```

### 옵션

| 환경변수 | 기본 | 설명 |
|---|---|---|
| `PM_BRANCH` | `main` | 추적 브랜치 |
| `PM_POLL_SECONDS` | `60` | 변경 확인 주기(초) |

## 동작 / 주의

- `git reset --hard origin/main` 으로 맞추므로 **추적되지 않는 `.env`·`data/`(OSM·그래프캐시)는 보존**됩니다.
- 새 커밋이 없으면 아무것도 하지 않습니다. 서버가 죽어 있으면 다음 주기에 되살립니다.
- 새로고침 시 GraphHopper 그래프 캐시가 있으면 재임포트 없이 빠르게 뜹니다(OSM 파일이 바뀐 경우에만 캐시 삭제).
- 재시작 시 수 초 다운타임이 있습니다.
- 실행 스크립트 경로는 `build/install/safety/bin/safety` (`rootProject.name=safety`).

## (선택) systemd 서비스로 상시 실행

부팅 시 자동 시작·프로세스 관리가 필요하면 `deploy/systemd/` 유닛과
`bootstrap.sh`/`deploy.sh`/`teardown.sh` 를 쓸 수 있습니다(root 필요). 대부분의 경우
위 `run.sh` 로 충분합니다.

| 파일 | 역할 |
|---|---|
| `bootstrap.sh` | 최초 1회 유닛 등록 + 빌드 + 활성화 |
| `deploy.sh` | 타이머가 호출: main 변경 시 pull·빌드·재시작 |
| `teardown.sh` | 제거 (`--purge` 로 완전 삭제) |
| `systemd/*` | 앱 서비스 + 배포 타이머(2분) |

```bash
sudo bash deploy/bootstrap.sh     # 등록·시작
sudo bash deploy/teardown.sh      # 제거
```
