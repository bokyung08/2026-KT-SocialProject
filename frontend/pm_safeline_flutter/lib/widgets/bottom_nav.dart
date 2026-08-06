import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../theme/app_theme.dart';

class SafeLineBottomNav extends StatelessWidget {
  const SafeLineBottomNav({
    super.key,
    required this.controller,
    required this.index,
  });
  final AppController controller;
  final int index;

  @override
  Widget build(BuildContext context) => NavigationBar(
    height: 68,
    selectedIndex: index,
    indicatorColor: const Color(0xFFFDEDEC),
    backgroundColor: Colors.white,
    onDestinationSelected: (value) =>
        controller.show(value == 0 ? AppScreen.home : AppScreen.info),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home, color: AppColors.brand),
        label: '홈',
      ),
      NavigationDestination(
        icon: Icon(Icons.info_outline),
        selectedIcon: Icon(Icons.info, color: AppColors.brand),
        label: '정보',
      ),
    ],
  );
}
