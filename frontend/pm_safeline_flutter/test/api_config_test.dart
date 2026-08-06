import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm_safeline_flutter/config/api_config.dart';

void main() {
  test('dart-define API_BASE_URL 값이 플랫폼 기본값보다 우선한다', () {
    expect(
      ApiConfig.resolveBaseUrl(
        definedValue: 'http://192.168.0.10:8080',
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      'http://192.168.0.10:8080',
    );
  });

  test('API_BASE_URL 미지정 시 Web과 Desktop은 localhost를 사용한다', () {
    expect(
      ApiConfig.resolveBaseUrl(
        definedValue: '',
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      'http://localhost:8080',
    );
    expect(
      ApiConfig.resolveBaseUrl(
        definedValue: '',
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      'http://localhost:8080',
    );
  });

  test('API_BASE_URL 미지정 Android는 Emulator 호스트 주소를 사용한다', () {
    expect(
      ApiConfig.resolveBaseUrl(
        definedValue: '',
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      'http://10.0.2.2:8080',
    );
  });

  test('대전 서비스 영역을 PM_OSM_BBOX 기준으로 판정한다', () {
    expect(
      ApiConfig.isInsideDaejeonServiceArea(lat: 36.3508, lon: 127.3842),
      isTrue,
    );
    expect(
      ApiConfig.isInsideDaejeonServiceArea(lat: 37.5665, lon: 126.9780),
      isFalse,
    );
  });
}
