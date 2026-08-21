import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/sample_places.dart';
import '../models/place.dart';
import '../models/place_search_result.dart';
import '../services/geocoding_service.dart';
import '../theme/app_theme.dart';
import '../app_controller.dart';

typedef DraftRouteSubmit =
    Future<String?> Function(Place start, Place destination);

class DesktopRouteSearchPanel extends StatefulWidget {
  const DesktopRouteSearchPanel({
    super.key,
    required this.initialStart,
    required this.initialDestination,
    required this.initialTarget,
    required this.active,
    required this.recentPlaces,
    required this.onClose,
    required this.onDraftChanged,
    required this.onSubmit,
    this.geocodingService,
    this.mapTapPoint,
    this.mapTapSession = 0,
  });

  final Place? initialStart;
  final Place? initialDestination;
  final RouteSearchTarget initialTarget;
  final bool active;
  final List<Place> recentPlaces;
  final VoidCallback onClose;
  final void Function(Place? start, Place? destination) onDraftChanged;
  final DraftRouteSubmit onSubmit;
  final GeocodingService? geocodingService;
  final LatLng? mapTapPoint;
  final int mapTapSession;

  @override
  State<DesktopRouteSearchPanel> createState() =>
      _DesktopRouteSearchPanelState();
}

class _SearchState {
  Timer? debounce;
  int generation = 0;
  bool searching = false;
  bool searched = false;
  String? error;
  List<PlaceSearchResult> results = const [];

  void reset() {
    debounce?.cancel();
    generation++;
    searching = false;
    searched = false;
    error = null;
    results = const [];
  }

  void dispose() => debounce?.cancel();
}

class _DesktopRouteSearchPanelState extends State<DesktopRouteSearchPanel> {
  static const _debounceDuration = Duration(milliseconds: 400);

  late final GeocodingService _geocoding;
  late final TextEditingController _startText;
  late final TextEditingController _destinationText;
  late final FocusNode _startFocus;
  late final FocusNode _destinationFocus;
  late final _SearchState _startSearch;
  late final _SearchState _destinationSearch;
  late bool _editingStart;
  Place? _draftStart;
  Place? _draftDestination;
  bool _submitting = false;
  String? _submitError;
  bool _suppressQueryChange = false;

  TextEditingController get _activeText =>
      _editingStart ? _startText : _destinationText;
  _SearchState get _activeSearch =>
      _editingStart ? _startSearch : _destinationSearch;

  @override
  void initState() {
    super.initState();
    _geocoding = widget.geocodingService ?? GeocodingService();
    _draftStart = widget.initialStart;
    _draftDestination = widget.initialDestination;
    _startText = TextEditingController(text: _draftStart?.name ?? '');
    _destinationText = TextEditingController(
      text: _draftDestination?.name ?? '',
    );
    _startFocus = FocusNode(debugLabel: 'desktop-route-start-search');
    _destinationFocus = FocusNode(
      debugLabel: 'desktop-route-destination-search',
    );
    _startSearch = _SearchState();
    _destinationSearch = _SearchState();
    _editingStart = widget.initialTarget == RouteSearchTarget.start;
    _requestInitialFocus();
  }

  @override
  void didUpdateWidget(covariant DesktopRouteSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _requestInitialFocus();
    if (widget.mapTapSession != oldWidget.mapTapSession &&
        widget.mapTapPoint != null) {
      _selectFromMap(widget.mapTapPoint!);
    }
  }

