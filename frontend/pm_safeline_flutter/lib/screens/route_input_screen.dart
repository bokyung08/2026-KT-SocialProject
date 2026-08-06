import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/sample_places.dart';
import '../models/place_search_result.dart';
import '../services/geocoding_service.dart';
import '../theme/app_theme.dart';

class RouteInputScreen extends StatefulWidget {
  const RouteInputScreen({
    super.key,
    required this.controller,
    this.geocodingService,
  });
  final AppController controller;
  final GeocodingService? geocodingService;
  @override
  State<RouteInputScreen> createState() => _RouteInputScreenState();
}

class _FieldSearchState {
  Timer? debounce;
  int requestGeneration = 0;
  bool searching = false;
  bool searched = false;
  String? error;
  List<PlaceSearchResult> results = const [];

  void reset() {
    debounce?.cancel();
    requestGeneration++;
    searching = false;
    searched = false;
    error = null;
    results = const [];
  }

  void dispose() => debounce?.cancel();
}

class _RouteInputScreenState extends State<RouteInputScreen> {
  static const _debounceDuration = Duration(milliseconds: 400);
  late final GeocodingService _geocoding;
  late final TextEditingController _startText;
  late final TextEditingController _destinationText;
  late final FocusNode _startFocus;
  late final FocusNode _destinationFocus;
  late _FieldSearchState _startSearch;
  late _FieldSearchState _destinationSearch;
  late bool _editingStart;

  TextEditingController get _activeText =>
      _editingStart ? _startText : _destinationText;
  _FieldSearchState get _activeSearch =>
      _editingStart ? _startSearch : _destinationSearch;

