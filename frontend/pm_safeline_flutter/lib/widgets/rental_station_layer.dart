import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/rental_station.dart';

class RentalStationLayer extends StatelessWidget {
  const RentalStationLayer({
    super.key,
    required this.stations,
    required this.onStationTap,
  });

  final List<RentalStation> stations;
  final ValueChanged<RentalStation> onStationTap;

  @override
  Widget build(BuildContext context) => MarkerLayer(
    markers: [
      for (final station in stations)
        Marker(
          point: station.position,
          width: 34,
          height: 34,
          child: Semantics(
            button: true,
            label: '${station.name}, ${_statusLabel(station.status)}',
            child: GestureDetector(
              key: ValueKey('rental-station-${station.id}'),
              onTap: () => onStationTap(station),
              child: Container(
                decoration: BoxDecoration(
                  color: _statusColor(station.status),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 7),
                  ],
                ),
                child: const Icon(
                  Icons.pedal_bike,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  static Color _statusColor(RentalStationStatus status) => switch (status) {
    RentalStationStatus.available => const Color(0xFF20A464),
    RentalStationStatus.lowAvailability => const Color(0xFFF5B700),
    RentalStationStatus.unavailable => const Color(0xFFD94A45),
    RentalStationStatus.unknown => const Color(0xFF8C8C94),
  };

  static String _statusLabel(RentalStationStatus status) => switch (status) {
    RentalStationStatus.available => '대여 가능',
    RentalStationStatus.lowAvailability => '재고 부족',
    RentalStationStatus.unavailable => '대여 불가',
    RentalStationStatus.unknown => '수량 정보 없음',
  };
}
