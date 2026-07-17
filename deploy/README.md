# 배포 (Linux + systemd, 폴링 자동배포)

`main` 브랜치에 merge 되면 배포 서버가 **자동으로 pull → 빌드 → 재시작**합니다.

## 구성 요소

| 파일 | 역할 |
|---|---|
| `bootstrap.sh` | **최초 1회** 유닛 등록 + 빌드 + 활성화 (멱등) |
| `teardown.sh` | 배포 서버에서 제거 (`--purge` 로 완전 삭제) |
| `systemd/pm-safeline.service` | 앱을 상시 실행하는 서비스 (기본 root, 단순) |
| `deploy.sh` | `origin/main` 확인 → 변경 시 reset·유닛동기화·빌드·재시작 (root) |
| `systemd/pm-safeline-deploy.service` | `deploy.sh` 를 실행하는 oneshot (root) |
| `systemd/pm-safeline-deploy.timer` | 2분마다 위 oneshot 실행(폴링) |

동작: **timer**(2분) → **deploy.service** → `deploy.sh`(새 커밋 있을 때만 빌드·`systemctl restart`) → **pm-safeline.service** 재시작.

### ❓ 처음 시작 때 systemd 등록도 자동인가?

**아니요 — 최초 등록은 1회 수동 트리거가 필요합니다.** systemd 는 아직 등록되지 않은 유닛을 스스로 실행할 수 없으므로(닭-달걀 문제), 어떤 자동배포 방식이든 "맨 처음 한 번"은 사람이 실행해야 합니다. 그래서 그 1회를 **명령 한 줄**(`bootstrap.sh`)로 만들었습니다.

**한 번 부트스트랩한 뒤에는 완전 자동입니다**: 코드 변경은 물론, `deploy/systemd/*` 유닛 파일이 바뀌어도 `deploy.sh` 가 매 배포 때 `/etc/systemd/system` 으로 동기화하고 `daemon-reload` 하므로 재부트스트랩이 필요 없습니다. 서버 재부팅 시에도 `enable` 되어 있어 자동 시작됩니다.

## 최초 설정 (배포 서버에서 1회)

```bash
# 0) JDK 21 · git 설치 (예: Ubuntu)
sudo apt-get update && sudo apt-get install -y git openjdk-21-jdk

# 1) 디렉토리 + 클론
sudo git clone -b main <REPO_URL> /opt/pm-safeline/app
cd /opt/pm-safeline/app

# 2) 비밀/설정: .env 작성 (git 에 없음). 최소 PM_OSM_FILE 지정.
sudo cp .env.default .env
sudo nano .env                # KOROAD_API_KEY, PM_OSM_FILE 등 채우기
#   예) PM_OSM_FILE=/opt/pm-safeline/app/data/osm/daejeon.osm
#   OSM 파일은 미리 서버에 올려두거나 Overpass 로 받아 data/osm/ 에 둔다.

# 3) 부트스트랩 한 줄 — 유닛 등록 + 빌드 + 활성화 (이후 자동)
sudo bash deploy/bootstrap.sh
```

기본은 **root 로 단순하게** 실행합니다(전용 사용자·sudoers 불필요). 비특권 사용자로
하드닝하려면 `pm-safeline.service` 의 `User=` 주석을 해제하고 그 사용자에게
디렉토리 읽기 + `data/` 쓰기 권한을 주면 됩니다.

> ⚠️ 유닛 파일과 스크립트의 `JAVA_HOME`, 경로(`/opt/pm-safeline/app`)를 서버 환경에 맞게
> 확인/수정하세요. 경로가 다르면 `PM_APP_DIR` 환경변수로 넘길 수 있습니다.
> `installDist` 실행 스크립트 이름은 `rootProject.name`(=`safety`)을 따르므로 `build/install/safety/bin/safety` 입니다.

## 확인 / 운영

```bash
# 앱 상태·로그
sudo systemctl status pm-safeline.service
sudo journalctl -u pm-safeline.service -f

# 자동배포 타이머·최근 배포 로그
systemctl list-timers pm-safeline-deploy.timer
sudo journalctl -u pm-safeline-deploy.service -f

# 지금 즉시 한 번 배포 시도(수동)
sudo systemctl start pm-safeline-deploy.service

# health 확인
curl -s localhost:8080/health
```

## 동작 원리 / 주의

- `deploy.sh` 는 `git reset --hard origin/main` 으로 정확히 맞춥니다. **추적되지 않는 `.env`·`data/` 는 보존**됩니다(사고 데이터·OSM·그래프캐시 유지).
- 새 커밋이 없으면 빌드/재시작을 하지 않으므로(멱등) 폴링 비용이 낮습니다.
- 재시작 시 GraphHopper 그래프 캐시(`PM_GRAPH_CACHE`)가 있으면 재임포트 없이 빠르게 뜹니다. OSM 파일이 바뀐 경우에만 캐시를 지우세요.
- 폴링 주기는 `pm-safeline-deploy.timer` 의 `OnUnitActiveSec` 로 조절합니다(기본 2분).
- 무중단이 필요하면 이후 blue-green(포트 2개 + 리버스 프록시 스위칭)으로 확장할 수 있습니다. 현재는 재시작 시 수 초 다운타임이 있습니다.

## 제거 (uninstall)

```bash
cd /opt/pm-safeline/app

# 서비스·타이머·유닛만 제거 (앱 디렉토리·.env·data 는 보존)
sudo bash deploy/teardown.sh

# 앱 디렉토리(/opt/pm-safeline)까지 통째로 완전 삭제
sudo bash deploy/teardown.sh --purge
```

스크립트 없이 수동으로 하려면:

```bash
sudo systemctl disable --now pm-safeline-deploy.timer pm-safeline.service
sudo rm -f /etc/systemd/system/pm-safeline*.service /etc/systemd/system/pm-safeline*.timer
sudo systemctl daemon-reload
sudo rm -rf /opt/pm-safeline    # (선택) 앱 디렉토리까지 완전 삭제
```

## 대안 (참고)

- **GitHub 웹훅**: merge 즉시 배포(지연 0). 서버에 수신 엔드포인트 + 시크릿 검증 필요.
- **GitHub Actions**: CI(빌드·테스트) 후 SSH 로 배포. 서버에 배포키 등록 필요. 폴링보다 표준적이나 설정이 더 많습니다.
