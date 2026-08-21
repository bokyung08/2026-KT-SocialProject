import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../app_controller.dart';
import '../data/sample_places.dart';
import '../models/place.dart';
import '../models/route_result.dart';
import '../screens/home_screen.dart';
import '../screens/info_screen.dart';
import '../screens/loading_screen.dart';
import 'desktop_route_search_panel.dart';
import 'responsive_map_shell.dart';
import 'route_map.dart';

class DesktopAppShell extends StatefulWidget {
  const DesktopAppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<DesktopAppShell> createState() => _DesktopAppShellState();
}

class _DesktopAppShellState extends State<DesktopAppShell> {
  late final RouteMapController _mapController;
  bool _searchOpen = false;
  int _searchSession = 0;
  RouteSearchTarget _searchTarget = RouteSearchTarget.start;
  Place? _searchInitialStart;
  Place? _searchInitialDestination;
  Place? _previewStart;
  Place? _previewDestination;
  LatLng? _mapTapPoint;
  int _mapTapSession = 0;

  @override
  void initState() {
    super.initState();
    _mapController = RouteMapController();
    if (widget.controller.screen == AppScreen.input) {
      _searchOpen = true;
      _searchTarget = widget.controller.routeSearchTarget;
      _searchInitialStart = widget.controller.start;
      _searchInitialDestination = widget.controller.destination;
      _previewStart = widget.controller.start;
      _previewDestination = widget.controller.destination;
    }
  }

  RouteResult? get _selectedRoute {
    final controller = widget.controller;
    if (controller.routes.isEmpty ||
        controller.selectedRoute < 0 ||
        controller.selectedRoute >= controller.routes.length) {
      return null;
    }
    return controller.routes[controller.selectedRoute];
  }

  void _openSearch({
    required RouteSearchTarget target,
    required Place? start,
    required Place? destination,
  }) {
    setState(() {
      _searchSession++;
      _searchOpen = true;
      _searchTarget = target;
      _searchInitialStart = start;
      _searchInitialDestination = destination;
      _previewStart = start;
      _previewDestination = destination;
    });
    widget.controller.setDesktopPanelOpen(true);
  }

  void _openNewRoute() => _openSearch(
    target: RouteSearchTarget.start,
    start: null,
    destination: null,
  );

  void _closeSearch() {
    widget.controller.cancelDraftAnalysis();
    setState(() {
      _searchOpen = false;
      _previewStart = null;
      _previewDestination = null;
    });
    if (widget.controller.screen == AppScreen.input) {
      widget.controller.show(AppScreen.home);
    }
  }

  void _togglePrimaryPanel() {
    if (_searchOpen) _closeSearch();
    widget.controller.toggleDesktopPanel();
  }

  Future<String?> _submitDraft(Place start, Place destination) async {
    final error = await widget.controller.analyzeDraft(start, destination);
    if (!mounted) return error;
    if (error != null) {
      setState(() {
        _previewStart = widget.controller.start;
        _previewDestination = widget.controller.destination;
      });
      return error;
    }
    setState(() => _searchOpen = false);
    return null;
  }

  void _updatePreview(Place? start, Place? destination) {
    setState(() {
      _previewStart = start;
      _previewDestination = destination;
    });
  }

  void _handleMapTap(LatLng point) {
    if (!_searchOpen) return;
    setState(() {
      _mapTapPoint = point;
      _mapTapSession++;
    });
  }

  Widget _panel() => switch (widget.controller.screen) {
    AppScreen.home || AppScreen.input => HomeScreen(
      key: const ValueKey('desktop-home-content'),
      controller: widget.controller,
      desktopPanel: true,
      onDesktopNewRoute: _openNewRoute,
    ),
    AppScreen.loading => LoadingScreen(
      key: const ValueKey('desktop-loading-content'),
      controller: widget.controller,
    ),
    AppScreen.info => InfoScreen(
      key: const ValueKey('desktop-info-content'),
      controller: widget.controller,
      desktopPanel: true,
    ),
    AppScreen.result => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final showDefaultPlaces =
        (controller.screen == AppScreen.home ||
            controller.screen == AppScreen.info ||
            controller.screen == AppScreen.input) &&
        controller.start == null &&
        controller.destination == null;
    final appliedStart =
        controller.start?.position ??
        (showDefaultPlaces ? samplePlaces[0].position : null);
    final appliedDestination =
        controller.destination?.position ??
        (showDefaultPlaces ? samplePlaces[1].position : null);
    final start =
        (_searchOpen ? _previewStart?.position : null) ?? appliedStart;
    final destination =
        (_searchOpen ? _previewDestination?.position : null) ??
        appliedDestination;

    return ResponsiveMapShell(
      key: const ValueKey('desktop-app-shell'),
      panelOpen: controller.desktopPanelOpen,
      onTogglePanel: _togglePrimaryPanel,
      onMapLayoutChanged: _mapController.fitRoute,
      layoutToken: controller.screen,
      overlayOpen: _searchOpen,
      overlayPanel: DesktopRouteSearchPanel(
        key: ValueKey('desktop-search-session-$_searchSession'),
        initialStart: _searchInitialStart,
        initialDestination: _searchInitialDestination,
        initialTarget: _searchTarget,
        active: _searchOpen,
        recentPlaces: controller.recentPlaces,
        onClose: _closeSearch,
        onDraftChanged: _updatePreview,
        onSubmit: _submitDraft,
        mapTapPoint: _mapTapPoint,
        mapTapSession: _mapTapSession,
      ),
      panel: SafeArea(child: _panel()),
      map: RouteMap(
        key: const ValueKey('desktop-persistent-map'),
        controller: _mapController,
        start: start,
        destination: destination,
        route: _selectedRoute,
        fitPadding: const EdgeInsets.fromLTRB(52, 76, 76, 58),
        maxRouteZoom: 15.5,
        onMapTap: _searchOpen ? _handleMapTap : null,
      ),
    );
  }
}
