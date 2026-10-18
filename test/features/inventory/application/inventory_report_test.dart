import 'package:agrico_deepseek/features/inventory/application/inventory_report.dart';
import 'package:agrico_deepseek/features/inventory/domain/entities/inventory_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const item = InventoryItem(
    id: 'item',
    farmId: 'farm',
    code: 'VT01',
    name: 'Phân bón',
    unit: 'kg',
    unitPrice: 10,
    supplier: 'A',
    stock: 7,
  );
  final events = [
    InventoryMovement(
      id: 'in',
      farmId: 'farm',
      itemId: 'item',
      code: 'NHAP-202610-001',
      kind: InventoryMovementKind.receipt,
      quantity: 10,
      occurredAt: DateTime.utc(2026, 9, 30, 17),
    ),
    InventoryMovement(
      id: 'out',
      farmId: 'farm',
      itemId: 'item',
      code: 'XUAT-202610-001',
      kind: InventoryMovementKind.issue,
      quantity: 3,
      occurredAt: DateTime.utc(2026, 10, 1),
    ),
  ];
  test('filters by code, item, type and inclusive Laos date', () {
    final report = InventoryReport(items: [item], movements: events);
    expect(report.filter(query: 'nhap').map((m) => m.id), ['in']);
    expect(report.filter(query: 'phân').length, 2);
    expect(report.filter(kind: InventoryMovementKind.issue).map((m) => m.id), [
      'out',
    ]);
    expect(report.filter(itemId: 'other'), isEmpty);
    expect(
      report
          .filter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 1))
          .length,
      2,
    );
    expect(report.filter(to: DateTime(2026, 9, 30)), isEmpty);
  });
  test('opening balance includes all movements before the Laos start day', () {
    final report = InventoryReport(items: [item], movements: events);
    // The first receipt occurs at 00:00 on October 1 in Laos, not
    // September 30. Both movements belong to October 1.
    final october = report.workbook(
      from: DateTime.utc(2026, 10, 1),
      to: DateTime.utc(2026, 10, 1),
    );
    final row = october['Stock'].rows[1];
    expect(row[3]?.value.toString(), '0');
    expect(row[4]?.value.toString(), '10');
    expect(row[5]?.value.toString(), '3');
    expect(row[6]?.value.toString(), '7');

    final november = report.workbook(from: DateTime.utc(2026, 11, 1));
    final next = november['Stock'].rows[1];
    expect(next[3]?.value.toString(), '7');
    expect(next[4]?.value.toString(), '0');
    expect(next[5]?.value.toString(), '0');
    expect(next[6]?.value.toString(), '7');
  });

  test('Excel contains overview, filtered movements and date-based stock', () {
    final report = InventoryReport(items: [item], movements: events);
    final excel = report.workbook(
      query: 'nhap',
      kind: InventoryMovementKind.receipt,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 1),
    );
    expect(excel.tables.keys, containsAll(['Overview', 'Movements', 'Stock']));
    expect(excel['Movements'].rows.length, 2);
    expect(excel['Stock'].rows.length, 2);
    expect(excel.encode(), isNotEmpty);
  });
}
