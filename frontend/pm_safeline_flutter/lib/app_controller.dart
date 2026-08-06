import 'package:flutter/foundation.dart';

import 'config/api_config.dart';
import 'data/sample_places.dart';
import 'models/place.dart';
import 'models/route_result.dart';
import 'repositories/api_route_repository.dart';
import 'repositories/mock_route_repository.dart';
import 'repositories/route_repository.dart';

enum AppScreen { home, input, loading, result, info }

enum RouteSearchTarget { start, destination }

class AppController extends ChangeNotifier {
  AppController({RouteRepository? repository})
    : repository =
          repository ??
          (ApiConfig.useMock
              ? MockRouteRepository()
              : ApiRouteRepository(ApiConfig.baseUrl));

  static const _minimumAnalysisDuration = Duration(milliseconds: 900);
  static const _completedStageHold = Duration(milliseconds: 220);

  final RouteRepository repository;
  AppScreen screen = AppScreen.home;
  Place? start;
  Place? destination;
  Place? recentRouteStart;
  Place? recentRouteDestination;
  Place? rentalAccessOrigin;
  Place? rentalStationStart;
  final List<Place> recentPlaces = [];
  List<RouteResult> routes = const [];
  int selectedRoute = 0;
  String? error;
  bool analysisResponseReady = false;
  RouteSearchTarget routeSearchTarget = RouteSearchTarget.start;

  int _analysisGeneration = 0;
  bool _disposed = false;

  bool get canAnalyze => start != null && destination != null;

  void show(AppScreen value) {
    if (screen == AppScreen.loading && value != AppScreen.loading) {
      _analysisGeneration++;
      analysisResponseReady = false;
    }
    screen = value;
    error = null;
    notifyListeners();
  }

  void setStart(Place value) {
    start = value;
    _clearRentalAccess();
    _remember(value);
    routes = const [];
    error = null;
    notifyListeners();
  }

  void setRentalStationStart(Place value) {
    rentalAccessOrigin = start;
    rentalStationStart = value;
    start = value;
    _remember(value);
    routes = const [];
    error = null;
    notifyListeners();
  }

  void setDestination(Place value) {
    destination = value;
    _remember(value);
    routes = const [];
    error = null;
    notifyListeners();
  }

  void clearStart() {
    start = null;
    _clearRentalAccess();
    routes = const [];
    notifyListeners();
  }

  void clearDestination() {
    destination = null;
    routes = const [];
    notifyListeners();
  }

  void swap() {
    final old = start;
    start = destination;
    destination = old;
    _clearRentalAccess();
    routes = const [];
    notifyListeners();
  }

  void useExample() {
    start = samplePlaces.first;
    destination = samplePlaces[1];
    _clearRentalAccess();
    notifyListeners();
  }

  void useRecentRoute() {
    start = recentRouteStart ?? samplePlaces.first;
    destination = recentRouteDestination ?? samplePlaces[1];
    _clearRentalAccess();
    notifyListeners();
  }

  void startNewRoute() {
    start = null;
    destination = null;
    _clearRentalAccess();
    routes = const [];
    selectedRoute = 0;
    error = null;
    routeSearchTarget = RouteSearchTarget.start;
    screen = AppScreen.input;
    notifyListeners();
  }

  void editRoute({RouteSearchTarget target = RouteSearchTarget.destination}) {
    routeSearchTarget = target;
    error = null;
    screen = AppScreen.input;
    notifyListeners();
  }

  void selectRoute(int value) {
    selectedRoute = value;
    notifyListeners();
  }

  void cancelAnalysis() {
    if (screen != AppScreen.loading) return;
    _analysisGeneration++;
    analysisResponseReady = false;
    error = null;
    screen = AppScreen.input;
    notifyListeners();
  }

  void _clearRentalAccess() {
    rentalAccessOrigin = null;
    rentalStationStart = null;
  }

  void _remember(Place value) {
    recentPlaces.removeWhere((item) => item.position == value.position);
    recentPlaces.insert(0, value);
    if (recentPlaces.length > 6) recentPlaces.removeLast();
  }

  bool _isCurrentAnalysis(int generation) =>
      !_disposed && generation == _analysisGeneration;

  Future<void> analyze() async {
    if (!canAnalyze) {
      error = '출발지와 도착지를 모두 검색해 선택해 주세요.';
      notifyListeners();
      return;
    }

    final generation = ++_analysisGeneration;
    final startedAt = DateTime.now();
    recentRouteStart = start;
    recentRouteDestination = destination;
    screen = AppScreen.loading;
    analysisResponseReady = false;
    error = null;
    notifyListeners();

    try {
      final nextRoutes = await repository.findRoutes(start!, destination!);
      if (!_isCurrentAnalysis(generation)) return;

      final elapsed = DateTime.now().difference(startedAt);
      final remaining = _minimumAnalysisDuration - elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (!_isCurrentAnalysis(generation)) return;

      analysisResponseReady = true;
      notifyListeners();
      await Future<void>.delayed(_completedStageHold);
      if (!_isCurrentAnalysis(generation)) return;

      routes = nextRoutes;
      selectedRoute = 0;
      analysisResponseReady = false;
      screen = AppScreen.result;
    } on RouteRepositoryException catch (exception) {
      if (!_isCurrentAnalysis(generation)) return;
      analysisResponseReady = false;
      error = exception.message;
      screen = AppScreen.input;
    }
    if (_isCurrentAnalysis(generation)) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _analysisGeneration++;
    super.dispose();
  }
}
