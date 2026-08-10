import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:agrico_deepseek/main.dart';
import 'package:agrico_deepseek/providers/cloud_sync_provider.dart';

void main() {
  testWidgets('AGRICO app starts successfully', (WidgetTester tester) async {
    // Đặt kích thước màn hình đủ lớn để tránh lỗi RenderFlex overflow.
    await tester.binding.setSurfaceSize(const Size(1200, 1000));

    // Khởi động ứng dụng AGRICO.
    await tester.pumpWidget(const MyApp());

    // Chờ toàn bộ widget và animation khởi tạo.
    await tester.pumpAndSettle();

    // Kiểm tra MyApp đã được render.
    expect(find.byType(MyApp), findsOneWidget);

    final materialAppContext = tester.element(find.byType(MaterialApp));
    expect(
      Provider.of<CloudSyncProvider>(materialAppContext, listen: false),
      isA<CloudSyncProvider>(),
    );

    // Khôi phục kích thước màn hình mặc định.
    await tester.binding.setSurfaceSize(null);
  });
}
