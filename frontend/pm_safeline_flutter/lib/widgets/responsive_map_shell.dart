import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class ResponsiveLayout {
  static const mobileBreakpoint = 600.0;
  static const desktopBreakpoint = 1024.0;
  static const tabletPanelWidth = 320.0;
  static const desktopPanelWidth = 380.0;

  static bool isWide(double width) => width >= mobileBreakpoint;

  static double panelWidth(double width) =>
      width >= desktopBreakpoint ? desktopPanelWidth : tabletPanelWidth;
}

class ResponsiveMapShell extends StatefulWidget {
  const ResponsiveMapShell({
    super.key,
    required this.panel,
    required this.map,
    required this.panelOpen,
    required this.onTogglePanel,
    this.onMapLayoutChanged,
    this.layoutToken,
    this.overlayPanel,
    this.overlayOpen = false,
  });

  final Widget panel;
  final Widget map;
  final bool panelOpen;
  final VoidCallback onTogglePanel;
  final VoidCallback? onMapLayoutChanged;
  final Object? layoutToken;
  final Widget? overlayPanel;
  final bool overlayOpen;

  @override
  State<ResponsiveMapShell> createState() => _ResponsiveMapShellState();
}

class _ResponsiveMapShellState extends State<ResponsiveMapShell> {
  static const _duration = Duration(milliseconds: 240);
  double? _lastWidth;

  @override
  void didUpdateWidget(covariant ResponsiveMapShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layoutToken != widget.layoutToken) _notifyMapAfterFrame();
  }

  void _notifyMapAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onMapLayoutChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder는 쓰지 않는다: 그 builder 콜백은 레이아웃 단계에서만
    // 재실행되는데, 오버레이 패널의 Positioned 지오메트리(left/width 등)가
    // 안 바뀐 채로 그 안의 자식 위젯 prop만 바뀌면(예: 지도 탭 좌표) 프레임워크가
    // "다시 레이아웃할 필요 없음"으로 보고 콜백을 건너뛰어, 오버레이 패널이
    // 새 상태를 못 받는 문제가 있었다. MediaQuery는 일반 빌드 경로를 타므로
    // setState가 있을 때마다 항상 다시 계산된다.
    final size = MediaQuery.sizeOf(context);
    if (_lastWidth != null && (_lastWidth! - size.width).abs() > .5) {
      _notifyMapAfterFrame();
    }
    _lastWidth = size.width;
    final panelWidth = ResponsiveLayout.panelWidth(size.width);
    final overlayWidth = math.min(
      panelWidth,
      math.max(0.0, size.width - panelWidth),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
          AnimatedPositioned(
            key: const ValueKey('responsive-shell-map'),
            duration: _duration,
            curve: Curves.easeOutCubic,
            onEnd: widget.onMapLayoutChanged,
            left: widget.panelOpen ? panelWidth : 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: widget.map,
          ),
          Positioned(
            left: widget.panelOpen ? panelWidth : 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: _duration,
                curve: Curves.easeOut,
                opacity: widget.overlayOpen ? 1 : 0,
                child: const ColoredBox(
                  key: ValueKey('desktop-search-map-scrim'),
                  color: Color(0x1A000000),
                ),
              ),
            ),
          ),
          if (widget.overlayOpen && widget.overlayPanel != null)
            AnimatedPositioned(
              key: const ValueKey('desktop-search-overlay-position'),
              duration: _duration,
              curve: Curves.easeOutCubic,
              left: panelWidth,
              top: 0,
              bottom: 0,
              width: overlayWidth,
              child: IgnorePointer(
                ignoring: !widget.overlayOpen,
                child: ExcludeSemantics(
                  excluding: !widget.overlayOpen,
                  child: Material(
                    key: const ValueKey('desktop-route-search-overlay'),
                    color: Colors.white,
                    elevation: 10,
                    shadowColor: Colors.black26,
                    child: widget.overlayPanel,
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: _duration,
            curve: Curves.easeOutCubic,
            left: widget.panelOpen ? 0 : -panelWidth,
            top: 0,
            bottom: 0,
            width: panelWidth,
            child: Material(
              key: const ValueKey('responsive-side-panel'),
              color: Colors.white,
              elevation: 8,
              shadowColor: Colors.black26,
              child: widget.panel,
            ),
          ),
          AnimatedPositioned(
            duration: _duration,
            curve: Curves.easeOutCubic,
            left: widget.panelOpen ? panelWidth - 1 : 0,
            top: (size.height / 2 - 30).clamp(16.0, double.infinity).toDouble(),
            width: 28,
            height: 60,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: widget.overlayOpen ? 0 : 1,
              child: IgnorePointer(
                ignoring: widget.overlayOpen,
                child: _PanelEdgeTab(
                  panelOpen: widget.panelOpen,
                  onPressed: widget.onTogglePanel,
                ),
              ),
            ),
          ),
        ],
      );
  }
}

class _PanelEdgeTab extends StatelessWidget {
  const _PanelEdgeTab({required this.panelOpen, required this.onPressed});

  final bool panelOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = panelOpen ? '경로 정보 패널 접기' : '경로 정보 패널 열기';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: ClipPath(
          clipper: const _PanelTabClipper(),
          child: Material(
            key: const ValueKey('desktop-panel-toggle'),
            color: Colors.white,
            elevation: 5,
            child: InkWell(
              onTap: onPressed,
              child: Center(
                child: Icon(
                  panelOpen
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 22,
                  semanticLabel: label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelTabClipper extends CustomClipper<ui.Path> {
  const _PanelTabClipper();

  @override
  ui.Path getClip(Size size) => ui.Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - 7, 7)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width - 7, size.height - 7)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<ui.Path> oldClipper) => false;
}
