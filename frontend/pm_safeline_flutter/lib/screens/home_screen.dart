import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/sample_places.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/route_map.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          ),
          const SizedBox(height: 6),
          const Text('끊김은 줄이고, 안전한 길은 이어 드려요.'),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: controller.startNewRoute,
            icon: const Icon(Icons.add),
            label: const Text('새 경로 탐색'),
          ),
          const SizedBox(height: 18),
          Text('최근 경로', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          InkWell(
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
                    '${controller.recentRouteStart?.name ?? '충남대학교'} → ${controller.recentRouteDestination?.name ?? '대전시청'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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
          ),
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
}
