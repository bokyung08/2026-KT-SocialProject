import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/sample_places.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/route_map.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.desktopPanel = false,
    this.onDesktopNewRoute,
    this.onDesktopEditRecentRoute,
  });

  final AppController controller;
  final bool desktopPanel;
  final VoidCallback? onDesktopNewRoute;
  final VoidCallback? onDesktopEditRecentRoute;

  @override
  Widget build(BuildContext context) =>
      desktopPanel ? _buildDesktopPanel(context) : _buildMobile(context);

  Widget _buildMobile(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brandHeader(context),
          const SizedBox(height: 6),
          const Text('끊김은 줄이고, 안전한 길은 이어 드려요.'),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onDesktopNewRoute ?? controller.startNewRoute,
            icon: const Icon(Icons.add),
            label: const Text('새 경로 탐색'),
          ),
          const SizedBox(height: 18),
          Text('최근 경로', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          _recentRouteCard(),
          const SizedBox(height: 18),
          Text('대전에서 시작해 볼까요?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: RouteMap(
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
                '끊김은 줄이고, 안전한 길은 이어 드려요.',
                style: TextStyle(color: AppColors.secondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('desktop-new-route-button'),
                onPressed: onDesktopNewRoute ?? controller.startNewRoute,
                icon: const Icon(Icons.add),
                label: const Text('새 경로 탐색'),
              ),
              const SizedBox(height: 26),
              Text('최근 경로', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              _recentRouteCard(),
              if (onDesktopEditRecentRoute != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('desktop-edit-recent-route'),
                  onPressed: onDesktopEditRecentRoute,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('최근 경로 수정'),
                ),
              ],
              const SizedBox(height: 26),
              Text(
                '대전에서 시작해 볼까요?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              for (final place in samplePlaces.take(3))
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F9),
                    borderRadius: BorderRadius.circular(12),
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: _desktopMenuButton(
                    label: '홈',
                    icon: Icons.home,
                    selected: true,
                    onPressed: () {},
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _desktopMenuButton(
                    key: const ValueKey('desktop-info-menu'),
                    label: '서비스 정보',
                    icon: Icons.info_outline,
                    selected: false,
                    onPressed: () => controller.show(AppScreen.info),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _brandHeader(BuildContext context) => Row(
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(9),
          child: Icon(Icons.electric_scooter, color: Colors.white),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          'PM 세이프라인',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    ],
  );

  Widget _recentRouteCard() => InkWell(
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
            '${controller.recentRouteStart?.name ?? '충남대학교'} → '
            '${controller.recentRouteDestination?.name ?? '대전시청'}',
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

  Widget _desktopMenuButton({
    Key? key,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) => Material(
    key: key,
    color: selected ? const Color(0xFFFDEDEC) : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? AppColors.brand : AppColors.secondary,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.brand : AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
