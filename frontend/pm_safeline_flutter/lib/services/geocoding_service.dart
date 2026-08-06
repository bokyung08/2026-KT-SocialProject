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