  void _selectFromMap(LatLng point) {
    final wasStart = _editingStart;
    final fallbackName =
        '위도 ${point.latitude.toStringAsFixed(5)}, '
        '경도 ${point.longitude.toStringAsFixed(5)}';
    final place = Place('지도에서 선택한 위치', fallbackName, point);
    final field = wasStart ? _startSearch : _destinationSearch;
    field.reset();
    // TextEditingController.text를 바꾸면 TextField의 onChanged가 함께 호출되어
    // _onQueryChanged가 방금 지정한 draft를 도로 지워버릴 수 있다. 프로그램적으로
    // 텍스트를 바꾸는 동안에는 그 콜백을 무시한다.
    _suppressQueryChange = true;
    if (wasStart) {
      _draftStart = place;
      _startText.text = place.name;
    } else {
      _draftDestination = place;
      _destinationText.text = place.name;
    }
    _suppressQueryChange = false;
    _notifyDraft();

    if (_draftStart == null) {
      _activateField(true);
    } else if (_draftDestination == null) {
      _activateField(false);
    } else {
      setState(() => _submitError = null);
      FocusManager.instance.primaryFocus?.unfocus();
    }

    _geocoding.reverseGeocode(point.latitude, point.longitude).then((result) {
      if (!mounted || result == null) return;
      final resolved = Place(result.name, result.address, point);
      final stillCurrent = wasStart
          ? _draftStart?.position == point
          : _draftDestination?.position == point;
      if (!stillCurrent) return;
      _suppressQueryChange = true;
      if (wasStart) {
        _draftStart = resolved;
        _startText.text = resolved.name;
      } else {
        _draftDestination = resolved;
        _destinationText.text = resolved.name;
      }
      _suppressQueryChange = false;
      _notifyDraft();
    });
  }

  void _requestInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
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

  void _notifyDraft() => widget.onDraftChanged(_draftStart, _draftDestination);

  void _activateField(bool start) {
    if (_editingStart != start) setState(() => _editingStart = start);
    (start ? _startFocus : _destinationFocus).requestFocus();
  }

  void _onQueryChanged({required bool start, required String value}) {
    if (_suppressQueryChange) return;
    final field = start ? _startSearch : _destinationSearch;
    final selected = start ? _draftStart : _draftDestination;
    field.debounce?.cancel();
    field.generation++;
    if (selected != null && value != selected.name) {
      if (start) {
        _draftStart = null;
      } else {
        _draftDestination = null;
      }
      _notifyDraft();
    }
    final query = value.trim();
    setState(() {
      _editingStart = start;
      field.searching = false;
      field.searched = false;
      field.error = null;
      field.results = const [];
      _submitError = null;
    });
    if (query.length < 2) return;
    final generation = field.generation;
    field.debounce = Timer(
      _debounceDuration,
      () => _runSearch(start: start, query: query, generation: generation),
    );
  }

  Future<void> _searchImmediately(bool start) async {
    final field = start ? _startSearch : _destinationSearch;
    final query = (start ? _startText : _destinationText).text.trim();
    field.debounce?.cancel();
    field.generation++;
    setState(() => _editingStart = start);
    if (query.length < 2) return;
    await _runSearch(start: start, query: query, generation: field.generation);
  }

