import 'package:latlong2/latlong.dart';

class Place {
  const Place(this.name, this.address, this.position);

  final String name;
  final String address;
  final LatLng position;

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'lat': position.latitude,
    'lon': position.longitude,
  };

  static Place fromJson(Map<String, dynamic> json) => Place(
    json['name'] as String,
    json['address'] as String,
    LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
  );
}
