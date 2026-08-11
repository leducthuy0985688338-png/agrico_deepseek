import 'package:agrico_deepseek/models/warehouse_item.dart';
import 'package:agrico_deepseek/providers/warehouse_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warehouse cloud round trip keeps catalogue and stock fields', () {
    final source = WarehouseItem(
      id: 'VT-CLOUD',
      name: 'Phân NPK 16-16-8',
      unit: 'Kg',
      importPrice: 17500,
      supplier: 'Nhà cung cấp Savannakhet',
      stock: 320,
    );

    final restored = WarehouseItem.fromMap(source.toMap());

    expect(restored.id, source.id);
    expect(restored.name, source.name);
    expect(restored.unit, source.unit);
    expect(restored.importPrice, source.importPrice);
    expect(restored.supplier, source.supplier);
    expect(restored.stock, source.stock);
  });

  test('warehouse map accepts Firestore numeric representations', () {
    final restored = WarehouseItem.fromMap({
      'id': 'VT-NUM',
      'name': 'Vôi nông nghiệp',
      'unit': 'Kg',
      'importPrice': 6250,
      'supplier': 'Nhà cung cấp A',
      'stock': 42.0,
    });

    expect(restored.importPrice, 6250.0);
    expect(restored.stock, 42);
  });

  test('warehouse restore deduplicates and ignores empty cloud', () {
    final provider = WarehouseProvider();
    final older = WarehouseItem(
      id: 'VT-01',
      name: 'Phân bản cũ',
      unit: 'Kg',
      importPrice: 12000,
      supplier: 'Nhà cung cấp cũ',
      stock: 10,
    );
    final second = WarehouseItem(
      id: 'VT-02',
      name: 'Bao bì',
      unit: 'Cái',
      importPrice: 3500,
      supplier: 'Nhà cung cấp B',
      stock: 75,
    );
    final newer = WarehouseItem(
      id: 'VT-01',
      name: 'Phân bản mới',
      unit: 'Kg',
      importPrice: 14500,
      supplier: 'Nhà cung cấp mới',
      stock: 28,
    );

    final restoredCount =
        provider.restoreFromCloud(items: [older, second, newer]);

    expect(restoredCount, 2);
    expect(provider.items, hasLength(2));
    expect(
      provider.items.firstWhere((item) => item.id == 'VT-01').name,
      'Phân bản mới',
    );
    expect(
      provider.items.firstWhere((item) => item.id == 'VT-01').stock,
      28,
    );

    final restoredIds = provider.items.map((item) => item.id).toList();
    final emptyCount = provider.restoreFromCloud(items: const []);

    expect(emptyCount, 0);
    expect(provider.items.map((item) => item.id), restoredIds);

    final invalidCount = provider.restoreFromCloud(
      items: [
        WarehouseItem(
          id: '   ',
          name: 'Không hợp lệ',
          unit: 'Kg',
          importPrice: 1,
          supplier: '',
        ),
      ],
    );

    expect(invalidCount, 0);
    expect(provider.items.map((item) => item.id), restoredIds);
  });
}
