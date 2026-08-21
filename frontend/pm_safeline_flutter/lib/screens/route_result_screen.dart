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
  double? _dashboardDragHeight;
  bool _legendExpanded = false;
  bool _desktopSearchOpen = false;
  int _desktopSearchSession = 0;
  RouteSearchTarget _desktopSearchTarget = RouteSearchTarget.destination;
  Place? _previewStart;
  Place? _previewDestination;
  LatLng? _mapTapPoint;
  int _mapTapSession = 0;
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
    final isWide = ResponsiveLayout.isWide(MediaQuery.sizeOf(context).width);
    setState(() {
      _mapFocusMode = !_mapFocusMode;
      if (isWide) widget.controller.setDesktopPanelOpen(!_mapFocusMode);
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

  void _handleDesktopMapTap(LatLng point) {
    if (!_desktopSearchOpen) return;
    setState(() {
      _mapTapPoint = point;
      _mapTapSession++;
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

    // LayoutBuilder는 쓰지 않는다: 그 builder 콜백은 레이아웃 단계에서만
    // 재실행되는데, 화면 지오메트리(가로/세로 크기)가 안 바뀐 채로 하위
    // 위젯의 prop만 바뀌면(예: 지도 탭 좌표) 프레임워크가 "다시 레이아웃할
    // 필요 없음"으로 보고 콜백을 건너뛰어, 그 안에서 만들어지는 검색
    // 오버레이가 새 상태를 못 받는 문제가 있었다. MediaQuery는 일반 빌드
    // 경로를 타므로 setState가 있을 때마다 항상 다시 계산된다.
    {
      final size = MediaQuery.sizeOf(context);
      final route = widget.controller.routes[widget.controller.selectedRoute];
      _refreshRecommendedStations(route);
      final isWide = ResponsiveLayout.isWide(size.width);
      final panelVisible = isWide && widget.controller.desktopPanelOpen;
      _observeResponsiveLayout(
        width: size.width,
        isWide: isWide,
        panelVisible: panelVisible,
      );
      if (!isWide) _scheduleDashboardMeasurement();

      final safePadding = MediaQuery.paddingOf(context);
      final routeFitPadding = _routeFitPadding(
        viewportHeight: size.height,
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
            mapTapPoint: _mapTapPoint,
            mapTapSession: _mapTapSession,
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
    }
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
            key: const ValueKey('result-persistent-map'),
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
            onMapTap: isWide && _desktopSearchOpen
                ? _handleDesktopMapTap
                : null,
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
            left: 12,
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
            left: 12,
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

  // 상단 바 높이는 항상 이 값으로 고정한다. 예전엔 pill 안의 즐겨찾기
  // IconButton 이 M3 기본 최소 크기 40 을 요구해서, 세로 패딩 11*2 까지
  // 더해져 바가 62px 로 부풀었다(모바일 전용 위젯이라 PC 에선 안 보였다).
  static const _mobileHeaderHeight = 44.0;

  Widget _buildMobileRouteHeader() => SizedBox(
    height: _mobileHeaderHeight,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox.square(
          dimension: _mobileHeaderHeight,
          child: IconButton.filled(
            key: const ValueKey('route-back-button'),
            padding: EdgeInsets.zero,
            onPressed: () => widget.controller.show(AppScreen.home),
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: '메인으로',
          ),
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
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.controller.start!.name} → '
                        '${widget.controller.destination!.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 10),
                    _favoriteButton(color: AppColors.muted, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _favoriteButton({Color color = Colors.black, double size = 24}) {
    final start = widget.controller.start;
    final destination = widget.controller.destination;
    if (start == null || destination == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('toggle-favorite-route'),
      tooltip: '즐겨찾기',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      onPressed: () => widget.controller.toggleFavorite(start, destination),
      icon: Icon(
        widget.controller.isFavorite(start, destination)
            ? Icons.star
            : Icons.star_border,
        color: color,
        size: size,
      ),
    );
  }

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
            _favoriteButton(),
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
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.circle_outlined,
                            size: 17,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Container(width: 1, height: 10, color: AppColors.muted),
                      Expanded(
                        child: Align(
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.location_on,
                            size: 19,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
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
                          onTap: () => _openDesktopSearch(
                            RouteSearchTarget.destination,
                          ),
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
      ),
      const Divider(height: 1),
      Expanded(child: _buildRouteDetails(route, desktop: true)),
    ],
  );

  Widget _buildMobileDashboard(RouteResult route, EdgeInsets safePadding) =>
      Positioned(
        left: 12,
        right: 12,
        bottom: 12 + safePadding.bottom,
        child: AnimatedContainer(
          key: _dashboardKey,
          duration: _dashboardDragHeight != null
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(
            maxHeight: _dashboardDragHeight ?? (_mapFocusMode ? 88 : 390),
          ),
          // 펼친 상태에선 첫 줄이 드래그 핸들이라 위쪽 여백을 핸들이 대신한다.
          padding: _mapFocusMode
              ? const EdgeInsets.all(12)
              : const EdgeInsets.fromLTRB(16, 4, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _mapFocusMode
                    ? InkWell(
                        key: const ValueKey('map-focus-summary'),
                        onTap: _toggleMapFocusMode,
                        borderRadius: BorderRadius.circular(14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.route_outlined,
                              color: AppColors.safe,
                            ),
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
                    : _buildRouteDetails(route, desktop: false),
              ),
            ],
          ),
        ),
      );

  static const _dashboardCollapsedHeight = 88.0;
  static const _dashboardExpandedHeight = 390.0;

  Widget _dashboardDragHandle() => GestureDetector(
    key: const ValueKey('mobile-dashboard-handle'),
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: (_) {
      setState(() {
        _dashboardDragHeight = _mapFocusMode
            ? _dashboardCollapsedHeight
            : _dashboardExpandedHeight;
      });
    },
    onVerticalDragUpdate: (details) {
      setState(() {
        _dashboardDragHeight = (_dashboardDragHeight! - details.delta.dy)
            .clamp(_dashboardCollapsedHeight, _dashboardExpandedHeight);
      });
    },
    onVerticalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      final currentHeight =
          _dashboardDragHeight ??
          (_mapFocusMode ? _dashboardCollapsedHeight : _dashboardExpandedHeight);
      final collapse = velocity.abs() > 200
          ? velocity > 0
          : currentHeight <
                (_dashboardCollapsedHeight + _dashboardExpandedHeight) / 2;
      setState(() {
        _mapFocusMode = collapse;
        _dashboardDragHeight = null;
      });
      _scheduleMapRefit();
    },
    onVerticalDragCancel: () {
      setState(() => _dashboardDragHeight = null);
    },
    // 이제 타이틀 Row 위에 별도 줄로 놓이므로, 높이가 그대로 카드 상단
    // 여백이 된다. 드래그 타깃은 유지하면서 내용이 밀리지 않게 낮춘다.
    child: const SizedBox(
      width: 56,
      height: 26,
      child: Center(
        child: SizedBox(
          width: 36,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildRouteDetails(RouteResult route, {required bool desktop}) {
    final reason = RouteRecommendationReasonBuilder.build(
      selected: route,
      candidates: widget.controller.routes,
      isRecommended: widget.controller.selectedRoute == 0,
    );
    final button = FilledButton(
      key: const ValueKey('search-again-button'),
      onPressed: desktop
          ? () => _openDesktopSearch(RouteSearchTarget.destination)
          : () => widget.controller.editRoute(),
      child: const Text('다시 검색하기'),
    );

    if (!desktop) {
      // 모바일은 고정 높이 컨테이너 안에서 버튼이 바닥에 눌리는 게 아니라,
      // 내용 길이만큼만 차지하고 버튼이 바로 뒤에 붙어야 한다(경로마다
      // 위험 정보 유무 등으로 내용 길이가 달라 억지로 통일할 필요 없음).
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRouteDetailsContent(route, reason, desktop: false),
            const SizedBox(height: 14),
            button,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: _buildRouteDetailsContent(route, reason, desktop: true),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: button,
        ),
      ],
    );
  }

  Widget _buildRouteDetailsContent(
    RouteResult route,
    RouteRecommendationReason reason, {
    required bool desktop,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 핸들은 타이틀/배지 Row 위(세로로 맨 위)에 별도 줄로 놓는다. Row 에
        // Stack 으로 겹쳐두면 Stack 높이를 핸들이 결정해버려 정렬을 바꿔도
        // 바가 움직이지 않았다. Column 이 카드 폭 전체를 차지하므로 Center
        // 만으로 카드 기준 정확한 가로 중앙이 된다.
        if (!desktop)
          Align(alignment: Alignment.topCenter, child: _dashboardDragHandle()),
        Row(
          children: [
            Expanded(
              child: Text(
                route.name,
                overflow: TextOverflow.ellipsis,
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
          _buildRouteSelector(desktop),
        ],
        const SizedBox(height: 14),
        _buildMetrics(route),
        if (_legendExpanded) ...[
          const SizedBox(height: 10),
          const Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                _LegendItem(AppColors.safe, '안전'),
                _LegendItem(AppColors.caution, '주의'),
                _LegendItem(AppColors.danger, '위험'),
              ],
            ),
          ),
        ],
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
        for (final (index, metric) in metrics.indexed)
          Expanded(
            child: index == 0
                ? _metricWithTap(
                    metric.label,
                    metric.value,
                    metric.color,
                    () => setState(() => _legendExpanded = !_legendExpanded),
                  )
                : _metric(metric.label, metric.value, metric.color),
          ),
      ],
    );
  }

  Widget _metric(
    String label,
    String value, [
    Color color = AppColors.ink,
  ]) => _metricWithTap(label, value, color, null);

  Widget _metricWithTap(
    String label,
    String value,
    Color color,
    VoidCallback? onTap,
  ) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 좁은 화면에선 '예상 시간' 값이 칸보다 길어져 Row 가 넘쳤다.
            // 칸 안에서 줄어들 수 있게 Flexible 로 감싼다.
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                _legendExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: AppColors.muted,
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      key: const ValueKey('toggle-safety-legend'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: content,
    );
  }

  String _count(int? value, String unit) =>
      value == null ? '정보 없음' : '$value$unit';
}

class _MetricData {
  const _MetricData(this.label, this.value, [this.color = AppColors.ink]);

  final String label;
  final String value;
  final Color color;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(9),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
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
