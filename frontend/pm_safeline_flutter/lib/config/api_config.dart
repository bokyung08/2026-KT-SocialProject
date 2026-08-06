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
    currentOrigin: kIsWeb ? Uri.base.origin : null,
  );

  static String get platformLabel =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  static String resolveBaseUrl({
    required String definedValue,
    required bool isWeb,
    required TargetPlatform platform,
    String? currentOrigin,
  }) {
    final explicitValue = definedValue.trim();
    if (explicitValue.isNotEmpty) return normalizeBaseUrl(explicitValue);
    if (isWeb) {
      return normalizeBaseUrl(
        currentOrigin ?? (throw StateError('Web origin을 확인할 수 없습니다.')),
      );
    }
    throw StateError(
      '${platform.name}에서 실제 API를 사용하려면 '
      'API_BASE_URL을 dart-define으로 설정해야 합니다.',
    );
  }

  static String normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (normalized.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty) {
      throw FormatException('API_BASE_URL 형식이 올바르지 않습니다.');
    }
    return normalized;
  }

  static Uri apiUri(String path, {String? baseUrl}) {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrl ?? ApiConfig.baseUrl);
    final normalizedPath = path.trim().replaceFirst(RegExp(r'^/+'), '');
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'API 경로가 비어 있습니다.');
    }
    return Uri.parse('$normalizedBaseUrl/$normalizedPath');
  }

  static bool isInsideDaejeonServiceArea({
    required double lat,
    required double lon,
  }) => lon >= 127.30 && lon <= 127.43 && lat >= 36.31 && lat <= 36.39;

  static void logStartup() {
    if (!kDebugMode) return;
    debugPrint('[API Config] USE_MOCK=$useMock');
    debugPrint(
      '[API Config] API_BASE_URL=${useMock ? 'not-required' : baseUrl}',
    );
    debugPrint('[API Config] platform=$platformLabel');
  }
}
