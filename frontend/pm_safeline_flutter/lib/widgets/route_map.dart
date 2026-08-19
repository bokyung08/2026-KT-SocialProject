import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/rental_station.dart';
import '../models/route_result.dart';
import '../theme/app_theme.dart';
import 'rental_station_layer.dart';

class RouteMapController {
  _RouteMapState? _state;
  LatLng? _lastMoveTarget;
  LatLng? _lastCameraCenter;
  Rect? _lastUsableRect;
  double? _lastMoveZoom;
  int _fitRequestCount = 0;

  LatLng? get lastMoveTarget => _lastMoveTarget;
  LatLng? get lastCameraCenter => _lastCameraCenter;
  Rect? get lastUsableRect => _lastUsableRect;
  double? get lastMoveZoom => _lastMoveZoom;
  int get fitRequestCount => _fitRequestCount;

  void moveTo(LatLng point, {double zoom = 15}) {
    _lastMoveTarget = point;
    _lastCameraCenter = point;
    _lastUsableRect = null;
    _lastMoveZoom = zoom;
    _state?._moveTo(point, zoom);
  }

  void moveToVisibleCenter(
    LatLng point, {
    required Rect usableRect,
    double zoom = 15,
  }) {
    _lastMoveTarget = point;
    _lastUsableRect = usableRect;
    _lastMoveZoom = zoom;
    _lastCameraCenter = _state?._moveToVisibleCenter(point, usableRect, zoom);
  }

  void fitRoute() {
    _fitRequestCount++;
    _state?._fit();
  }

  void _attach(_RouteMapState state) => _state = state;

  void _detach(_RouteMapState state) {
    if (identical(_state, state)) _state = null;
  }
}

class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    this.controller,
    this.start,
    this.destination,
    this.route,
    this.accessStart,
    this.accessEnd,
    this.interactive = true,
    this.rentalStations = const [],
    this.showRentalStations = false,
    this.onRentalStationTap,
    this.fitPadding = const EdgeInsets.all(42),
    this.maxRouteZoom = 16,
  });

  final RouteMapController? controller;
  final LatLng? start;
  final LatLng? destination;
  final RouteResult? route;
  final LatLng? accessStart;
  final LatLng? accessEnd;
  final bool interactive;
  final List<RentalStation> rentalStations;
  final bool showRentalStations;
  final ValueChanged<RentalStation>? onRentalStationTap;
  final EdgeInsets fitPadding;
  final double maxRouteZoom;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  static const _daejeon = LatLng(36.3504, 127.3845);
  final _mapController = MapController();

  List<LatLng> get _cameraPoints {
    final geometry = widget.route?.geometry ?? const <LatLng>[];
    if (geometry.length > 2) {
      return [
        if (widget.start != null) widget.start!,
        ...geometry,
        if (widget.destination != null) widget.destination!,
      ];
    }
    return [
      if (widget.start != null) widget.start!,
      if (widget.destination != null) widget.destination!,
    ];
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  @override
  void didUpdateWidget(covariant RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.route != widget.route ||
        oldWidget.start != widget.start ||
        oldWidget.destination != widget.destination ||
        oldWidget.accessStart != widget.accessStart ||
        oldWidget.accessEnd != widget.accessEnd ||
        oldWidget.fitPadding != widget.fitPadding ||
        oldWidget.maxRouteZoom != widget.maxRouteZoom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  void _moveTo(LatLng point, double zoom) {
    if (!mounted) return;
    _mapController.move(point, zoom);
  }

  LatLng? _moveToVisibleCenter(LatLng point, Rect usableRect, double zoom) {
    if (!mounted) return null;
    final camera = _mapController.camera;
    final mapRect = Offset.zero & camera.size;
    final visibleRect = usableRect.intersect(mapRect);
    if (visibleRect.isEmpty) {
      _mapController.move(point, zoom);
      return point;
    }

    final targetOffset = visibleRect.center - mapRect.center;
    final projectedTarget = camera.projectAtZoom(point, zoom);
    final cameraCenter = camera.unprojectAtZoom(
      projectedTarget - targetOffset,
      zoom,
    );
    _mapController.move(cameraCenter, zoom);
    return cameraCenter;
  }

  void _fit() {
    if (!mounted) return;
    final points = _cameraPoints;
    if (points.length > 1) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: widget.fitPadding,
          maxZoom: widget.maxRouteZoom,
        ),
      );
    } else if (points.length == 1) {
      _mapController.move(points.first, 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = _cameraPoints;
    final hasAccessSegment =
        widget.accessStart != null &&
        widget.accessEnd != null &&
        widget.accessStart != widget.accessEnd;
    final hasRoadGeometry =
        widget.route != null && widget.route!.geometry.length > 2;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: points.isEmpty ? _daejeon : points.first,
        initialZoom: 13.2,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kt.pm_safeline_flutter',
        ),
        if (hasAccessSegment)
          PolylineLayer(
            key: const ValueKey('rental-access-polyline'),
            polylines: [
              Polyline(
                points: [widget.accessStart!, widget.accessEnd!],
                strokeWidth: 2.5,
                color: const Color(0xFF9A9AA3),
                pattern: const StrokePattern.dotted(spacingFactor: 1.8),
              ),
            ],
          ),
        if (hasRoadGeometry)
          PolylineLayer(
            key: const ValueKey('main-route-polyline'),
            polylines: [
              Polyline(
                points: widget.route!.geometry,
                strokeWidth: 6,
                color: AppColors.safe,
              ),
            ],
          ),
        if (widget.showRentalStations)
          RentalStationLayer(
            stations: widget.rentalStations,
            onStationTap: (station) => widget.onRentalStationTap?.call(station),
          ),
        MarkerLayer(
          markers: [
            if (widget.start != null)
              _marker(widget.start!, AppColors.ink, Icons.circle_outlined),
            if (widget.destination != null)
              _marker(widget.destination!, AppColors.brand, Icons.location_on),
            ...?widget.route?.hazards
                .where((item) => item.position != null)
                .map(
                  (item) => _marker(
                    item.position!,
                    AppColors.danger,
                    Icons.priority_high,
                  ),
                ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Marker _marker(LatLng point, Color color, IconData icon) => Marker(
    point: point,
    width: 38,
    height: 38,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Icon(icon, color: color, size: 24),
    ),
  );
}
