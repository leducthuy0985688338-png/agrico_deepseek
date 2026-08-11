import 'package:agrico_deepseek/models/finance_model.dart';
import 'package:agrico_deepseek/providers/finance_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finance records keep cloud fields during a map round trip', () {
    final source = FinanceRecord(
      id: 'FIN-CLOUD',
      fieldId: 'LO-CLOUD',
      fieldName: 'Lô Cloud',
      date: DateTime.utc(2026, 8, 11, 7, 30),
      type: TransactionType.CHI,
      category: 'Nhiên liệu',
      amount: 4250000,
      description: 'Chi phí từ thiết bị khác',
      machineId: 'M-CLOUD',
      machineName: 'Máy Cloud',
    );

    final restored = FinanceRecord.fromMap(source.toMap());

    expect(restored.id, source.id);
    expect(restored.fieldId, source.fieldId);
    expect(restored.date, source.date);
    expect(restored.type, TransactionType.CHI);
    expect(restored.amount, 4250000);
    expect(restored.description, 'Chi phí từ thiết bị khác');
    expect(restored.machineId, 'M-CLOUD');
    expect(restored.machineName, 'Máy Cloud');
  });

  test('finance restore replaces samples, deduplicates, and rebuilds budgets', () {
    final provider = FinanceProvider();
    final expense = FinanceRecord(
      id: 'FIN-EXPENSE',
      fieldId: 'LO-CLOUD',
      fieldName: 'Lô Cloud',
      date: DateTime.utc(2026, 8, 10),
      type: TransactionType.CHI,
      category: 'Vật tư',
      amount: 4000000,
      description: 'Vật tư Cloud',
    );
    final revenue = FinanceRecord(
      id: 'FIN-REVENUE',
      fieldId: 'LO-CLOUD',
      fieldName: 'Lô Cloud',
      date: DateTime.utc(2026, 8, 11),
      type: TransactionType.THU,
      category: 'Thu hoạch',
      amount: 12000000,
      description: 'Doanh thu Cloud',
    );

    provider.restoreFromCloud(records: [expense, revenue, revenue]);

    expect(provider.records, hasLength(2));
    expect(provider.records.first.id, 'FIN-REVENUE');
    expect(provider.budgets, hasLength(1));
    expect(provider.getTotalCost(), 4000000);
    expect(provider.getTotalRevenue(), 12000000);
    expect(provider.getTotalProfit(), 8000000);
    expect(provider.budgets.single.remainingBudget, 5000000);
  });

  test('empty cloud finance data does not erase local records', () {
    final provider = FinanceProvider();
    final originalIds = provider.records.map((record) => record.id).toList();

    provider.restoreFromCloud(records: const []);

    expect(provider.records.map((record) => record.id), originalIds);
  });
}
