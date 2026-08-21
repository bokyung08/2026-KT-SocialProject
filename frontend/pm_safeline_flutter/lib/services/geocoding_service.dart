import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/place_search_result.dart';

class GeocodingException implements Exception {
  const GeocodingException(this.message);
  final String message;
}

class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// 좌표를 실제 지명 + 주소로 변환한다. 실패하면 null을 반환한다
  /// (호출부에서 좌표 표기로 대체할 수 있게 예외를 던지지 않는다).
  /// 검색 결과(`PlaceSearchResult.fromNominatimJson`)와 동일한 방식으로
  /// display_name의 첫 조각을 이름, 나머지를 주소로 나눈다.
  Future<({String name, String address})?> reverseGeocode(
    double lat,
    double lon,
  ) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lon',
      'format': 'jsonv2',
      'addressdetails': '1',
      'zoom': '18',
    });
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Accept-Language': 'ko',
              'User-Agent': 'PM-SafeLine-Flutter-Demo/1.0',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final displayName = decoded['display_name']?.toString().trim() ?? '';
      if (displayName.isEmpty) return null;
      final parts = displayName
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (parts.isEmpty) return null;
      final rawName = decoded['name'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : parts.first;
      final address = _formatAddress(decoded['address'], fallback: displayName);
      return (name: name, address: address);
    } catch (_) {
      return null;
    }
  }

  /// Nominatim의 `address` 상세 필드로 시/도 → 구 → 동 → 도로명 → 번지 순의
  /// 한국식 주소를 만든다. 국가·우편번호는 제외한다.
  String _formatAddress(dynamic addressJson, {required String fallback}) {
    if (addressJson is! Map) return fallback;
    final address = addressJson.map(
      (key, value) => MapEntry(key.toString(), value?.toString().trim() ?? ''),
    );
    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = address[key];
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final ordered = <String>[];
    void add(String? value) {
      if (value != null && !ordered.contains(value)) ordered.add(value);
    }

    add(pick(['state', 'province', 'city']));
    add(pick(['city', 'county']));
    add(pick(['borough', 'city_district']));
    add(pick(['suburb', 'quarter', 'neighbourhood', 'town', 'village']));
    add(pick(['road']));
    add(pick(['house_number']));

    return ordered.isEmpty ? fallback : ordered.join(' ');
  }

  Future<List<PlaceSearchResult>> search(String query) async {
    final keyword = query.trim();
    if (keyword.length < 2) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': keyword,
      'format': 'jsonv2',
      'limit': '8',
      'countrycodes': 'kr',
      'addressdetails': '1',
      'namedetails': '1',
    });
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Accept-Language': 'ko',
              'User-Agent': 'PM-SafeLine-Flutter-Demo/1.0',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw GeocodingException(
          '장소 검색 서버가 응답하지 않습니다. (${response.statusCode})',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const FormatException('검색 응답 형식 오류');
      final parsed = decoded
          .whereType<Map>()
          .map(
            (item) => PlaceSearchResult.fromNominatimJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
      final unique = <String, PlaceSearchResult>{};
      for (final result in parsed) {
        // 같은 이름과 주소의 중복 OSM 객체는 UX에서 구분할 정보가 없으므로 하나로 합친다.
        unique.putIfAbsent(
          '${result.name.toLowerCase()}|${result.address.toLowerCase()}',
          () => result,
        );
      }
      return createDistinctDisplayTitles(unique.values.toList(growable: false));
    } on TimeoutException {
      throw const GeocodingException('장소 검색 시간이 초과됐습니다. 다시 시도해 주세요.');
    } on GeocodingException {
      rethrow;
    } on FormatException {
      throw const GeocodingException('장소 검색 결과를 해석하지 못했습니다.');
    } catch (_) {
      throw const GeocodingException('네트워크 연결을 확인하고 다시 검색해 주세요.');
    }
  }
}
