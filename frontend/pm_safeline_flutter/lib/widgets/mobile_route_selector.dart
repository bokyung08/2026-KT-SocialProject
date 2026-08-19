import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MobileRouteSelector extends StatefulWidget {
  const MobileRouteSelector({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int itemCount;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<MobileRouteSelector> createState() => _MobileRouteSelectorState();
}

class _MobileRouteSelectorState extends State<MobileRouteSelector> {
  final _scrollController = ScrollController();
  double _scrollItemWidth = 0;
  static const _spacing = 6.0;

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant MobileRouteSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.itemCount != widget.itemCount) {
      _revealSelected();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _revealSelected([int? selectedIndex]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _scrollItemWidth <= 0) {
        return;
      }
      final index = selectedIndex ?? widget.selectedIndex;
      final viewportWidth = _scrollController.position.viewportDimension;
      final itemStart = index * (_scrollItemWidth + _spacing);
      final centeredOffset = itemStart - (viewportWidth - _scrollItemWidth) / 2;
      final target = centeredOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _select(int index) {
    widget.onSelected(index);
    _revealSelected(index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final useEqualWidths = widget.itemCount <= 3;
      final equalWidth = widget.itemCount == 0
          ? constraints.maxWidth
          : (constraints.maxWidth - _spacing * (widget.itemCount - 1)) /
                widget.itemCount;
      final scrollItemWidth = ((constraints.maxWidth - _spacing * 2) / 3)
          .clamp(92.0, 128.0)
          .toDouble();
      _scrollItemWidth = useEqualWidths ? 0 : scrollItemWidth;
      if (useEqualWidths) {
        return Row(
          key: const ValueKey('mobile-route-selector'),
          children: [
            for (var index = 0; index < widget.itemCount; index++) ...[
              if (index > 0) const SizedBox(width: _spacing),
              SizedBox(width: equalWidth, child: _item(index)),
            ],
          ],
        );
      }

      return SizedBox(
        key: const ValueKey('mobile-route-selector-scroll'),
        width: constraints.maxWidth,
        height: 44,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Row(
              children: [
                for (var index = 0; index < widget.itemCount; index++) ...[
                  if (index > 0) const SizedBox(width: _spacing),
                  SizedBox(width: scrollItemWidth, child: _item(index)),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _item(int index) {
    final selected = index == widget.selectedIndex;
    return Material(
      key: ValueKey('mobile-route-item-$index'),
      color: selected ? const Color(0xFFFDEDEC) : const Color(0xFFF7F7F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppColors.brand : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('mobile-route-option-$index'),
        onTap: () => _select(index),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    index == 0 ? '추천 경로' : '대안 ${index + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.brand : AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
