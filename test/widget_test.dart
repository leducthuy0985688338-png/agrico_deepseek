import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/main.dart';

void main() {
  testWidgets('AGRICO login screen smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());

    expect(find.text('AGRICO ERP'), findsOneWidget);
    expect(find.text('Quản lý nông nghiệp thông minh'), findsOneWidget);
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
  });
}
