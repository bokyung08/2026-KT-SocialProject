import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../app_controller.dart';
import '../config/api_config.dart';
import '../models/place.dart';
import '../models/rental_station.dart';
import '../models/route_result.dart';
import '../services/rental_station_recommendation_service.dart';
import '../services/rental_station_service.dart';
import '../services/rental_station_service_factory.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/route_recommendation_reason.dart';
import '../widgets/desktop_route_search_panel.dart';
import '../widgets/map_floating_controls.dart';
import '../widgets/mobile_route_selector.dart';
import '../widgets/responsive_map_shell.dart';
import '../widgets/route_map.dart';
import '../widgets/route_recommendation_reason_card.dart';

class RouteResultScreen extends StatefulWidget {
  const RouteResultScreen({
    super.key,
    required this.controller,
    this.rentalStationService,
    this.currentLocation,
    this.mapController,
  });

  final AppController controller;
  final RentalStationService? rentalStationService;
  final LatLng? currentLocation;
  final RouteMapController? mapController;

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  late final RentalStationService _rentalStationService;
  late final RouteMapController _routeMapController;
  final _recommendationService = const RentalStationRecommendationService();
  List<RentalStation> _stations = const [];
  List<RentalStation> _recommendedStations = const [];
  List<RentalStation>? _recommendationStationsSource;
  RouteResult? _recommendationRouteSource;
  LatLng? _recommendationStartSource;
  bool _showRentalStations = false;
  bool _mapFocusMode = false;
  bool _desktopSearchOpen = false;
  int _desktopSearchSession = 0;
  RouteSearchTarget _desktopSearchTarget = RouteSearchTarget.destination;
  Place? _previewStart;
  Place? _previewDestination;
  bool _loadingStations = false;
  String? _stationError;
  final _mapAreaKey = GlobalKey();
  final _mobileHeaderKey = GlobalKey();
  final _rentalToggleKey = GlobalKey();
  final _mapControlsKey = GlobalKey();
  final _dashboardKey = GlobalKey();
  double? _dashboardHeight;
  bool _dashboardMeasurementScheduled = false;
  String? _lastLayoutSignature;

  @override
  void initState() {
    super.initState();
    _rentalStationService = ApiConfig.useMock
        ? (widget.rentalStationService ??
              createRentalStationService(useMock: true))
        : createRentalStationService(useMock: false);
    _routeMapController = widget.mapController ?? RouteMapController();
  }

  void _refreshRecommendedStations(RouteResult route) {
    final start = widget.controller.start?.position;
    if (identical(_recommendationStationsSource, _stations) &&
        identical(_recommendationRouteSource, route) &&
        _recommendationStartSource == start) {
      return;
    }
    _recommendationStationsSource = _stations;
    _recommendationRouteSource = route;
    _recommendationStartSource = start;
    _recommendedStations = route.geometry.length > 2
        ? _recommendationService.recommend(
            stations: _stations,
            routeGeometry: route.geometry,
            routeStart: start,
          )
        : const [];
  }

