import 'package:flutter/foundation.dart';

class ApiConfig {
  const ApiConfig._();

  static const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
  static const _definedBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl => resolveBaseUrl(
    definedValue: _definedBaseUrl,
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  static String get platformLabel =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  static String resolveBaseUrl({
    required String definedValue,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    final explicitValue = definedValue.trim();
    if (explicitValue.isNotEmpty) return explicitValue;
    if (isWeb) return 'http://localhost:8080';
    return platform == TargetPlatform.android
        ? 'http://10.0.2.2:8080'
        : 'http://localhost:8080';
  }

  static bool isInsideDaejeonServiceArea({
    required double lat,
    required double lon,
  }) => lon >= 127.30 && lon <= 127.43 && lat >= 36.31 && lat <= 36.39;

  static void logStartup() {
    if (!kDebugMode) return;
    debugPrint('[API Config] USE_MOCK=$useMock');
    debugPrint('[API Config] API_BASE_URL=$baseUrl');
    debugPrint('[API Config] platform=$platformLabel');
  }
}