  @override
  void initState() {
    super.initState();
    _geocoding = widget.geocodingService ?? GeocodingService();
    _startText = TextEditingController(
      text: widget.controller.start?.name ?? '',
    );
    _destinationText = TextEditingController(
      text: widget.controller.destination?.name ?? '',
    );
    _startFocus = FocusNode(debugLabel: 'route-start-search');
    _destinationFocus = FocusNode(debugLabel: 'route-destination-search');
    _startSearch = _FieldSearchState();
    _destinationSearch = _FieldSearchState();
    _editingStart =
        widget.controller.routeSearchTarget == RouteSearchTarget.start;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_editingStart ? _startFocus : _destinationFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _startSearch.dispose();
    _destinationSearch.dispose();
    _startText.dispose();
    _destinationText.dispose();
    _startFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  void _activateField(bool start) {
    widget.controller.routeSearchTarget = start
        ? RouteSearchTarget.start
        : RouteSearchTarget.destination;
    if (_editingStart != start) setState(() => _editingStart = start);
    (start ? _startFocus : _destinationFocus).requestFocus();
  }

  void _onQueryChanged({required bool start, required String value}) {
    final field = start ? _startSearch : _destinationSearch;
    final selected = start
        ? widget.controller.start
        : widget.controller.destination;
    field.debounce?.cancel();
    field.requestGeneration++;
    if (selected != null && value != selected.name) {
      if (start) {
        widget.controller.clearStart();
      } else {
        widget.controller.clearDestination();
      }
    }
    final query = value.trim();
    widget.controller.routeSearchTarget = start
        ? RouteSearchTarget.start
        : RouteSearchTarget.destination;
    setState(() {
      _editingStart = start;
      field.searching = false;
      field.searched = false;
      field.error = null;
      field.results = const [];
    });
    if (query.length < 2) return;
    final generation = field.requestGeneration;
    field.debounce = Timer(
      _debounceDuration,
      () => _runSearch(start: start, query: query, generation: generation),
    );
  }

  Future<void> _searchImmediately(bool start) async {
    final field = start ? _startSearch : _destinationSearch;
    final query = (start ? _startText : _destinationText).text.trim();
    field.debounce?.cancel();
    field.requestGeneration++;
    widget.controller.routeSearchTarget = start
        ? RouteSearchTarget.start
        : RouteSearchTarget.destination;
    setState(() => _editingStart = start);
    if (query.length < 2) return;
    await _runSearch(
      start: start,
      query: query,
      generation: field.requestGeneration,
    );
  }

  Future<void> _runSearch({
    required bool start,
    required String query,
    required int generation,
  }) async {
    final field = start ? _startSearch : _destinationSearch;
    final text = start ? _startText : _destinationText;
    if (generation != field.requestGeneration || text.text.trim() != query) {
      return;
    }
    setState(() {
      field.searching = true;
      field.searched = true;
      field.error = null;
      field.results = const [];
    });
    try {
      final results = await _geocoding.search(query);
      if (!mounted ||
          generation != field.requestGeneration ||
          text.text.trim() != query) {
        return;
      }
      setState(() {
        field.results = results;
        field.searching = false;
      });
    } on GeocodingException catch (error) {
      if (!mounted ||
          generation != field.requestGeneration ||
          text.text.trim() != query) {
        return;
      }
      setState(() {
        field.error = error.message;
        field.searching = false;
      });
    }
  }

  void _select(PlaceSearchResult result) {
    final start = _editingStart;
    final field = start ? _startSearch : _destinationSearch;
    field.reset();
    final place = result.toPlace();
    if (start) {
      widget.controller.setStart(place);
      _startText.text = result.displayTitle;
    } else {
      widget.controller.setDestination(place);
      _destinationText.text = result.displayTitle;
    }

    if (widget.controller.start == null) {
      _activateField(true);
    } else if (widget.controller.destination == null) {
      _activateField(false);
    } else {
      widget.controller.routeSearchTarget = start
          ? RouteSearchTarget.start
          : RouteSearchTarget.destination;
      setState(() {});
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _clearField(bool start) {
    final field = start ? _startSearch : _destinationSearch;
    final text = start ? _startText : _destinationText;
    field.reset();
    text.clear();
    if (start) {
      widget.controller.clearStart();
    } else {
      widget.controller.clearDestination();
    }
    _activateField(start);
  }

  void _swap() {
    widget.controller.swap();
    final old = _startText.text;
    _startText.text = _destinationText.text;
    _destinationText.text = old;
    _startSearch.reset();
    _destinationSearch.reset();
    setState(() {});
  }

  void _analyze() {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.controller.analyze();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final active = _activeSearch;
    final activeQuery = _activeText.text.trim();
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFFAFAFB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    key: const ValueKey('route-search-back'),
                    onPressed: () => controller.show(AppScreen.home),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: '뒤로가기',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '출발지와 도착지를 검색하세요',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('route-search-close'),
                    tooltip: '닫기',
                    onPressed: () => controller.show(AppScreen.home),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _searchField(
                key: const ValueKey('start-search-field'),
                label: '출발지',
                controller: _startText,
                focusNode: _startFocus,
                start: true,
                icon: Icons.circle_outlined,
              ),
              const SizedBox(height: 8),
              _searchField(
                key: const ValueKey('destination-search-field'),
                label: '도착지',
                controller: _destinationText,
                focusNode: _destinationFocus,
                start: false,
                icon: Icons.location_on,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('swap-route-fields'),
                  onPressed: _swap,
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('출발·도착 교환'),
                ),
              ),
              Text(
                active.searched || active.searching
                    ? '“$activeQuery” 검색 결과'
                    : activeQuery.isEmpty
                    ? '최근 검색 · 추천 장소'
                    : '2글자 이상 입력하면 자동으로 검색해요',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: _resultList(active, activeQuery)),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    controller.error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              if (!keyboardVisible) ...[
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('analyze-route-button'),
                  onPressed: controller.canAnalyze ? _analyze : null,
                  child: Text(
                    controller.canAnalyze ? '경로 탐색' : '출발지와 도착지를 선택해 주세요',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField({
    Key? key,
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool start,
    required IconData icon,
  }) {
    final active = _editingStart == start;
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      keyboardAppearance: Brightness.light,
      scrollPadding: const EdgeInsets.only(bottom: 120),
      onTap: () => _activateField(start),
      onSubmitted: (_) => _searchImmediately(start),
      onChanged: (value) => _onQueryChanged(start: start, value: value),
      decoration: InputDecoration(
        labelText: label,
        hintText: label,
        filled: true,
        fillColor: const Color(0xFFF0F0F3),
        prefixIcon: Icon(icon, color: start ? AppColors.ink : AppColors.brand),
        suffixIconConstraints: const BoxConstraints(minWidth: 92, maxWidth: 96),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '$label 지우기',
              onPressed: () => _clearField(start),
              icon: const Icon(Icons.close, size: 19),
            ),
            IconButton(
              tooltip: '$label 검색',
              onPressed: () {
                _activateField(start);
                _searchImmediately(start);
              },
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: active ? AppColors.brand : Colors.transparent,
            width: active ? 1.4 : 0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.8),
        ),
      ),
    );
  }

  Widget _resultList(_FieldSearchState field, String query) {
    if (field.searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 34, color: AppColors.brand),
            SizedBox(height: 12),
            Text('장소를 검색하고 있어요'),
          ],
        ),
      );
    }
    if (field.error != null) return _message(Icons.wifi_off, field.error!);
    if (field.searched && field.results.isEmpty) {
      return _message(
        Icons.search_off,
        '“$query” 검색 결과가 없습니다.\n다른 검색어를 입력해 주세요.',
      );
    }
    if (!field.searched && query.isNotEmpty) {
      return _message(Icons.keyboard, '2글자 이상 입력하면 검색 결과가 자동으로 표시됩니다.');
    }
    if (!field.searched) return _recommendedList();
    return ListView.separated(
      key: const ValueKey('place-search-results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: field.results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, thickness: .7),
      itemBuilder: (_, index) {
        final result = field.results[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 4,
          ),
          leading: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFFDEDEC),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.place_outlined, color: AppColors.brand),
          ),
          title: Text(
            result.displayTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
          subtitle: Text(
            result.address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          trailing: SizedBox(
            width: 58,
            child: Text(
              result.category,
              textAlign: TextAlign.right,
              maxLines: 2,
              style: const TextStyle(fontSize: 11, color: AppColors.secondary),
            ),
          ),
          onTap: () => _select(result),
        );
      },
    );
  }

  Widget _recommendedList() {
    final recentCount = widget.controller.recentPlaces.length;
    final places = [
      ...widget.controller.recentPlaces,
      ...samplePlaces.where(
        (sample) => !widget.controller.recentPlaces.any(
          (recent) => recent.position == sample.position,
        ),
      ),
    ];
    return ListView.separated(
      key: const ValueKey('recommended-place-results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: places.length,
      separatorBuilder: (_, _) => const Divider(height: 1, thickness: .7),
      itemBuilder: (_, index) {
        final place = places[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            index < recentCount ? Icons.history : Icons.place_outlined,
            color: AppColors.muted,
          ),
          title: Text(
            place.name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
          subtitle: Text(
            place.address,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          trailing: Text(
            index < recentCount ? '최근' : '추천',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          onTap: () => _select(
            PlaceSearchResult(
              id: 'saved-$index',
              name: place.name,
              displayTitle: place.name,
              address: place.address,
              category: index < recentCount ? '최근 검색' : '추천',
              lat: place.position.latitude,
              lon: place.position.longitude,
            ),
          ),
        );
      },
    );
  }

  Widget _message(IconData icon, String text) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: AppColors.muted),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}
