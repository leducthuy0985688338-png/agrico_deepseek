import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:agrico_deepseek/main.dart';
import 'package:agrico_deepseek/providers/cloud_sync_provider.dart';
import 'package:agrico_deepseek/providers/dashboard_provider.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:agrico_deepseek/providers/production_season_provider.dart';
import 'package:agrico_deepseek/providers/production_log_provider.dart';
import 'package:agrico_deepseek/providers/harvest_provider.dart';
import 'package:agrico_deepseek/providers/production_cost_provider.dart';
import 'package:agrico_deepseek/screens/settings_screen.dart';

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
    expect(
      Provider.of<DashboardProvider>(materialAppContext, listen: false),
      isA<DashboardProvider>(),
    );
    expect(
      Provider.of<FieldProvider>(materialAppContext, listen: false),
      same(FieldProvider.instance),
    );
    expect(
      Provider.of<ProductionSeasonProvider>(materialAppContext, listen: false),
      isA<ProductionSeasonProvider>(),
    );
    expect(
      Provider.of<ProductionLogProvider>(materialAppContext, listen: false),
      isA<ProductionLogProvider>(),
    );
    expect(
      Provider.of<HarvestProvider>(materialAppContext, listen: false),
      isA<HarvestProvider>(),
    );
    expect(
      Provider.of<ProductionCostProvider>(materialAppContext, listen: false),
      isA<ProductionCostProvider>(),
    );

    // Khôi phục kích thước màn hình mặc định.
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('settings tab opens the real cloud sync screen', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('ĐĂNG NHẬP'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('☁️ Đồng bộ dữ liệu'), findsOneWidget);
    expect(
      find.text(
        'Đồng bộ tất cả dữ liệu lên Cloud để sử dụng trên nhiều thiết bị',
      ),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(null);
  });
}
