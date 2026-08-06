import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MapFloatingControls extends StatelessWidget {
  const MapFloatingControls({
    super.key,
    required this.onCurrentLocation,
    required this.onFitRoute,
    required this.onToggleFocusMode,
    required this.focusMode,
  });

  final VoidCallback onCurrentLocation;
  final VoidCallback onFitRoute;
  final VoidCallback onToggleFocusMode;
  final bool focusMode;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 3,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapControlButton(
          key: const ValueKey('map-current-location-button'),
          icon: Icons.my_location_rounded,
          tooltip: '현재 위치',
          onPressed: onCurrentLocation,
        ),
        const _ControlDivider(),
        _MapControlButton(
          key: const ValueKey('map-fit-route-button'),
          icon: Icons.route_outlined,
          tooltip: '경로 전체보기',
          onPressed: onFitRoute,
        ),
        const _ControlDivider(),
        _MapControlButton(
          key: const ValueKey('map-focus-mode-button'),
          icon: focusMode
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          tooltip: focusMode ? '지도 크게보기 종료' : '지도 크게보기',
          selected: focusMode,
          onPressed: onToggleFocusMode,
        ),
      ],
    ),
  );
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox.square(
        dimension: 44,
        child: Icon(
          icon,
          size: 21,
          color: selected ? AppColors.brand : AppColors.secondary,
        ),
      ),
    ),
  );
}

class _ControlDivider extends StatelessWidget {
  const _ControlDivider();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 26, child: Divider(height: 1, thickness: 0.7));
}
