import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/rental_station.dart';
import 'rental_station_service.dart';

class ApiRentalStationService implements RentalStationService {
  ApiRentalStationService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<List<RentalStation>> fetchStations() async {
    final normalizedBaseUrl = _baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$normalizedBaseUrl/tashu/stations');

    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      final decoded = _decodeResponse(response.bodyBytes);
      if (response.statusCode != 200) {
        _logError();
        throw RentalStationException(
          _errorMessage(decoded) ?? '대여소 정보를 불러오지 못했습니다.',
        );
      }
      if (decoded is! Map) {
        throw const FormatException('Expected a response object.');
      }

      final payload = Map<String, dynamic>.from(decoded);
      if (payload['source'] != 'api') {
        _logError();
        throw RentalStationException(
          _errorMessage(payload) ?? '대여소 정보를 불러오지 못했습니다.',
        );
      }
      final count = _parseCount(payload['count']);
      final rawStations = payload['stations'];
      if (rawStations is! List) {
        throw const FormatException('Expected a stations list.');
      }
      if (count < rawStations.length) {
        throw const FormatException('Station count is smaller than stations.');
      }
      final stations = rawStations
          .map(
            (item) =>
                RentalStation.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      _logSuccess(stations);
      return stations;
    } on TimeoutException {
      _logError();
      throw const RentalStationException('대여소 정보를 불러오지 못했습니다.');
    } on RentalStationException {
      rethrow;
    } on FormatException {
      _logError();
      throw const RentalStationException('대여소 정보를 불러오지 못했습니다.');
    } catch (_) {
      _logError();
      throw const RentalStationException('대여소 정보를 불러오지 못했습니다.');
    }
  }

  int _parseCount(dynamic value) {
    if (value is int && value >= 0) return value;
    if (value is num && value >= 0 && value == value.roundToDouble()) {
      return value.toInt();
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null && parsed >= 0) return parsed;
    throw const FormatException('Expected a non-negative count.');
  }

  dynamic _decodeResponse(List<int> bodyBytes) {
    try {
      return jsonDecode(utf8.decode(bodyBytes));
    } on FormatException {
      return null;
    }
  }

  String? _errorMessage(dynamic decoded) {
    if (decoded is! Map) return null;
    final message = decoded['message'];
    return message is String && message.trim().isNotEmpty
        ? message.trim()
        : null;
  }

  void _logSuccess(List<RentalStation> stations) {
    if (!kDebugMode) return;
    debugPrint('[RentalStation] stationCount=${stations.length}');
    debugPrint(
      '[RentalStation] firstStationName='
      '${stations.isEmpty ? '없음' : stations.first.name}',
    );
    debugPrint('[RentalStation] source=api');
  }

  void _logError() {
    if (!kDebugMode) return;
    debugPrint('[RentalStation] stationCount=0');
    debugPrint('[RentalStation] firstStationName=없음');
    debugPrint('[RentalStation] source=error');
  }
}
