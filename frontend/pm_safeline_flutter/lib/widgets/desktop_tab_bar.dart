import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../theme/app_theme.dart';

/// 데스크톱 패널 하단의 홈/서비스 정보 탭 바.
/// 화면 전환이 "뒤로가기가 있는 하위 페이지"가 아니라 탭 전환처럼 느껴지도록
/// 홈 화면과 정보 화면 양쪽에서 동일한 형태로 사용한다.
class DesktopTabBar extends StatelessWidget {
  const DesktopTabBar({
    super.key,
    required this.controller,
    required this.selected,
  });

  final AppController controller;
  final AppScreen selected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _button(
              label: '홈',
              icon: Icons.home,
              isSelected: selected == AppScreen.home,
              onPressed: () => controller.show(AppScreen.home),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _button(
              key: const ValueKey('desktop-info-menu'),
              label: '서비스 정보',
              icon: Icons.info_outline,
              isSelected: selected == AppScreen.info,
              onPressed: () => controller.show(AppScreen.info),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _button({
    Key? key,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onPressed,
  }) => Material(
    key: key,
    color: isSelected ? const Color(0xFFFDEDEC) : Colors.transparent,
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
              color: isSelected ? AppColors.brand : AppColors.secondary,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.brand : AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
