import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_controller.dart';
import '../data/sample_places.dart';
import '../models/place.dart';
import '../services/current_location_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/desktop_tab_bar.dart';
import '../widgets/route_map.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.desktopPanel = false,
    this.onDesktopNewRoute,
  });

  final AppController controller;
  final bool desktopPanel;
  final VoidCallback? onDesktopNewRoute;

  @override
  Widget build(BuildContext context) =>
      desktopPanel ? _buildDesktopPanel(context) : _buildMobile(context);

  Widget _buildMobile(BuildContext context) => Scaffold(
    extendBody: true,
    body: Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        22,
        20,
        SafeLineBottomNav.reservedHeight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brandHeader(context),
          const SizedBox(height: 6),
          const Text('길잇, 끊김은 줄이고 안전한 길은 이어드려요.'),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onDesktopNewRoute ?? controller.startNewRoute,
            icon: const Icon(Icons.add),
            label: const Text('새 경로 탐색'),
          ),
          if (controller.hasRecentRoute) ...[
            const SizedBox(height: 18),
            Text('최근 경로', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _recentRouteCard(),
          ],
          if (controller.favorites.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('즐겨찾는 경로', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ..._favoriteCards(),
          ],
          const SizedBox(height: 18),
          Text('대전에서 시작해 볼까요?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: RouteMap(
                // 최근 경로/즐겨찾기가 비동기로 로드되며 위쪽 콘텐츠 높이가 바뀌면
                // 이 Expanded의 크기도 함께 바뀐다. 첫 프레임 크기 기준으로 시작한
                // 타일 요청이 그 리사이즈에 취소돼 버리는 걸 막기 위해, 로드가
                // 끝난 뒤(최종 레이아웃이 확정된 뒤) 지도를 한 번 새로 마운트한다.
                key: ValueKey('home-map-${controller.historyLoaded}'),
                start: samplePlaces[0].position,
                destination: samplePlaces[1].position,
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: SafeLineBottomNav(controller: controller, index: 0),
  );

  Widget _buildDesktopPanel(BuildContext context) => ColoredBox(
    key: const ValueKey('desktop-home-panel'),
    color: Colors.white,
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            children: [
              _brandHeader(context),
              const SizedBox(height: 8),
              const Text(
                '길잇, 끊김은 줄이고 안전한 길은 이어드려요.',
                style: TextStyle(color: AppColors.secondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('desktop-new-route-button'),
                onPressed: onDesktopNewRoute ?? controller.startNewRoute,
                icon: const Icon(Icons.add),
                label: const Text('새 경로 탐색'),
              ),
              if (controller.hasRecentRoute) ...[
                const SizedBox(height: 26),
                Text('최근 경로', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                _recentRouteCard(),
              ],
              if (controller.favorites.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text(
                  '즐겨찾는 경로',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                ..._favoriteCards(),
              ],
              const SizedBox(height: 26),
              Text(
                '대전에서 시작해 볼까요?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              for (final place in samplePlaces.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0xFFF7F7F9),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: ValueKey('sample-place-${place.name}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _useSamplePlace(context, place),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 19,
                              color: AppColors.brand,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                place.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        DesktopTabBar(controller: controller, selected: AppScreen.home),
      ],
    ),
  );

  Widget _brandHeader(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SvgPicture.asset(
          'assets/main_icon.svg',
          width: 32,
          height: 32,
        ),
      ),
      const SizedBox(width: 10),
      SvgPicture.asset('assets/title_img.svg', height: 40),
    ],
  );

  Widget _recentRouteCard() => InkWell(
    key: const ValueKey('recent-route-card'),
    borderRadius: BorderRadius.circular(16),
    onTap: () {
      controller.useRecentRoute();
      controller.analyze();
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${controller.recentRouteStart?.name} → '
            '${controller.recentRouteDestination?.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          const Text(
            '안전 경로를 다시 확인해 보세요',
            style: TextStyle(
              color: AppColors.brand,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _favoriteCards() => [
    for (final favorite in controller.favorites)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          key: ValueKey('favorite-route-${favorite.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            controller.useFavorite(favorite);
            controller.analyze();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    favorite.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-favorite-${favorite.id}'),
                  tooltip: '즐겨찾기 해제',
                  onPressed: () => controller.removeFavorite(favorite.id),
                  icon: const Icon(Icons.star, color: AppColors.brand),
                ),
              ],
            ),
          ),
        ),
      ),
  ];

  Future<void> _useSamplePlace(BuildContext context, Place destination) async {
    const locationService = CurrentLocationService();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final position = await locationService.getCurrentLocation();
      final start = Place('현재 위치', '현재 위치', position);
      controller.setStart(start);
      controller.setDestination(destination);
      await controller.analyze();
    } on CurrentLocationException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
