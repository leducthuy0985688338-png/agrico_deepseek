import 'package:agrico_deepseek/models/fuel_model.dart';
import 'package:agrico_deepseek/providers/fuel_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fuel restore replaces samples and rebuilds stock from cloud ledger', () {
    final provider = FuelProvider();

    final restoredFuels = [
      FuelModel(
        id: 'F-CLOUD',
        name: 'Dầu Cloud',
        unit: 'Lít',
        stock: 999,
        unitPrice: 26000,
        supplier: 'Nhà cung cấp Cloud',
      ),
      FuelModel(
        id: 'F-NO-LEDGER',
        name: 'Mỡ Cloud',
        unit: 'Kg',
        stock: 25,
        unitPrice: 180000,
        supplier: 'Nhà cung cấp B',
      ),
    ];
    final restoredTransactions = [
      FuelTransaction(
        id: 'TX-IN',
        fuelId: 'F-CLOUD',
        fuelName: 'Dầu Cloud',
        date: DateTime.utc(2026, 8, 10),
        type: TransactionType.NHAP,
        quantity: 100,
        price: 26000,
      ),
      FuelTransaction(
        id: 'TX-OUT',
        fuelId: 'F-CLOUD',
        fuelName: 'Dầu Cloud',
        date: DateTime.utc(2026, 8, 11),
        type: TransactionType.XUAT,
        quantity: 35,
        price: 26000,
        machineId: 'M001',
        fieldId: 'LO0001',
        seasonId: 'VS001',
        operatorName: 'Nguyễn Văn An',
      ),
    ];

    provider.restoreFromCloud(
      fuels: restoredFuels,
      transactions: [...restoredTransactions, restoredTransactions.last],
    );

    expect(provider.fuels.map((fuel) => fuel.id), ['F-CLOUD', 'F-NO-LEDGER']);
    expect(provider.allTransactions, hasLength(2));
    expect(provider.allTransactions.first.id, 'TX-OUT');
    expect(provider.fuels.first.stock, 65);
    expect(provider.fuels.last.stock, 25);
    expect(provider.allTransactions.first.seasonId, 'VS001');
    expect(provider.allTransactions.first.operatorName, 'Nguyễn Văn An');
  });
}
