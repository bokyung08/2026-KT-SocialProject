# 배포 (Linux + systemd, 폴링 자동배포)

`main` 브랜치에 merge 되면 배포 서버가 **자동으로 pull → 빌드 → 재시작**합니다.

## 구성 요소

| 파일 | 역할 |
|---|---|
| `systemd/pm-safeline.service` | 앱을 상시 실행하는 서비스 |
| `deploy.sh` | `origin/main` 확인 → 변경 시 reset·빌드·재시작 |
| `systemd/pm-safeline-deploy.service` | `deploy.sh` 를 실행하는 oneshot |
| `systemd/pm-safeline-deploy.timer` | 2분마다 위 oneshot 실행(폴링) |

동작: **timer**(2분) → **deploy.service** → `deploy.sh`(새 커밋 있을 때만 빌드·`systemctl restart`) → **pm-safeline.service** 재시작.

## 최초 설정 (배포 서버에서 1회)

```bash
# 0) JDK 21 · git 설치 (예: Ubuntu)
sudo apt-get update && sudo apt-get install -y git openjdk-21-jdk

# 1) 배포 전용 사용자 + 디렉토리
sudo useradd --system --create-home --home-dir /opt/pm-safeline deploy
sudo -u deploy git clone -b main <REPO_URL> /opt/pm-safeline/app
cd /opt/pm-safeline/app

# 2) 비밀/설정: .env 작성 (git 에 없음). 최소 PM_OSM_FILE 지정.
sudo -u deploy cp .env.default .env
sudo -u deploy nano .env      # KOROAD_API_KEY, PM_OSM_FILE 등 채우기
#   예) PM_OSM_FILE=/opt/pm-safeline/app/data/osm/daejeon.osm
#   OSM 파일은 미리 서버에 올려두거나 Overpass 로 받아 data/osm/ 에 둔다.

# 3) 최초 빌드
sudo -u deploy env JAVA_HOME=/usr/lib/jvm/java-21-openjdk ./gradlew --no-daemon clean installDist

# 4) deploy 사용자가 앱 서비스만 재시작할 수 있게 sudoers 허용(비번 없이)
echo 'deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart pm-safeline.service' \
  | sudo tee /etc/sudoers.d/pm-safeline-deploy
sudo chmod 440 /etc/sudoers.d/pm-safeline-deploy

# 5) systemd 유닛 설치
sudo cp deploy/systemd/pm-safeline.service          /etc/systemd/system/
sudo cp deploy/systemd/pm-safeline-deploy.service   /etc/systemd/system/
sudo cp deploy/systemd/pm-safeline-deploy.timer     /etc/systemd/system/
sudo systemctl daemon-reload

# 6) 앱 + 자동배포 타이머 활성화
sudo systemctl enable --now pm-safeline.service
sudo systemctl enable --now pm-safeline-deploy.timer
```

> ⚠️ 유닛 파일의 `JAVA_HOME`, 경로(`/opt/pm-safeline/app`), 사용자(`deploy`)를 서버 환경에 맞게 확인/수정하세요.
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

## 대안 (참고)

- **GitHub 웹훅**: merge 즉시 배포(지연 0). 서버에 수신 엔드포인트 + 시크릿 검증 필요.
- **GitHub Actions**: CI(빌드·테스트) 후 SSH 로 배포. 서버에 배포키 등록 필요. 폴링보다 표준적이나 설정이 더 많습니다.
