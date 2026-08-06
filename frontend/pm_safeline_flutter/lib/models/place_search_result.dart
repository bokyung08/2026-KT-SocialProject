import 'package:latlong2/latlong.dart';

import 'place.dart';

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.id,
    required this.name,
    required this.displayTitle,
    required this.address,
    required this.category,
    required this.lat,
    required this.lon,
    this.qualifierCandidates = const [],
  });

  final String id;
  final String name;
  final String displayTitle;
  final String address;
  final String category;
  final double lat;
  final double lon;
  final List<String> qualifierCandidates;

  // 선택 후 입력창과 최근 경로에도 지점이 구분되는 제목을 보존한다.
  Place toPlace() => Place(displayTitle, address, LatLng(lat, lon));

  PlaceSearchResult withDisplayTitle(String value) => PlaceSearchResult(
    id: id,
    name: name,
    displayTitle: value,
    address: address,
    category: category,
    lat: lat,
    lon: lon,
    qualifierCandidates: qualifierCandidates,
  );

  factory PlaceSearchResult.fromNominatimJson(Map<String, dynamic> json) {
    final lat = double.tryParse(json['lat']?.toString() ?? '');
    final lon = double.tryParse(json['lon']?.toString() ?? '');
    final displayName = json['display_name']?.toString().trim() ?? '';
    if (lat == null || lon == null || displayName.isEmpty) {
      throw const FormatException('검색 결과의 좌표 또는 주소가 올바르지 않습니다.');
    }

    final parts = displayName
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final namedetails = _stringMap(json['namedetails']);
    final addressDetails = _stringMap(json['address']);
    final name = _firstValue([
      namedetails['name'],
      json['name']?.toString(),
      parts.first,
    ]);
    final type = json['type']?.toString() ?? '';
    final osmClass = json['class']?.toString() ?? '';
    final category = _category(type, osmClass);
    final branch = _firstValue([
      namedetails['branch'],
      addressDetails['branch'],
    ]);
    final address = parts.length > 1 ? parts.skip(1).join(' ') : displayName;
    final qualifiers =
        _uniqueNonEmpty([
              branch,
              addressDetails['building'],
              addressDetails['road'],
              addressDetails['suburb'],
              addressDetails['neighbourhood'],
              addressDetails['quarter'],
              addressDetails['borough'],
              addressDetails['city_district'],
              addressDetails['city'],
              addressDetails['town'],
              category,
            ])
            .where((value) => value != name && !name.contains(value))
            .toList(growable: false);
    final id = _firstValue([
      json['place_id']?.toString(),
      '${json['osm_type'] ?? 'place'}-${json['osm_id'] ?? ''}',
      '$lat,$lon',
    ]);
    return PlaceSearchResult(
      id: id,
      name: name,
      displayTitle: branch.isNotEmpty && !name.contains(branch)
          ? '$name($branch)'
          : name,
      address: address,
      category: category,
      lat: lat,
      lon: lon,
      qualifierCandidates: qualifiers,
    );
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) return const {};
    return value.map(
      (key, item) => MapEntry(key.toString(), item?.toString().trim() ?? ''),
    );
  }

  static String _firstValue(Iterable<String?> values) => values
      .firstWhere(
        (value) => value != null && value.trim().isNotEmpty,
        orElse: () => '',
      )!
      .trim();

  static List<String> _uniqueNonEmpty(Iterable<String?> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value != null && value.trim().isNotEmpty && seen.add(value.trim()))
          value.trim(),
    ];
  }

  static String _category(String type, String osmClass) {
    const labels = {
      'bakery': '베이커리',
      'marketplace': '시장',
      'station': '교통',
      'university': '교육',
      'school': '교육',
      'hospital': '의료',
      'restaurant': '음식점',
      'cafe': '카페',
      'park': '공원',
      'administrative': '지역',
    };
    return labels[type] ??
        labels[osmClass] ??
        (type.isEmpty ? '장소' : type.replaceAll('_', ' '));
  }
}

/// 같은 이름의 후보는 지점명 또는 주소에서 얻은 고유 식별자를 제목에 붙인다.
List<PlaceSearchResult> createDistinctDisplayTitles(
  List<PlaceSearchResult> results,
) {
  final groups = <String, List<PlaceSearchResult>>{};
  for (final result in results) {
    groups.putIfAbsent(result.name.trim().toLowerCase(), () => []).add(result);
  }
  return [
    for (final result in results)
      if (groups[result.name.trim().toLowerCase()]!.length == 1)
        result
      else
        result.withDisplayTitle(
          '${result.name}(${_uniqueQualifier(result, groups[result.name.trim().toLowerCase()]!)})',
        ),
  ];
}

String _uniqueQualifier(
  PlaceSearchResult target,
  List<PlaceSearchResult> siblings,
) {
  final optionsByResult = <PlaceSearchResult, List<String>>{
    for (final result in siblings)
      result: [...result.qualifierCandidates, result.address],
  };
  for (final option in optionsByResult[target]!) {
    if (option.isEmpty) continue;
    final occurrences = optionsByResult.values
        .where((options) => options.contains(option))
        .length;
    if (occurrences == 1) return option;
  }
  // 동일 이름·동일 주소는 서비스에서 제거하므로 남은 후보는 전체 주소로 구분 가능하다.
  return target.address.isNotEmpty ? target.address : target.category;
}
