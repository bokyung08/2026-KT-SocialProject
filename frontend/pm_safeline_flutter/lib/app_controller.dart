import 'package:flutter/foundation.dart';

import 'config/api_config.dart';
import 'data/sample_places.dart';
import 'models/favorite_route.dart';
import 'models/place.dart';
import 'models/route_result.dart';
import 'repositories/api_route_repository.dart';
import 'repositories/mock_route_repository.dart';
import 'repositories/route_repository.dart';
import 'services/local_history_store.dart';

enum AppScreen { home, input, loading, result, info }

enum RouteSearchTarget { start, destination }

class AppController extends ChangeNotifier {
  AppController({RouteRepository? repository, LocalHistoryStore? historyStore})
    : repository =
          repository ??
          (ApiConfig.useMock
              ? MockRouteRepository()
              : ApiRouteRepository(ApiConfig.baseUrl)),
      historyStore = historyStore ?? LocalHistoryStore();

  static const _minimumAnalysisDuration = Duration(milliseconds: 900);
  static const _completedStageHold = Duration(milliseconds: 220);

  final RouteRepository repository;
  final LocalHistoryStore historyStore;
  AppScreen screen = AppScreen.home;
  Place? start;
  Place? destination;
  Place? recentRouteStart;
  Place? recentRouteDestination;
  Place? rentalAccessOrigin;
  Place? rentalStationStart;
  final List<Place> recentPlaces = [];
  final List<FavoriteRoute> favorites = [];
  bool historyLoaded = false;
  List<RouteResult> routes = const [];
  int selectedRoute = 0;
  String? error;
  bool analysisResponseReady = false;
  bool desktopPanelOpen = true;
  RouteSearchTarget routeSearchTarget = RouteSearchTarget.start;

  int _analysisGeneration = 0;
  bool _disposed = false;

  bool get canAnalyze => start != null && destination != null;

  Future<void> loadPersisted() async {
    final loadedStart = await historyStore.loadRecentStart();
    final loadedDestination = await historyStore.loadRecentDestination();
    final loadedPlaces = await historyStore.loadRecentPlaces();
    final loadedFavorites = await historyStore.loadFavorites();
    if (_disposed) return;
    recentRouteStart = loadedStart;
    recentRouteDestination = loadedDestination;
    recentPlaces
      ..clear()
      ..addAll(loadedPlaces);
    favorites
      ..clear()
      ..addAll(loadedFavorites);
    historyLoaded = true;
    notifyListeners();
  }

  bool isFavorite(Place start, Place destination) => favorites.any(
    (route) => route.id == FavoriteRoute.idFor(start, destination),
  );

  void toggleFavorite(Place start, Place destination) {
    final id = FavoriteRoute.idFor(start, destination);
    final existingIndex = favorites.indexWhere((route) => route.id == id);
    if (existingIndex >= 0) {
      favorites.removeAt(existingIndex);
    } else {
      favorites.insert(0, FavoriteRoute(id: id, start: start, destination: destination));
    }
    historyStore.saveFavorites(favorites);
    notifyListeners();
  }

  void removeFavorite(String id) {
    favorites.removeWhere((route) => route.id == id);
    historyStore.saveFavorites(favorites);
    notifyListeners();
  }

  void useFavorite(FavoriteRoute route) {
    start = route.start;
    destination = route.destination;
    _clearRentalAccess();
    notifyListeners();
  }

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

  bool get hasRecentRoute =>
      recentRouteStart != null && recentRouteDestination != null;

  void useRecentRoute() {
    if (!hasRecentRoute) return;
    start = recentRouteStart;
    destination = recentRouteDestination;
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

  void setDesktopPanelOpen(bool value) {
    if (desktopPanelOpen == value) return;
    desktopPanelOpen = value;
    notifyListeners();
  }

  void toggleDesktopPanel() => setDesktopPanelOpen(!desktopPanelOpen);

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
    historyStore.saveRecentPlaces(recentPlaces);
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
    historyStore.saveRecentRoute(recentRouteStart, recentRouteDestination);
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

  Future<String?> analyzeDraft(Place draftStart, Place draftDestination) async {
    final generation = ++_analysisGeneration;
    try {
      final nextRoutes = await repository.findRoutes(
        draftStart,
        draftDestination,
      );
      if (!_isCurrentAnalysis(generation)) return '경로 요청이 취소되었습니다.';

      start = draftStart;
      destination = draftDestination;
      recentRouteStart = draftStart;
      recentRouteDestination = draftDestination;
      historyStore.saveRecentRoute(draftStart, draftDestination);
      _clearRentalAccess();
      _remember(draftStart);
      _remember(draftDestination);
      routes = nextRoutes;
      selectedRoute = 0;
      analysisResponseReady = false;
      error = null;
      screen = AppScreen.result;
      notifyListeners();
      return null;
    } on RouteRepositoryException catch (exception) {
      if (!_isCurrentAnalysis(generation)) return '경로 요청이 취소되었습니다.';
      return exception.message;
    } catch (_) {
      if (!_isCurrentAnalysis(generation)) return '경로 요청이 취소되었습니다.';
      return '경로를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }

  void cancelDraftAnalysis() {
    _analysisGeneration++;
  }

  @override
  void dispose() {
    _disposed = true;
    _analysisGeneration++;
    super.dispose();
  }
}
