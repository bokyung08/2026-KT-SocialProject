# PM 세이프라인 Flutter

개인형 이동장치(PM) 이용자를 위해 자전거도로 연속성과 위험 도로구조를 반영한 안전 경로를 보여 주는 Web·Android·iOS Flutter 프로토타입입니다. 디자인 데모는 백엔드 없이 Mock 모드로 실행할 수 있습니다.

## 구조

- `lib/config`: `dart-define` 실행 설정
- `lib/models`: 장소·API 경로 모델과 `[경도, 위도]` 좌표 변환
- `lib/repositories`: Mock/API 저장소
- `lib/screens`: 홈, 장소 입력, 분석, 결과, 서비스 정보
- `lib/widgets`: OpenStreetMap 지도와 하단 내비게이션
- `test`: 모델, 좌표, 표시 형식, 기본 화면 테스트

## 실행

```bash
cd frontend/pm_safeline_flutter
flutter pub get
flutter run -d chrome --dart-define=USE_MOCK=true
```

기본값은 `USE_MOCK=true`입니다. `API_BASE_URL`을 `dart-define`으로 전달하면 해당 값이 항상 최우선입니다. 값을 생략하면 Web·Windows/Desktop은 `http://localhost:8080`, Android는 에뮬레이터 기준 `http://10.0.2.2:8080`을 사용합니다.

실제 Ktor API에 연결하려면 다음과 같이 실행합니다.

```bash
flutter run -d chrome --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://localhost:8080
```

Android 에뮬레이터에서 호스트 PC의 서버는 `localhost`가 아니라 `10.0.2.2`입니다.

```bash
flutter run -d emulator-5554 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Android 에뮬레이터 브라우저에서 `http://10.0.2.2:8080/health`를 열어 `{"status":"ok","engine":true}`가 보이는지 먼저 확인할 수 있습니다. Debug 앱은 최초 경로 요청 전에 `/health` 상태코드와 응답을 로그에 남깁니다. 로컬 Ktor 개발 서버가 HTTP를 사용하므로 Android debug manifest에서만 cleartext 통신을 허용하며, release manifest에는 이 설정을 추가하지 않습니다.

실제 Android 기기에서는 PC와 같은 네트워크에 연결한 뒤 `http://<PC의-LAN-IP>:8080`을 사용하고 방화벽 접근을 허용해야 합니다. Android 기본값인 `10.0.2.2`는 에뮬레이터 전용이므로 실제 기기에서는 반드시 `API_BASE_URL`을 지정하세요.

## 장소 검색

출발지와 도착지는 2글자 이상 입력하면 400ms debounce 후 자동으로 검색됩니다. Enter와 검색 아이콘으로 즉시 검색할 수도 있습니다. 검색은 무료 공개 Nominatim API를 사용하며 `GeocodingService`로 분리되어 있어 다른 지오코딩 API로 교체할 수 있습니다. 최신 입력의 결과만 표시하고 검색 결과는 최대 8개로 제한합니다. 같은 이름의 장소는 지점명 또는 주소 기반 `displayTitle`로 구분합니다. 운영 서비스에서는 [Nominatim 사용 정책](https://operations.osmfoundation.org/policies/nominatim/)에 맞는 자체 인스턴스나 상용 제공자를 사용해야 합니다.

검색 결과에서 장소를 선택해야 내부 좌표가 확정되고 경로 탐색 버튼이 활성화됩니다. Mock 모드 역시 이 좌표를 기준으로 데모 경로를 생성합니다.

## 공영자전거 대여소

경로 결과 지도의 `타슈` 토글을 켜면 대전 공영자전거 대여소 mock 데이터가 표시됩니다. 마커 색상은 대여 가능(초록), 대여 불가(회색), 수량 정보 없음(노랑)을 뜻합니다. 대여소 상세의 `여기서 대여`를 누르면 해당 대여소를 출발지로 지정하고, 선택된 도착지까지 기존 `/route` 안전 경로를 다시 탐색합니다. 현재 출발지에서 대여소까지는 도보 경로가 아니라 직선 접근거리만 안내합니다.

현재 앱은 기기 현재 위치로 사용자가 선택한 출발지를 덮어쓰지 않습니다. 대여소 접근 거리는 기존 선택 출발지를 기준으로만 계산하고, 여기서 대여 이후 main route의 출발지는 항상 선택 대여소 좌표입니다. 향후 위치 기능을 추가할 때는 PM OSM 지원 범위(lon 127.30~127.43, lat 36.31~36.39) 안의 위치만 경로 출발지 후보로 사용해야 합니다.

대여소 데이터는 `RentalStationService`로 분리되어 있습니다. 실제 타슈 OpenAPI 연동 시 인증 방식과 base URL을 환경 설정으로 분리하고, 응답 필드 매핑, 운영 갱신 주기에 맞춘 재조회·캐시, 장애/빈 응답 처리를 구현해야 합니다. API 키는 소스에 저장하지 않아야 합니다.

민간 킥보드와 카카오바이크의 실시간 위치·재고는 사업자 제휴 API와 이용 권한이 필요하므로 현재 프로토타입에는 포함하지 않습니다.

## 지도와 API 주의사항

지도는 `flutter_map`과 OpenStreetMap 타일을 사용하므로 지도 API 키가 필요하지 않습니다. 앱 화면에 **© OpenStreetMap contributors** 저작자 표시를 유지해야 합니다. 현재 프로토타입은 OSM public tile을 사용하지만, 배포 시에는 전용 타일 서버 또는 타일 제공업체로 교체해야 합니다.

Flutter Web은 브라우저의 CORS 정책을 따릅니다. Ktor 서버가 Flutter Web 주소(개발 중에는 임의 localhost 포트)의 `POST`, `Content-Type: application/json` 요청을 허용하지 않으면 브라우저에서 API 호출이 차단됩니다. 브라우저 보안을 끄지 말고 백엔드팀에 제한된 origin과 메서드·헤더를 허용하는 CORS 설정을 요청하세요.

현재 `/route` API는 거리, 시간, 탐색 비용, 안전점수, 경로 geometry, 자전거도로 비율, 도로유형 전환 횟수만 제공합니다. 다음 데이터는 서버 응답에 없어 API 모드에서 생성하지 않습니다.

- 구간별 안전·주의·위험 등급
- 단절·합류·위험 지점 좌표와 사유
- 안전점수 상세 산출 내역

위 정보는 Mock 모드에서만 UI 시연용으로 표시됩니다. 향후 백엔드팀과 위험 구간 타입·좌표·설명, 점수 구성요소를 포함하는 버전 관리된 응답 스키마를 협의해야 합니다.

## 검증

```bash
dart format .
flutter analyze
flutter test
flutter build web
```

iOS 소스는 포함되어 있지만 iOS 빌드와 서명 검증에는 macOS와 Xcode가 필요합니다.