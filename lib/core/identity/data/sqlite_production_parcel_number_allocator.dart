import 'package:sqflite/sqflite.dart';

import '../domain/production_parcel_number_allocator.dart';
import '../domain/production_parcel_reference_code.dart';

class SqliteProductionParcelNumberAllocator
    implements ProductionParcelNumberAllocator {
  const SqliteProductionParcelNumberAllocator(this.transaction);
  final Transaction transaction;
  static const table = 'agrico_production_parcel_sequences_v4';

  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS $table (
      farm_id TEXT NOT NULL,
      project_code TEXT NOT NULL,
      parent_block_number INTEGER NOT NULL CHECK(parent_block_number >= 0),
      last_sequence INTEGER NOT NULL CHECK(last_sequence >= 0),
      PRIMARY KEY(farm_id, project_code, parent_block_number)
    )
  ''');

  @override
  Future<T> saveLandBlock<T>({
    required String farmId,
    required String projectCode,
    required Future<T> Function(ProductionParcelReferenceCode code) save,
  }) async {
    ProductionParcelReferenceCode.landBlock(
      projectCode: projectCode,
      landBlockNumber: 1,
    );
    final number = await _next(farmId, projectCode, 0);
    return save(
      ProductionParcelReferenceCode.landBlock(
        projectCode: projectCode,
        landBlockNumber: number,
      ),
    );
  }

  @override
  Future<T> saveFieldPlot<T>({
    required String farmId,
    required ProductionParcelReferenceCode parent,
    required Future<T> Function(ProductionParcelReferenceCode code) save,
  }) async {
    // Validate the parent before changing a counter. Its persisted identity
    // and farm membership must be checked by the creation workflow.
    ProductionParcelReferenceCode.fieldPlot(parent: parent, number: 1);
    final number = await _next(
      farmId,
      parent.projectCode,
      parent.landBlockNumber,
    );
    return save(
      ProductionParcelReferenceCode.fieldPlot(parent: parent, number: number),
    );
  }

  Future<int> _next(String farmId, String projectCode, int parentNumber) async {
    if (farmId.trim().isEmpty) {
      throw const FormatException('Farm identity is required.');
    }
    final scope = [farmId, projectCode, parentNumber];
    await transaction.rawInsert(
      'INSERT OR IGNORE INTO $table '
      '(farm_id, project_code, parent_block_number, last_sequence) VALUES (?, ?, ?, 0)',
      scope,
    );
    final changed = await transaction.rawUpdate(
      'UPDATE $table '
      'SET last_sequence = last_sequence + 1 '
      'WHERE farm_id = ? AND project_code = ? AND parent_block_number = ? '
      'AND last_sequence < 2147483647',
      scope,
    );
    if (changed != 1) {
      throw StateError('Production parcel numbering range is full.');
    }
    final rows = await transaction.rawQuery(
      'SELECT last_sequence FROM $table '
      'WHERE farm_id = ? AND project_code = ? AND parent_block_number = ?',
      scope,
    );
    return rows.single['last_sequence']! as int;
  }
}
