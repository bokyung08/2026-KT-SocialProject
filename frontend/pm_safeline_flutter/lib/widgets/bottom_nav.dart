import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../theme/app_theme.dart';

/// 토스 미니앱 브랜딩 가이드가 요구하는 플로팅 탭바.
///
/// 화면 하단에 붙는 바가 아니라, 좌우/하단 여백을 두고 콘텐츠 위에 떠 있는
/// 캡슐 형태로 그린다. 사용하는 화면은 `extendBody: true`로 두고 스크롤
/// 콘텐츠 하단에 [reservedHeight]만큼 여백을 남겨 탭바가 콘텐츠를 가리지
/// 않도록 한다.
class SafeLineBottomNav extends StatelessWidget {
  const SafeLineBottomNav({
    super.key,
    required this.controller,
    required this.index,
  });

  /// 탭바가 떠 있는 영역(캡슐 높이 + 상하 여백). 콘텐츠 하단 패딩에 사용한다.
  static const double reservedHeight = 84;

  static const double _capsuleHeight = 56;
  static const double _horizontalMargin = 20;
  static const double _bottomMargin = 16;

  final AppController controller;
  final int index;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalMargin,
        12,
        _horizontalMargin,
        _bottomMargin,
      ),
      // heightFactor 1: bottomNavigationBar 슬롯은 loose 제약이라 그냥 Center를
      // 쓰면 세로로 화면 전체까지 늘어나 탭바가 가운데 떠 버린다.
      child: Center(
        heightFactor: 1,
        child: Container(
          key: const ValueKey('floating-tab-bar'),
          height: _capsuleHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_capsuleHeight / 2),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F1A1A1E),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tab(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: '홈',
                selected: index == 0,
                onTap: () => controller.show(AppScreen.home),
              ),
              _tab(
                icon: Icons.info_outline,
                selectedIcon: Icons.info,
                label: '정보',
                selected: index == 1,
                onTap: () => controller.show(AppScreen.info),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _tab({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected ? AppColors.brand : AppColors.secondary;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_capsuleHeight / 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: _capsuleHeight - 12,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFDEDEC) : Colors.transparent,
            borderRadius: BorderRadius.circular(_capsuleHeight / 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
