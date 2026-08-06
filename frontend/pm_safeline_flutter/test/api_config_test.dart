import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm_safeline_flutter/config/api_config.dart';

void main() {
  const localWebBaseUrl =
      'http://localhost'
      ':8080';
  const androidEmulatorBaseUrl =
      'http://10.0.2.2'
      ':8080';
  const deployedOrigin =
      'http://cuws.duckdns.org'
      ':8080';

  test('dart-define API_BASE_URL 값이 현재 origin보다 우선한다', () {
    expect(
      ApiConfig.resolveBaseUrl(
        definedValue: '$localWebBaseUrl/',
        isWeb: true,
        platform: TargetPlatform.android,
        currentOrigin: deployedOrigin,
      ),
      localWebBaseUrl,
    );
  });

  test('Web은 API_BASE_URL 미지정 시 현재 origin을 사용한다', () {
    expect(
      ApiConfig.resolveBaseUrl(
        definedValue: '',
        isWeb: true,
        platform: TargetPlatform.android,
        currentOrigin: '$deployedOrigin/',
      ),
      deployedOrigin,
    );
  });

  test('Android는 전달된 API_BASE_URL을 사용한다', () {
    expect(
      ApiConfig.resolveBaseUrl(
        definedValue: androidEmulatorBaseUrl,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      androidEmulatorBaseUrl,
    );
  });

  test('Web이 아닌 플랫폼에서 API_BASE_URL 미지정 시 명확히 실패한다', () {
    expect(
      () => ApiConfig.resolveBaseUrl(
        definedValue: '',
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('URL 끝의 슬래시를 제거하고 API 경로를 한 번만 연결한다', () {
    expect(
      ApiConfig.apiUri('/route', baseUrl: '$localWebBaseUrl///').toString(),
      '$localWebBaseUrl/route',
    );
    expect(
      ApiConfig.apiUri('health', baseUrl: '$localWebBaseUrl/').toString(),
      '$localWebBaseUrl/health',
    );
    expect(
      ApiConfig.apiUri(
        '/tashu/stations',
        baseUrl: '$localWebBaseUrl/',
      ).toString(),
      '$localWebBaseUrl/tashu/stations',
    );
  });

  test('잘못된 API_BASE_URL은 명확히 실패한다', () {
    expect(
      () => ApiConfig.resolveBaseUrl(
        definedValue: 'not-a-url',
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      throwsA(isA<FormatException>()),
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
