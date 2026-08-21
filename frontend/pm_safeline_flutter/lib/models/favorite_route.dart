import 'place.dart';

class FavoriteRoute {
  const FavoriteRoute({
    required this.id,
    required this.start,
    required this.destination,
  });

  final String id;
  final Place start;
  final Place destination;

  String get label => '${start.name} → ${destination.name}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toJson(),
    'destination': destination.toJson(),
  };

  static FavoriteRoute fromJson(Map<String, dynamic> json) => FavoriteRoute(
    id: json['id'] as String,
    start: Place.fromJson(Map<String, dynamic>.from(json['start'] as Map)),
    destination: Place.fromJson(
      Map<String, dynamic>.from(json['destination'] as Map),
    ),
  );

  static String idFor(Place start, Place destination) =>
      '${start.position.latitude},${start.position.longitude}'
      '->${destination.position.latitude},${destination.position.longitude}';
}