  Future<void> _runSearch({
    required bool start,
    required String query,
    required int generation,
  }) async {
    final field = start ? _startSearch : _destinationSearch;
    final text = start ? _startText : _destinationText;
    if (generation != field.generation || text.text.trim() != query) return;
    setState(() {
      field.searching = true;
      field.searched = true;
      field.error = null;
      field.results = const [];
    });
    try {
      final results = await _geocoding.search(query);
      if (!mounted ||
          generation != field.generation ||
          text.text.trim() != query) {
        return;
      }
      setState(() {
        field.results = results;
        field.searching = false;
      });
    } on GeocodingException catch (error) {
      if (!mounted ||
          generation != field.generation ||
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
    final place = result.toPlace();
    final field = _editingStart ? _startSearch : _destinationSearch;
    field.reset();
    _suppressQueryChange = true;
    if (_editingStart) {
      _draftStart = place;
      _startText.text = result.displayTitle;
    } else {
      _draftDestination = place;
      _destinationText.text = result.displayTitle;
    }
    _suppressQueryChange = false;
    _notifyDraft();

    if (_draftStart == null) {
      _activateField(true);
    } else if (_draftDestination == null) {
      _activateField(false);
    } else {
      setState(() => _submitError = null);
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _clearField(bool start) {
    final field = start ? _startSearch : _destinationSearch;
    final text = start ? _startText : _destinationText;
    field.reset();
    _suppressQueryChange = true;
    text.clear();
    _suppressQueryChange = false;
    if (start) {
      _draftStart = null;
    } else {
      _draftDestination = null;
    }
    _notifyDraft();
    _activateField(start);
    setState(() => _submitError = null);
  }

  void _swap() {
    _suppressQueryChange = true;
    final oldText = _startText.text;
    _startText.text = _destinationText.text;
    _destinationText.text = oldText;
    _suppressQueryChange = false;
    final oldPlace = _draftStart;
    _draftStart = _draftDestination;
    _draftDestination = oldPlace;
    _startSearch.reset();
    _destinationSearch.reset();
    _notifyDraft();
    setState(() => _submitError = null);
  }

  void _close() {
    _startSearch.reset();
    _destinationSearch.reset();
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onClose();
  }

  Future<void> _submit() async {
    final start = _draftStart;
    final destination = _draftDestination;
    if (start == null || destination == null || _submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final error = await widget.onSubmit(start, destination);
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(
        error == null
            ? '[DesktopRouteSearchPanel] submit 성공'
            : '[DesktopRouteSearchPanel] submit 실패: $error',
      );
    }
    setState(() {
      _submitting = false;
      _submitError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeSearch;
    final activeQuery = _activeText.text.trim();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      key: const ValueKey('desktop-route-search-content'),
      color: const Color(0xFFFAFAFB),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + keyboardInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
                    key: const ValueKey('desktop-search-close'),
                    tooltip: '검색 패널 닫기',
                    onPressed: _close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _searchField(
                key: const ValueKey('desktop-start-search-field'),
                label: '출발지',
                controller: _startText,
                focusNode: _startFocus,
                start: true,
                icon: Icons.circle_outlined,
              ),
              const SizedBox(height: 8),
              _searchField(
                key: const ValueKey('desktop-destination-search-field'),
                label: '도착지',
                controller: _destinationText,
                focusNode: _destinationFocus,
                start: false,
                icon: Icons.location_on,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('desktop-swap-route-fields'),
                  onPressed: _submitting ? null : _swap,
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('출발·도착 교환'),
                ),
              ),
              Text(
                active.searched || active.searching
                    ? '“$activeQuery” 검색 결과'
                    : activeQuery.isEmpty
                    ? '최근 검색 · 추천 장소'
                    : '',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: _resultList(active, activeQuery)),
              if (_submitError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _submitError!,
                    key: const ValueKey('desktop-route-submit-error'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton(
                key: const ValueKey('desktop-analyze-route-button'),
                onPressed:
                    _draftStart != null &&
                        _draftDestination != null &&
                        !_submitting
                    ? _submit
                    : null,
                child: Text(
                  _submitting
                      ? '안전 경로 분석 중...'
                      : _draftStart != null && _draftDestination != null
                      ? '경로 탐색'
                      : '출발지와 도착지를 선택해 주세요',
                ),
              ),
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
      enabled: !_submitting,
      textInputAction: TextInputAction.search,
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
              onPressed: _submitting ? null : () => _clearField(start),
              icon: const Icon(Icons.close, size: 19),
            ),
            IconButton(
              tooltip: '$label 검색',
              onPressed: _submitting
                  ? null
                  : () {
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

  Widget _resultList(_SearchState field, String query) {
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
      key: const ValueKey('desktop-place-search-results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: field.results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, thickness: .7),
      itemBuilder: (_, index) => _resultTile(field.results[index]),
    );
  }

  Widget _resultTile(PlaceSearchResult result) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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

  Widget _recommendedList() {
    final recentCount = widget.recentPlaces.length;
    final places = [
      ...widget.recentPlaces,
      ...samplePlaces.where(
        (sample) => !widget.recentPlaces.any(
          (recent) => recent.position == sample.position,
        ),
      ),
    ];
    return ListView.separated(
      key: const ValueKey('desktop-recommended-place-results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 8),
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
              id: 'desktop-saved-$index',
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
