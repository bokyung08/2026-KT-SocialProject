import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/place.dart';
import '../models/route_result.dart';
import 'route_repository.dart';

class ApiRouteRepository implements RouteRepository {
  ApiRouteRepository(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client(),
      _enableDebugHealthCheck = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _enableDebugHealthCheck;
  bool _healthChecked = false;

  @override
  Future<List<RouteResult>> findRoutes(Place start, Place destination) async {
    final routeUri = ApiConfig.apiUri('/route', baseUrl: baseUrl);
    final requestBody = {
      'fromLat': start.position.latitude,
      'fromLon': start.position.longitude,
      'toLat': destination.position.latitude,
      'toLon': destination.position.longitude,
      'alternatives': 3,
    };

    if (kDebugMode) {
      debugPrint('[Route API] USE_MOCK=${ApiConfig.useMock}');
      debugPrint('[Route API] API_BASE_URL=$baseUrl');
      debugPrint('[Route API] platform=${ApiConfig.platformLabel}');
      debugPrint('[Route API] requestUrl=$routeUri');
      debugPrint(
        '[Route API] fromLat=${requestBody['fromLat']}, '
        'fromLon=${requestBody['fromLon']}, '
        'toLat=${requestBody['toLat']}, toLon=${requestBody['toLon']}',
      );
    }

    try {
      await _logHealthStatus();
      final response = await _client
          .post(
            routeUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        debugPrint(
          '[Route API] POST $routeUri statusCode=${response.statusCode}',
        );
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw const RouteRepositoryException('서버 응답을 해석할 수 없습니다.');
      }
      if (response.statusCode != 200) {
        final detail = decoded is Map ? decoded['detail'] : null;
        throw RouteRepositoryException(
          detail?.toString() ?? '서버 요청에 실패했습니다. (${response.statusCode})',
        );
      }
      if (decoded is! Map || decoded['routes'] is! List) {
        throw const RouteRepositoryException('서버 응답 형식이 올바르지 않습니다.');
      }

      final rawRoutes = decoded['routes'] as List;
      final routes = <RouteResult>[];
      for (final (index, item) in rawRoutes.indexed) {
        if (item is! Map) throw const FormatException('경로 항목 형식 오류');
        final route = RouteResult.fromJson(
          Map<String, dynamic>.from(item),
          name: index == 0 ? '추천 경로' : '대안 경로 ${index + 1}',
        );
        if (kDebugMode) {
          debugPrint(
            '[Route API] route[$index] response geometry length='
            '${route.geometry.length}',
          );
        }
        if (route.geometry.length <= 2) {
          _logInsufficientGeometry(
            index: index,
            start: start,
            destination: destination,
            statusCode: response.statusCode,
            responseBody: response.body,
            geometryLength: route.geometry.length,
          );
          if (index == 0) {
            throw const RouteRepositoryException(
              '서버가 실제 도로 경로 좌표를 충분히 반환하지 않았습니다. '
              '임시 직선 대신 경로를 다시 탐색해 주세요.',
            );
          }
          continue;
        }
        routes.add(route);
      }
      if (routes.isEmpty) {
        throw const RouteRepositoryException('탐색된 경로가 없습니다. 다른 위치를 선택해 주세요.');
      }
      return routes;
    } on TimeoutException {
      throw const RouteRepositoryException('서버 응답이 늦어지고 있어요. 잠시 후 다시 시도해 주세요.');
    } on RouteRepositoryException {
      rethrow;
    } on FormatException {
      throw const RouteRepositoryException('서버에서 올바르지 않은 경로 데이터를 받았습니다.');
    } catch (error) {
      if (kDebugMode) debugPrint('[Route API] network error=$error');
      throw const RouteRepositoryException(
        '서버에 연결할 수 없습니다. 주소와 네트워크를 확인해 주세요.',
      );
    }
  }

  Future<void> _logHealthStatus() async {
    if (!kDebugMode || !_enableDebugHealthCheck || _healthChecked) return;
    _healthChecked = true;
    final healthUri = ApiConfig.apiUri('/health', baseUrl: baseUrl);
    try {
      final response = await _client
          .get(healthUri)
          .timeout(const Duration(seconds: 4));
      debugPrint(
        '[Route API] GET $healthUri statusCode=${response.statusCode} '
        'body=${_bodySnippet(response.body)}',
      );
    } catch (error) {
      debugPrint(
        '[Route API] GET $healthUri failed=$error '
        '(API_BASE_URL과 서버 접근 가능 여부를 확인하세요.)',
      );
    }
  }

  void _logInsufficientGeometry({
    required int index,
    required Place start,
    required Place destination,
    required int statusCode,
    required String responseBody,
    required int geometryLength,
  }) {
    if (!kDebugMode) return;
    debugPrint('[Route API] insufficient geometry routeIndex=$index');
    debugPrint(
      '[Route API] fromLat=${start.position.latitude}, '
      'fromLon=${start.position.longitude}, '
      'toLat=${destination.position.latitude}, '
      'toLon=${destination.position.longitude}',
    );
    debugPrint('[Route API] response status=$statusCode');
    debugPrint('[Route API] response geometry length=$geometryLength');
    debugPrint('[Route API] response body=${_bodySnippet(responseBody)}');
  }

  String _bodySnippet(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 500 ? compact : '${compact.substring(0, 500)}…';
  }
}
