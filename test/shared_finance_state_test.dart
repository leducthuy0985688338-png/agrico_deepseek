import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:agrico_deepseek/models/finance_model.dart';
import 'package:agrico_deepseek/providers/dashboard_provider.dart';
import 'package:agrico_deepseek/providers/finance_provider.dart';
import 'package:agrico_deepseek/screens/finance_screen.dart';

FinanceRecord _testRevenue() {
  return FinanceRecord(
    id: 'FINANCE-SHARED-01',
    fieldId: 'FIELD-SHARED-01',
    fieldName: 'Lô kiểm thử',
    date: DateTime(2026, 8, 11),
    type: TransactionType.THU,
    category: 'Thu hoạch',
    amount: 1234567,
    description: 'Kiểm tra trạng thái dùng chung',
  );
}

void main() {
  test('dashboard reads the active finance provider', () {
    final financeProvider = FinanceProvider();
    final dashboard = DashboardProvider(financeProvider: financeProvider);
    final revenueBefore = financeProvider.getTotalRevenue();

    financeProvider.addTransaction(_testRevenue());

    expect(
      dashboard.totalRevenue,
      (revenueBefore + 1234567).toInt(),
    );

    financeProvider.dispose();
  });

  testWidgets('finance detail keeps the transaction from shared state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    final financeProvider = FinanceProvider()..addTransaction(_testRevenue());

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceProvider>.value(
        value: financeProvider,
        child: const MaterialApp(home: FinanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lô kiểm thử'), findsOneWidget);

    await tester.tap(find.text('Lô kiểm thử'));
    await tester.pumpAndSettle();

    expect(find.text('Kiểm tra trạng thái dùng chung'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    financeProvider.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
