import 'package:agrico_deepseek/models/fuel_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fuel transaction cloud mapping preserves traceability', () {
    final transaction = FuelTransaction(
      id: 'TX-001',
      fuelId: 'F001',
      fuelName: 'Dầu Diesel',
      date: DateTime.utc(2026, 8, 11, 2, 30),
      type: TransactionType.XUAT,
      quantity: 42.5,
      price: 25000,
      machineId: 'M001',
      machineName: 'Máy cày Yanmar',
      fieldId: 'LO0001',
      fieldName: 'Lô cà phê A1',
      seasonId: 'VS001',
      operatorName: 'Nguyễn Văn An',
      note: 'Đổ dầu ca sáng',
    );

    final cloudMap = transaction.toMap();

    expect(cloudMap['id'], 'TX-001');
    expect(cloudMap['date'], '2026-08-11T02:30:00.000Z');
    expect(cloudMap['type'], TransactionType.XUAT.index);
    expect(cloudMap['quantity'], 42.5);
    expect(cloudMap['machineId'], 'M001');
    expect(cloudMap['fieldId'], 'LO0001');
    expect(cloudMap['seasonId'], 'VS001');
    expect(cloudMap['operatorName'], 'Nguyễn Văn An');

    final restored = FuelTransaction.fromMap(cloudMap);
    expect(restored.toMap(), cloudMap);
  });
}
