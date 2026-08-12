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
    this.onDismissOverlay,
  });

  final Widget panel;
  final Widget map;
  final bool panelOpen;
  final VoidCallback onTogglePanel;
  final VoidCallback? onMapLayoutChanged;
  final Object? layoutToken;
  final Widget? overlayPanel;
  final bool overlayOpen;
  final VoidCallback? onDismissOverlay;

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_lastWidth != null &&
          (_lastWidth! - constraints.maxWidth).abs() > .5) {
        _notifyMapAfterFrame();
      }
      _lastWidth = constraints.maxWidth;
      final panelWidth = ResponsiveLayout.panelWidth(constraints.maxWidth);
      final overlayWidth = math.min(
        panelWidth,
        math.max(0.0, constraints.maxWidth - panelWidth),
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
              ignoring: !widget.overlayOpen,
              child: AnimatedOpacity(
                duration: _duration,
                curve: Curves.easeOut,
                opacity: widget.overlayOpen ? 1 : 0,
                child: GestureDetector(
                  key: const ValueKey('desktop-search-map-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismissOverlay,
                  child: const ColoredBox(color: Color(0x1A000000)),
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
            top: (constraints.maxHeight / 2 - 30)
                .clamp(16.0, double.infinity)
                .toDouble(),
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
    },
  );
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
