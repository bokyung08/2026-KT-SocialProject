import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm_safeline_flutter/widgets/mobile_route_selector.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0, 599.0]) {
    testWidgets('$width px에서 후보 3개가 잘림 없이 같은 너비로 표시된다', (tester) async {
      await _pumpSelector(tester, width: width, itemCount: 3);

      final selector = tester.getRect(
        find.byKey(const ValueKey('mobile-route-selector')),
      );
      final first = tester.getRect(
        find.byKey(const ValueKey('mobile-route-option-0')),
      );
      final last = tester.getRect(
        find.byKey(const ValueKey('mobile-route-option-2')),
      );

      expect(first.width, closeTo(last.width, 0.1));
      expect(first.height, greaterThanOrEqualTo(40));
      expect(last.right, lessThanOrEqualTo(selector.right + 0.1));
      expect(find.text('추천 경로'), findsOneWidget);
      expect(find.text('대안 2'), findsOneWidget);
      expect(find.text('대안 3'), findsOneWidget);
      expect(find.textContaining('후보 중 추천'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('후보 1개와 2개는 사용 가능한 너비를 균등하게 채운다', (tester) async {
    await _pumpSelector(tester, width: 320, itemCount: 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-route-option-0'))).width,
      closeTo(288, 0.1),
    );

    await _pumpSelector(tester, width: 320, itemCount: 2);
    final first = tester.getSize(
      find.byKey(const ValueKey('mobile-route-option-0')),
    );
    final second = tester.getSize(
      find.byKey(const ValueKey('mobile-route-option-1')),
    );
    expect(first.width, closeTo(second.width, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('후보 4개 이상은 가로 스크롤하며 마지막 선택 항목을 자동 노출한다', (tester) async {
    await _pumpSelector(tester, width: 320, itemCount: 5);
    await tester.tap(find.byKey(const ValueKey('select-last-route')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-route-selector-scroll')),
      findsOneWidget,
    );
    expect(find.text('대안 5'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-route-option-4')).hitTestable(),
      findsOneWidget,
    );
    final viewport = tester.getRect(
      find.byKey(const ValueKey('mobile-route-selector-scroll')),
    );
    final last = tester.getRect(
      find.byKey(const ValueKey('mobile-route-option-4')),
    );
    expect(last.left, greaterThanOrEqualTo(viewport.left - 0.1));
    expect(last.right, lessThanOrEqualTo(viewport.right + 0.1));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSelector(
  WidgetTester tester, {
  required double width,
  required int itemCount,
  int initialSelectedIndex = 0,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SelectorHarness(
              itemCount: itemCount,
              initialSelectedIndex: initialSelectedIndex,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _SelectorHarness extends StatefulWidget {
  const _SelectorHarness({
    required this.itemCount,
    required this.initialSelectedIndex,
  });

  final int itemCount;
  final int initialSelectedIndex;

  @override
  State<_SelectorHarness> createState() => _SelectorHarnessState();
}

class _SelectorHarnessState extends State<_SelectorHarness> {
  late int selectedIndex;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialSelectedIndex;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MobileRouteSelector(
        itemCount: widget.itemCount,
        selectedIndex: selectedIndex,
        onSelected: (index) => setState(() => selectedIndex = index),
      ),
      TextButton(
        key: const ValueKey('select-last-route'),
        onPressed: () => setState(() => selectedIndex = widget.itemCount - 1),
        child: const Text('마지막 경로 선택'),
      ),
    ],
  );
}
