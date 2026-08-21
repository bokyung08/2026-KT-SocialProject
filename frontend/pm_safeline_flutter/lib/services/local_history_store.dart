import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_route.dart';
import '../models/place.dart';

/// 브라우저(기기) 로컬 저장소에 최근 검색 경로·즐겨찾기를 보관한다.
class LocalHistoryStore {
  static const _recentStartKey = 'pm_safeline.recent_start';
  static const _recentDestinationKey = 'pm_safeline.recent_destination';
  static const _recentPlacesKey = 'pm_safeline.recent_places';
  static const _favoritesKey = 'pm_safeline.favorite_routes';

  Future<Place?> loadRecentStart() => _loadPlace(_recentStartKey);
  Future<Place?> loadRecentDestination() => _loadPlace(_recentDestinationKey);

  Future<void> saveRecentRoute(Place? start, Place? destination) async {
    final prefs = await SharedPreferences.getInstance();
    await _savePlace(prefs, _recentStartKey, start);
    await _savePlace(prefs, _recentDestinationKey, destination);
  }

  Future<List<Place>> loadRecentPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentPlacesKey);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Place.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> saveRecentPlaces(List<Place> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentPlacesKey,
      jsonEncode(places.map((place) => place.toJson()).toList()),
    );
  }

  Future<List<FavoriteRoute>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => FavoriteRoute.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> saveFavorites(List<FavoriteRoute> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _favoritesKey,
      jsonEncode(favorites.map((route) => route.toJson()).toList()),
    );
  }

  Future<Place?> _loadPlace(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return Place.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePlace(
    SharedPreferences prefs,
    String key,
    Place? place,
  ) async {
    if (place == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(place.toJson()));
    }
  }
}