  void _scheduleDashboardMeasurement() {
    if (_dashboardMeasurementScheduled) return;
    _dashboardMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dashboardMeasurementScheduled = false;
      if (!mounted) return;
      final renderObject = _dashboardKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final measuredHeight = renderObject.size.height;
      if (_dashboardHeight == null ||
          (_dashboardHeight! - measuredHeight).abs() > 0.5) {
        setState(() => _dashboardHeight = measuredHeight);
      }
    });
  }

  void _scheduleMapRefit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _routeMapController.fitRoute();
    });
  }

  void _observeResponsiveLayout({
    required double width,
    required bool isWide,
    required bool panelVisible,
  }) {
    final signature =
        '${width.round()}:${isWide ? 1 : 0}:${panelVisible ? 1 : 0}';
    if (_lastLayoutSignature == null) {
      _lastLayoutSignature = signature;
      return;
    }
    if (_lastLayoutSignature != signature) {
      _lastLayoutSignature = signature;
      _scheduleMapRefit();
    }
  }

  EdgeInsets _routeFitPadding({
    required double viewportHeight,
    required EdgeInsets safePadding,
    required bool isWide,
    required bool panelVisible,
  }) {
    if (isWide) {
      return EdgeInsets.fromLTRB(
        panelVisible ? 54 : 64,
        96 + safePadding.top,
        82,
        58 + safePadding.bottom,
      );
    }

    final topPadding = 136.0 + safePadding.top;
    if (_mapFocusMode) {
      return EdgeInsets.fromLTRB(52, topPadding, 52, 98 + safePadding.bottom);
    }
    final estimatedDashboardHeight = math.min(390.0, viewportHeight * 0.46);
    final dashboardHeight = _dashboardHeight ?? estimatedDashboardHeight;
    final maximumBottomPadding = math.max(
      180.0,
      viewportHeight - topPadding - 160.0,
    );
    final bottomPadding = math.min(
      dashboardHeight + 36.0 + safePadding.bottom,
      maximumBottomPadding,
    );
    return EdgeInsets.fromLTRB(52, topPadding, 52, bottomPadding);
  }

  void _moveToCurrentOrRouteStart() {
    final selectedRoute =
        widget.controller.routes[widget.controller.selectedRoute];
    final target =
        widget.currentLocation ??
        widget.controller.start?.position ??
        (selectedRoute.geometry.isEmpty ? null : selectedRoute.geometry.first);
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final usableRect = _currentLocationUsableRect();
      if (usableRect == null) {
        _routeMapController.moveTo(target, zoom: 15.5);
        return;
      }
      _routeMapController.moveToVisibleCenter(
        target,
        usableRect: usableRect,
        zoom: 15.5,
      );
    });
  }

  Rect? _rectInMap(GlobalKey key, RenderBox mapBox) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final globalOrigin = renderObject.localToGlobal(Offset.zero);
    return mapBox.globalToLocal(globalOrigin) & renderObject.size;
  }

  Rect? _currentLocationUsableRect() {
    final renderObject = _mapAreaKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final safePadding = MediaQuery.paddingOf(context);
    const edgeMargin = 16.0;
    final left = edgeMargin + safePadding.left;
    var top = edgeMargin + safePadding.top;
    var right = renderObject.size.width - edgeMargin - safePadding.right;
    var bottom = renderObject.size.height - edgeMargin - safePadding.bottom;

    final headerRect = _rectInMap(_mobileHeaderKey, renderObject);
    if (headerRect != null) top = math.max(top, headerRect.bottom + 12);

    for (final key in [_rentalToggleKey, _mapControlsKey]) {
      final controlsRect = _rectInMap(key, renderObject);
      if (controlsRect != null) {
        right = math.min(right, controlsRect.left - 12);
      }
    }

    final dashboardRect = _rectInMap(_dashboardKey, renderObject);
    if (dashboardRect != null) {
      bottom = math.min(bottom, dashboardRect.top - 12);
    }

    if (right <= left || bottom <= top) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _fitEntireRoute() => _routeMapController.fitRoute();

  void _toggleMapFocusMode() {
    setState(() {
      _mapFocusMode = !_mapFocusMode;
      if (_mapFocusMode &&
          ResponsiveLayout.isWide(MediaQuery.sizeOf(context).width)) {
        widget.controller.setDesktopPanelOpen(false);
      }
    });
    _scheduleMapRefit();
  }

  void _toggleDesktopPanel() {
    if (_desktopSearchOpen) _closeDesktopSearch();
    setState(() {
      widget.controller.toggleDesktopPanel();
      if (widget.controller.desktopPanelOpen) _mapFocusMode = false;
    });
    _scheduleMapRefit();
  }

  void _openDesktopSearch(RouteSearchTarget target) {
    setState(() {
      _desktopSearchSession++;
      _desktopSearchOpen = true;
      _desktopSearchTarget = target;
      _previewStart = widget.controller.start;
      _previewDestination = widget.controller.destination;
    });
    widget.controller.setDesktopPanelOpen(true);
  }

  void _closeDesktopSearch() {
    widget.controller.cancelDraftAnalysis();
    setState(() {
      _desktopSearchOpen = false;
      _previewStart = null;
      _previewDestination = null;
    });
  }

  void _updateDesktopPreview(Place? start, Place? destination) {
    setState(() {
      _previewStart = start;
      _previewDestination = destination;
    });
  }

  Future<String?> _submitDesktopDraft(Place start, Place destination) async {
    final error = await widget.controller.analyzeDraft(start, destination);
    if (!mounted) return error;
    if (error != null) {
      setState(() {
        _previewStart = widget.controller.start;
        _previewDestination = widget.controller.destination;
      });
      return error;
    }
    setState(() {
      _desktopSearchOpen = false;
      _previewStart = null;
      _previewDestination = null;
    });
    _scheduleMapRefit();
    return null;
  }

  void _selectRoute(int index) {
    if (index == widget.controller.selectedRoute) return;
    widget.controller.selectRoute(index);
    if (mounted) setState(() {});
    _scheduleMapRefit();
  }

  Future<void> _toggleRentalStations(bool enabled) async {
    setState(() => _showRentalStations = enabled);
    if (enabled && _stations.isEmpty && !_loadingStations) {
      await _loadRentalStations();
    }
  }

  Future<void> _loadRentalStations() async {
    setState(() {
      _loadingStations = true;
      _stationError = null;
    });
    try {
      final stations = await _rentalStationService.fetchStations();
      if (!mounted) return;
      setState(() => _stations = stations);
    } on RentalStationException catch (error) {
      if (!mounted) return;
      setState(() {
        _stations = const [];
        _stationError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stations = const [];
        _stationError = '대여소 정보를 불러오지 못했습니다.';
      });
    } finally {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  void _showStationDetails(RentalStation station) {
    final start = widget.controller.start;
    final accessDistance = start == null
        ? null
        : const Distance().as(
            LengthUnit.Meter,
            start.position,
            station.position,
          );
    debugPrint(
      '[Tashu Station] name=${station.name}, address=${station.address}, '
      'availableBikes=${station.availableBikes}, totalDocks=${station.totalDocks}, '
      'returnableDocks=${station.returnableDocks}, updatedAt=${station.updatedAt}, '
      'lat=${station.lat}, lon=${station.lon}',
    );

    final viewport = MediaQuery.sizeOf(context);
    final sheetWidth = math.min(430.0, viewport.width);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        minWidth: sheetWidth,
        maxWidth: sheetWidth,
        maxHeight: math.min(620.0, viewport.height * 0.78),
      ),
      builder: (sheetContext) => SafeArea(
        key: const ValueKey('rental-station-sheet'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFEAF7F0),
                      foregroundColor: Color(0xFF20A464),
                      child: Icon(Icons.pedal_bike),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            station.name,
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            station.address,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    _StationStatusBadge(status: station.status),
                  ],
                ),
                const SizedBox(height: 18),
                _StationDetailRow(
                  label: '대여 가능 자전거',
                  value: _count(station.availableBikes, '대'),
                ),
                if (accessDistance != null)
                  _StationDetailRow(
                    label: '현재 출발지에서 접근 거리',
                    value: '약 ${formatDistance(accessDistance)} · 직선거리',
                  ),
                if (station.totalDocks == null &&
                    station.returnableDocks == null &&
                    station.updatedAt == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      '전체 거치대·반납 가능 수량·갱신 시각은 타슈 API 미제공',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('rent-from-station'),
                    onPressed: () => _rentFromStation(station),
                    icon: const Icon(Icons.route),
                    label: const Text('여기서 대여'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rentFromStation(RentalStation station) async {
    final destination = widget.controller.destination;
    if (destination == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('도착지를 먼저 선택해 주세요.')));
      return;
    }

    Navigator.of(context).pop();
    widget.controller.setRentalStationStart(
      Place(station.name, station.address, station.position),
    );
    await widget.controller.analyze();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.routes.isEmpty ||
        widget.controller.start == null ||
        widget.controller.destination == null) {
      return const Scaffold(body: Center(child: Text('표시할 경로가 없습니다.')));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final route = widget.controller.routes[widget.controller.selectedRoute];
        _refreshRecommendedStations(route);
        final isWide = ResponsiveLayout.isWide(constraints.maxWidth);
        final panelVisible = isWide && widget.controller.desktopPanelOpen;
        _observeResponsiveLayout(
          width: constraints.maxWidth,
          isWide: isWide,
          panelVisible: panelVisible,
        );
        if (!isWide) _scheduleDashboardMeasurement();

        final safePadding = MediaQuery.paddingOf(context);
        final routeFitPadding = _routeFitPadding(
          viewportHeight: constraints.maxHeight,
          safePadding: safePadding,
          isWide: isWide,
          panelVisible: panelVisible,
        );
        final accessOrigin = widget.controller.rentalAccessOrigin;
        final rentalStart = widget.controller.rentalStationStart;
        final accessDistance = accessOrigin == null || rentalStart == null
            ? null
            : const Distance().as(
                LengthUnit.Meter,
                accessOrigin.position,
                rentalStart.position,
              );

        if (!isWide) {
          return Scaffold(
            body: _buildMapArea(
              route: route,
              fitPadding: routeFitPadding,
              safePadding: safePadding,
              isWide: false,
              showCollapsedBackButton: false,
              accessOrigin: accessOrigin,
              rentalStart: rentalStart,
              accessDistance: accessDistance,
              includeMobileDashboard: true,
            ),
          );
        }

        return Scaffold(
          body: ResponsiveMapShell(
            panelOpen: panelVisible,
            onTogglePanel: _toggleDesktopPanel,
            onMapLayoutChanged: _fitEntireRoute,
            layoutToken: widget.controller.selectedRoute,
            panel: SafeArea(child: _buildDesktopPanel(route)),
            overlayOpen: _desktopSearchOpen,
            onDismissOverlay: _closeDesktopSearch,
            overlayPanel: DesktopRouteSearchPanel(
              key: ValueKey(
                'desktop-result-search-session-$_desktopSearchSession',
              ),
              initialStart: widget.controller.start,
              initialDestination: widget.controller.destination,
              initialTarget: _desktopSearchTarget,
              active: _desktopSearchOpen,
              recentPlaces: widget.controller.recentPlaces,
              onClose: _closeDesktopSearch,
              onDraftChanged: _updateDesktopPreview,
              onSubmit: _submitDesktopDraft,
            ),
            map: _buildMapArea(
              route: route,
              fitPadding: routeFitPadding,
              safePadding: safePadding,
              isWide: true,
              showCollapsedBackButton: !panelVisible,
              accessOrigin: accessOrigin,
              rentalStart: rentalStart,
              accessDistance: accessDistance,
              includeMobileDashboard: false,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapArea({
    required RouteResult route,
    required EdgeInsets fitPadding,
    required EdgeInsets safePadding,
    required bool isWide,
    required bool showCollapsedBackButton,
    required Place? accessOrigin,
    required Place? rentalStart,
    required double? accessDistance,
    required bool includeMobileDashboard,
  }) {
    final topBase = safePadding.top;
    return Stack(
      key: _mapAreaKey,
      children: [
        Positioned.fill(
          child: RouteMap(
            controller: _routeMapController,
            start:
                (_desktopSearchOpen ? _previewStart?.position : null) ??
                widget.controller.start!.position,
            destination:
                (_desktopSearchOpen ? _previewDestination?.position : null) ??
                widget.controller.destination!.position,
            route: route,
            accessStart: accessOrigin?.position,
            accessEnd: rentalStart?.position,
            rentalStations: _recommendedStations,
            showRentalStations: _showRentalStations,
            onRentalStationTap: _showStationDetails,
            fitPadding: fitPadding,
            maxRouteZoom: 15.5,
          ),
        ),
        if (!isWide)
          Positioned(
            top: 12 + topBase,
            left: 12,
            right: 12,
            child: KeyedSubtree(
              key: _mobileHeaderKey,
              child: _buildMobileRouteHeader(),
            ),
          )
        else if (showCollapsedBackButton)
          Positioned(
            top: 12 + topBase,
            left: 40,
            child: IconButton.filled(
              key: const ValueKey('route-back-button'),
              onPressed: () => widget.controller.show(AppScreen.home),
              icon: const Icon(Icons.arrow_back),
              tooltip: '메인으로',
            ),
          ),
        Positioned(
          top: (isWide ? 12 : 68) + topBase,
          right: 12,
          child: KeyedSubtree(
            key: _rentalToggleKey,
            child: FilterChip(
              key: const ValueKey('rental-station-toggle'),
              selected: _showRentalStations,
              onSelected: _toggleRentalStations,
              avatar: const Icon(Icons.pedal_bike, size: 18),
              label: const Text('타슈'),
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFFEAF7F0),
              side: BorderSide(
                color: _showRentalStations
                    ? const Color(0xFF20A464)
                    : AppColors.border,
              ),
            ),
          ),
        ),
        Positioned(
          top: (isWide ? 68 : 124) + topBase,
          right: 12,
          child: KeyedSubtree(
            key: _mapControlsKey,
            child: MapFloatingControls(
              focusMode: _mapFocusMode,
              onCurrentLocation: _moveToCurrentOrRouteStart,
              onFitRoute: _fitEntireRoute,
              onToggleFocusMode: _toggleMapFocusMode,
            ),
          ),
        ),
        if (_showRentalStations &&
            (_loadingStations ||
                _stationError != null ||
                (!_loadingStations && _recommendedStations.isEmpty)))
          Positioned(
            top: (isWide ? 64 : 120) + topBase,
            right: 68,
            child: _StationLoadState(
              loading: _loadingStations,
              error: _stationError,
              empty:
                  !_loadingStations &&
                  _stationError == null &&
                  _recommendedStations.isEmpty,
              onRetry: _loadRentalStations,
            ),
          ),
        if (_showRentalStations &&
            !_loadingStations &&
            _stationError == null &&
            _recommendedStations.isNotEmpty)
          Positioned(
            top: (isWide ? 64 : 120) + topBase,
            right: 68,
            child: _RentalRecommendationBadge(
              count: _recommendedStations.length,
            ),
          ),
        if (accessDistance != null)
          Positioned(
            top: (isWide ? 68 : 120) + topBase,
            left: isWide && showCollapsedBackButton ? 40 : 12,
            child: Material(
              key: const ValueKey('rental-access-distance'),
              color: Colors.white,
              elevation: 2,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.directions_walk,
                      size: 17,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '대여소 접근 거리 약 ${formatDistance(accessDistance)}',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (includeMobileDashboard) _buildMobileDashboard(route, safePadding),
      ],
    );
  }

  Widget _buildMobileRouteHeader() => Row(
    children: [
      IconButton.filled(
        key: const ValueKey('route-back-button'),
        onPressed: () => widget.controller.show(AppScreen.home),
        icon: const Icon(Icons.arrow_back),
        tooltip: '메인으로',
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 3,
          shadowColor: Colors.black26,
          child: InkWell(
            key: const ValueKey('route-summary-pill'),
            onTap: () => widget.controller.editRoute(),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.controller.start!.name} → '
                      '${widget.controller.destination!.name}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildDesktopPanel(RouteResult route) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 8),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('route-back-button'),
              onPressed: () => widget.controller.show(AppScreen.home),
              icon: const Icon(Icons.arrow_back),
              tooltip: '메인으로',
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                '경로 정보',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Material(
          color: const Color(0xFFF4F4F6),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Column(
                  children: [
                    Icon(Icons.circle_outlined, size: 17, color: AppColors.ink),
                    SizedBox(height: 5),
                    SizedBox(
                      height: 18,
                      child: VerticalDivider(width: 1, color: AppColors.muted),
                    ),
                    SizedBox(height: 5),
                    Icon(Icons.location_on, size: 19, color: AppColors.brand),
                  ],
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        key: const ValueKey('desktop-edit-start'),
                        onTap: () =>
                            _openDesktopSearch(RouteSearchTarget.start),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Text(
                            widget.controller.start!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 10),
                      InkWell(
                        key: const ValueKey('desktop-edit-destination'),
                        onTap: () =>
                            _openDesktopSearch(RouteSearchTarget.destination),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Text(
                            widget.controller.destination!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('desktop-route-search'),
                  onPressed: () =>
                      _openDesktopSearch(RouteSearchTarget.destination),
                  tooltip: '출발지와 도착지 수정',
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 19,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: _buildRouteDetails(route, desktop: true),
        ),
      ),
    ],
  );

  Widget _buildMobileDashboard(RouteResult route, EdgeInsets safePadding) =>
      Positioned(
        left: 12,
        right: 12,
        bottom: 12 + safePadding.bottom,
        child: Container(
          key: _dashboardKey,
          constraints: BoxConstraints(maxHeight: _mapFocusMode ? 72 : 390),
          padding: EdgeInsets.all(_mapFocusMode ? 12 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18)],
          ),
          child: _mapFocusMode
              ? InkWell(
                  key: const ValueKey('map-focus-summary'),
                  onTap: _toggleMapFocusMode,
                  borderRadius: BorderRadius.circular(14),
                  child: Row(
                    children: [
                      const Icon(Icons.route_outlined, color: AppColors.safe),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              route.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${formatDistance(route.distanceMeters)} · '
                              '${formatDuration(route.durationMillis)}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: _buildRouteDetails(route, desktop: false),
                ),
        ),
      );

  Widget _buildRouteDetails(RouteResult route, {required bool desktop}) {
    final reason = RouteRecommendationReasonBuilder.build(
      selected: route,
      candidates: widget.controller.routes,
      isRecommended: widget.controller.selectedRoute == 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                route.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFDEDEC),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _routeTypeLabel(widget.controller.selectedRoute),
                style: const TextStyle(
                  color: AppColors.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (widget.controller.routes.length > 1) ...[
          const SizedBox(height: 12),
          Text('경로 선택', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildRouteSelector(desktop),
        ],
        const SizedBox(height: 14),
        _buildMetrics(route),

        const SizedBox(height: 16),
        RouteRecommendationReasonCard(
          reason: reason,
          isRecommended: widget.controller.selectedRoute == 0,
        ),
        if (route.hasDetailedAnalysis && route.hazards.isNotEmpty) ...[
          const Divider(height: 28),
          Text('상세 위험 정보', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...route.hazards.map(
            (hazard) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const CircleAvatar(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                child: Icon(Icons.priority_high),
              ),
              title: Text(hazard.title),
              subtitle: Text(hazard.description),
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton(
          key: const ValueKey('search-again-button'),
          onPressed: desktop
              ? () => _openDesktopSearch(RouteSearchTarget.destination)
              : () => widget.controller.editRoute(),
          child: const Text('다시 검색하기'),
        ),
      ],
    );
  }

  String _routeTypeLabel(int index) {
    if (index == 0) return '후보 중 추천';
    final routes = widget.controller.routes;
    if (routes.isNotEmpty) {
      final shortest = routes.reduce(
        (a, b) => a.distanceMeters <= b.distanceMeters ? a : b,
      );
      if (identical(routes[index], shortest)) return '최단';
    }
    return '대안';
  }

  Widget _buildRouteSelector(bool desktop) {
    final routes = widget.controller.routes;
    if (desktop) {
      return Column(
        children: [
          for (final (index, item) in routes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: index == widget.controller.selectedRoute
                    ? const Color(0xFFFDEDEC)
                    : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey('route-option-$index'),
                  onTap: () => _selectRoute(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          index == widget.controller.selectedRoute
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: index == widget.controller.selectedRoute
                              ? AppColors.brand
                              : AppColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _routeTypeLabel(index),
                          style: TextStyle(
                            color: index == 0
                                ? AppColors.brand
                                : AppColors.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatDistance(item.distanceMeters),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return MobileRouteSelector(
      itemCount: routes.length,
      selectedIndex: widget.controller.selectedRoute,
      onSelected: _selectRoute,
    );
  }

  Widget _buildMetrics(RouteResult route) {
    final metrics = [
      _MetricData('안전점수', '${route.safetyScore.round()}점', AppColors.safe),
      _MetricData('거리', formatDistance(route.distanceMeters)),
      _MetricData('예상 시간', formatDuration(route.durationMillis)),
      _MetricData('자전거도로 비율', '${(route.bikeInfraRatio * 100).round()}%'),
    ];
    return Row(
      key: const ValueKey('route-summary-metrics'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final metric in metrics)
          Expanded(child: _metric(metric.label, metric.value, metric.color)),
      ],
    );
  }

  Widget _metric(String label, String value, [Color color = AppColors.ink]) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      );

  String _count(int? value, String unit) =>
      value == null ? '정보 없음' : '$value$unit';
}

class _MetricData {
  const _MetricData(this.label, this.value, [this.color = AppColors.ink]);

  final String label;
  final String value;
  final Color color;
}

class _StationLoadState extends StatelessWidget {
  const _StationLoadState({
    required this.loading,
    required this.error,
    required this.empty,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 3,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text('타슈 대여소 불러오는 중'),
          ] else if (error != null) ...[
            const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              tooltip: '다시 시도',
              visualDensity: VisualDensity.compact,
            ),
          ] else if (empty) ...[
            const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210),
              child: const Text('경로 주변에 추천 가능한 타슈 대여소가 없습니다', maxLines: 2),
            ),
          ],
        ],
      ),
    ),
  );
}

class _RentalRecommendationBadge extends StatelessWidget {
  const _RentalRecommendationBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('rental-recommendation-badge'),
    color: Colors.white,
    elevation: 2,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '경로 주변 타슈 $count개',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Text(
            '500m 이내 추천 대여소',
            style: TextStyle(color: AppColors.muted, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _StationStatusBadge extends StatelessWidget {
  const _StationStatusBadge({required this.status});

  final RentalStationStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      RentalStationStatus.available => (const Color(0xFF20A464), '대여 가능'),
      RentalStationStatus.lowAvailability => (const Color(0xFFF5B700), '수량 부족'),
      RentalStationStatus.unavailable => (const Color(0xFFD94A45), '대여 불가'),
      RentalStationStatus.unknown => (const Color(0xFF8C8C94), '정보 없음'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StationDetailRow extends StatelessWidget {
  const _StationDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
