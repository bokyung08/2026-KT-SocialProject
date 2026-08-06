import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_rental_station_service.dart';
import 'mock_rental_station_service.dart';
import 'rental_station_service.dart';

RentalStationService createRentalStationService({
  bool useMock = ApiConfig.useMock,
  http.Client? client,
  String? baseUrl,
}) {
  final service = useMock
      ? const MockRentalStationService()
      : ApiRentalStationService(client: client, baseUrl: baseUrl);
  if (kDebugMode) {
    debugPrint('[RentalStation] USE_MOCK=$useMock');
    debugPrint('[RentalStation] RentalStationService=${service.runtimeType}');
  }
  return service;
}
