import 'package:sqflite/sqflite.dart';

import '../domain/land_parcel_reference_code.dart';

/// Allocates household/parcel display numbers inside the caller's save
/// transaction. Callbacks must write the corresponding record with [tx].
class SqliteParcelNumberSequence {
  static const table = 'agrico_parcel_number_sequences_v2';
  static const previousTable = 'agrico_parcel_number_sequences';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        farm_id TEXT NOT NULL,
        village_id TEXT NOT NULL,
        household_number INTEGER NOT NULL,
        last_sequence INTEGER NOT NULL CHECK (
          (household_number = 0 AND last_sequence BETWEEN 0 AND 99999) OR
          (household_number != 0 AND last_sequence BETWEEN 0 AND 999)
        ),
        PRIMARY KEY (farm_id, village_id, household_number)
      )
    ''');
    final old = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [previousTable],
    );
    if (old.isNotEmpty) {
      // Preserve old allocations. Household counters used to be per village;
      // take the highest issued number as the first global starting point.
      await db.execute('''
        INSERT OR IGNORE INTO $table
          (farm_id, village_id, household_number, last_sequence)
        SELECT farm_id,
               CASE WHEN household_number = 0 THEN '' ELSE village_id END,
               household_number, MAX(last_sequence)
        FROM $previousTable
        GROUP BY farm_id,
          CASE WHEN household_number = 0 THEN '' ELSE village_id END,
          household_number
      ''');
    }
  }

  /// `household_number = 0` and the empty village scope reserve one household
  /// counter for the entire farm. The households table is unique per farm.
  Future<T> saveHousehold<T>({
    required Transaction tx,
    required String farmId,
    required Future<T> Function(String householdCode) save,
  }) async {
    final number = await _next(tx, farmId, '', 0);
    return save('H${number.toString().padLeft(5, '0')}');
  }

  /// Parcel numbering starts at 001 for each household inside a village.
  Future<T> saveParcel<T>({
    required Transaction tx,
    required String farmId,
    required String villageId,
    required int householdNumber,
    required String countryCode,
    required String provinceCode,
    required String districtCode,
    required String villageCode,
    required Future<T> Function(String parcelCode) save,
  }) async {
    if (householdNumber < 1 || householdNumber > 99999) {
      throw const FormatException('Household number must be 00001–99999.');
    }
    final number = await _next(tx, farmId, villageId, householdNumber);
    final code = LandParcelReferenceCode(
      countryCode: countryCode,
      provinceCode: provinceCode,
      districtCode: districtCode,
      villageCode: villageCode,
      householdNumber: householdNumber,
      parcelNumber: number,
    ).toString();
    return save(code);
  }

  Future<int> _next(Transaction tx, String farmId, String villageId,
      int householdNumber) async {
    if (farmId.trim().isEmpty ||
        (householdNumber != 0 && villageId.trim().isEmpty)) {
      throw const FormatException('Farm and parcel village are required.');
    }
    final scope = [farmId, villageId, householdNumber];
    await tx.rawInsert(
      'INSERT OR IGNORE INTO $table '
      '(farm_id, village_id, household_number, last_sequence) '
      'VALUES (?, ?, ?, 0)', scope);
    final changed = await tx.rawUpdate(
      'UPDATE $table SET last_sequence = last_sequence + 1 '
      'WHERE farm_id = ? AND village_id = ? AND household_number = ? '
      'AND last_sequence < ?', [...scope, householdNumber == 0 ? 99999 : 999]);
    if (changed != 1) throw const FormatException('Parcel numbering range is full.');
    final rows = await tx.rawQuery('SELECT last_sequence FROM $table '
        'WHERE farm_id = ? AND village_id = ? AND household_number = ?', scope);
    return rows.single['last_sequence']! as int;
  }
}
