import 'package:sqflite/sqflite.dart';
import '../authorization.dart';
import '../live_authorization.dart';
import '../../../features/inventory/domain/repositories/warehouse_repository.dart';

/// Basic identities for the account assignment picker; no private/pay data.
class SqliteOperationDirectory {
  const SqliteOperationDirectory(this.database, this.access);
  final Database database;
  final LiveAuthorization access;
  Future<Map<String, Map<String, String>>> load(
    AuthorizationSubject opened,
  ) => access.read(opened, [PermissionCodes.accountView], () async {
    final result = <String, Map<String, String>>{};
    for (final entry in {
      'warehouseIds': ('inventory_warehouses_v1', 'code'),
      'departmentIds': ('personnel_departments_v1', 'code'),
      'machineIds': ('company_catalog_entries_v1', 'code'),
    }.entries) {
      final (table, code) = entry.value;
      final rows = await database.query(
        table,
        columns: ['id', 'name', code],
        where:
            "farm_id=?${entry.key == 'machineIds' ? " AND kind='machine'" : ''}",
        whereArgs: [opened.farmId],
        orderBy: code,
      );
      result[entry.key] = {
        for (final row in rows)
          row['id']! as String: '${row[code]} · ${row['name']}',
      };
    }
    final defaultId = InventoryWarehouse.defaultId(opened.farmId);
    result['warehouseIds']!.putIfAbsent(defaultId, () => 'KHO-000');
    return result;
  });
}
