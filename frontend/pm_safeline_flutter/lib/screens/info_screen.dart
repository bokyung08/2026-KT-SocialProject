import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../config/api_config.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/desktop_tab_bar.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({
    super.key,
    required this.controller,
    this.desktopPanel = false,
  });

  final AppController controller;
  final bool desktopPanel;

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      key: desktopPanel ? const ValueKey('desktop-info-panel') : null,
      padding: EdgeInsets.fromLTRB(
        desktopPanel ? 24 : 20,
        desktopPanel ? 24 : 20,
        desktopPanel ? 24 : 20,
        desktopPanel ? 20 : SafeLineBottomNav.reservedHeight,
      ),
      children: [
        Text('서비스 정보', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'PM 이용자가 자전거도로의 단절과 위험 도로구조를 피하도록 '
          '연속주행 안전 경로를 제안합니다.',
        ),
        const SizedBox(height: 20),
        _card(
          '현재 실행 모드',
          ApiConfig.useMock
              ? 'Mock · 디자인 시연 데이터'
              : 'API · ${ApiConfig.baseUrl}',
          Icons.tune,
        ),
        _card('지도 데이터', '© OpenStreetMap contributors', Icons.map_outlined),
        _card(
          'API 데이터 안내',
          ApiConfig.useMock
              ? '위험 지점과 설명은 시연용 Mock 데이터입니다.'
              : '안전 점수와 추천 이유는 도로 구조 데이터를 기반으로 제공되며, '
                    '구간별 상세 위험 정보는 추후 제공될 예정입니다.',
          Icons.info_outline,
        ),
      ],
    );

    if (desktopPanel) {
      return ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            Expanded(child: content),
            const Divider(height: 1),
            DesktopTabBar(controller: controller, selected: AppScreen.info),
          ],
        ),
      );
    }
    return Scaffold(
      extendBody: true,
      body: content,
      bottomNavigationBar: SafeLineBottomNav(controller: controller, index: 1),
    );
  }

  Widget _card(String title, String body, IconData icon) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.brand),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(body),
            ],
          ),
        ),
      ],
    ),
  );
}
