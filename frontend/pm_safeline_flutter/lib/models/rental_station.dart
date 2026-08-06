import 'package:latlong2/latlong.dart';

enum RentalStationStatus { available, lowAvailability, unavailable, unknown }

class RentalStation {
  const RentalStation({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
    required this.availableBikes,
    required this.totalDocks,
    required this.returnableDocks,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lon;
  final int? availableBikes;
  final int? totalDocks;
  final int? returnableDocks;
  final DateTime? updatedAt;

  factory RentalStation.fromJson(Map<String, dynamic> json) {
    final updatedAtValue = json['updatedAt'];
    return RentalStation(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      address: _requiredString(json, 'address'),
      lat: _requiredDouble(json, 'lat'),
      lon: _requiredDouble(json, 'lon'),
      availableBikes: _nullableInt(json, 'availableBikes'),
      totalDocks: _nullableInt(json, 'totalDocks'),
      returnableDocks: _nullableInt(json, 'returnableDocks'),
      updatedAt: updatedAtValue == null
          ? null
          : DateTime.tryParse(updatedAtValue.toString()),
    );
  }

  LatLng get position => LatLng(lat, lon);
  RentalStationStatus get status {
    final bikes = availableBikes;
    if (bikes == null) return RentalStationStatus.unknown;
    if (bikes == 0) return RentalStationStatus.unavailable;
    if (bikes <= 2) return RentalStationStatus.lowAvailability;
    return RentalStationStatus.available;
  }
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('RentalStation.$field must be a non-empty string.');
}

double _requiredDouble(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value?.toString() ?? '');
  if (parsed != null) return parsed;
  throw FormatException('RentalStation.$field must be a number.');
}

int? _nullableInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  final parsed = int.tryParse(value.toString());
  if (parsed != null) return parsed;
  throw FormatException('RentalStation.$field must be an integer or null.');
}
