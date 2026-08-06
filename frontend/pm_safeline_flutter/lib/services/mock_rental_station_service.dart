import '../models/rental_station.dart';
import 'rental_station_service.dart';

class MockRentalStationService implements RentalStationService {
  const MockRentalStationService({
    this.delay = const Duration(milliseconds: 650),
  });

  final Duration delay;

  @override
  Future<List<RentalStation>> fetchStations() async {
    await Future<void>.delayed(delay);
    final updated = DateTime.now().subtract(const Duration(minutes: 3));
    return [
      RentalStation(
        id: 'tashu-cityhall',
        name: '대전시청역 타슈 대여소',
        address: '대전 서구 둔산중로 55',
        lat: 36.3508,
        lon: 127.3842,
        availableBikes: 7,
        totalDocks: 14,
        returnableDocks: 7,
        updatedAt: updated,
      ),
      RentalStation(
        id: 'tashu-gov',
        name: '정부청사역 타슈 대여소',
        address: '대전 서구 청사로 189',
        lat: 36.3575,
        lon: 127.3812,
        availableBikes: 3,
        totalDocks: 12,
        returnableDocks: 9,
        updatedAt: updated,
      ),
      RentalStation(
        id: 'tashu-jungangno',
        name: '중앙로역 타슈 대여소',
        address: '대전 중구 중앙로 145',
        lat: 36.3288,
        lon: 127.4255,
        availableBikes: 0,
        totalDocks: 10,
        returnableDocks: 10,
        updatedAt: updated,
      ),
      RentalStation(
        id: 'tashu-daejeon',
        name: '대전역 타슈 대여소',
        address: '대전 동구 중앙로 215',
        lat: 36.3321,
        lon: 127.4344,
        availableBikes: 9,
        totalDocks: 16,
        returnableDocks: 7,
        updatedAt: updated,
      ),
      RentalStation(
        id: 'tashu-cnu',
        name: '충남대 정문 타슈 대여소',
        address: '대전 유성구 대학로 99',
        lat: 36.3664,
        lon: 127.3447,
        availableBikes: 5,
        totalDocks: 12,
        returnableDocks: 7,
        updatedAt: updated,
      ),
      RentalStation(
        id: 'tashu-dunsan',
        name: '둔산동 타슈 대여소',
        address: '대전 서구 둔산로 100',
        lat: 36.3519,
        lon: 127.3778,
        availableBikes: null,
        totalDocks: 11,
        returnableDocks: 6,
        updatedAt: updated,
      ),
      RentalStation(
        id: 'tashu-hanbat',
        name: '한밭수목원 타슈 대여소',
        address: '대전 서구 둔산대로 169',
        lat: 36.3683,
        lon: 127.3881,
        availableBikes: 2,
        totalDocks: 10,
        returnableDocks: 8,
        updatedAt: updated,
      ),
    ];
  }
}
