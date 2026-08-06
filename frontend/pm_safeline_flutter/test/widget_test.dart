import 'package:flutter_test/flutter_test.dart';
import 'package:pm_safeline_flutter/app.dart';

void main() {
  testWidgets('홈 화면에 서비스 제목과 경로 탐색 버튼을 표시한다', (tester) async {
    await tester.pumpWidget(const SafeLineApp());
    expect(find.text('PM 세이프라인'), findsOneWidget);
    expect(find.text('새 경로 탐색'), findsOneWidget);
  });
}
