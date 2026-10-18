import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/services/production_cost_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestCosts extends ProductionCostDatabase {
  _TestCosts(this.db);
  final Database db;

  @override
  Future<Database> get database async => db;
}

void main() {
  sqfliteFfiInit();
  test('material source is first-writer-wins under concurrent upserts', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute('''
        CREATE TABLE production_costs (
          id TEXT PRIMARY KEY,
          field_id TEXT NOT NULL,
          season_id TEXT NOT NULL,
          category TEXT NOT NULL,
          date TEXT NOT NULL,
          item_name TEXT NOT NULL,
          quantity REAL NOT NULL,
          unit TEXT NOT NULL,
          unit_price REAL NOT NULL,
          amount REAL NOT NULL,
          employee_id TEXT,
          machine_id TEXT,
          notes TEXT NOT NULL,
          source TEXT,
          source_id TEXT
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX idx_cost_source ON production_costs(source, source_id) '
        'WHERE source IS NOT NULL AND source_id IS NOT NULL',
      );
      final costs = _TestCosts(db);
      ProductionCostModel issue(String id, double price) => ProductionCostModel(
        id: id,
        fieldId: 'field',
        seasonId: 'season',
        category: ProductionCostCategory.material,
        date: DateTime.utc(2026, 10, 18),
        itemName: 'Fertilizer',
        quantity: 2,
        unit: 'kg',
        unitPrice: price,
        amount: 2 * price,
        notes: 'issue',
        source: 'material',
        sourceId: 'movement-1',
      );
      await Future.wait([
        costs.upsert(issue('first', 10)),
        costs.upsert(issue('second', 99)),
      ]);
      final saved = await costs.getBySource('material', 'movement-1');
      expect(saved, isNotNull);
      expect(saved!.unitPrice, anyOf(10, 99));
      expect(saved.amount, saved.unitPrice * 2);
      expect((await db.query('production_costs')), hasLength(1));
      await costs.upsert(issue('replay', 500));
      final replay = await costs.getBySource('material', 'movement-1');
      expect(replay!.unitPrice, saved.unitPrice);
      expect(replay.id, saved.id);
    } finally {
      await db.close();
    }
  });
}
