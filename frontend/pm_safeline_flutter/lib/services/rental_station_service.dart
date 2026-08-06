import '../models/rental_station.dart';

abstract interface class RentalStationService {
  Future<List<RentalStation>> fetchStations();
}

class RentalStationException implements Exception {
  const RentalStationException(this.message);
  final String message;
}
