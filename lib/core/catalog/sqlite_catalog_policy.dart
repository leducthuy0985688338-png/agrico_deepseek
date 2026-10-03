import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'company_catalog.dart';
import 'sqlite_company_catalog.dart';

class SqliteCatalogPolicy {
  const SqliteCatalogPolicy._();
  static Future<void> crop(
    DatabaseExecutor db, {
    required String id,
    required String parcelId,
    required String type,
    required String unit,
  }) async {
    // Pre-A04 standalone schemas remain supported. The production root installs
    // the catalog before opening business routes; validation shares their transaction.
    if (!await SqliteCompanyCatalog.hasTable(
      db,
      SqliteCompanyCatalog.entriesTable,
    )) {
      return;
    }
    final parcels = await db.query(
      'land_parcels',
      columns: ['farm_id'],
      where: 'id=?',
      whereArgs: [parcelId],
    );
    if (parcels.isEmpty) throw const CatalogFailure('catalog.denied');
    final old = await db.query(
      'land_parcel_crops',
      columns: ['payload_json'],
      where: 'id=? AND parcel_id=?',
      whereArgs: [id, parcelId],
    );
    if (old.isNotEmpty) {
      final previous =
          jsonDecode(old.single['payload_json'] as String)
              as Map<String, dynamic>;
      if (previous['cropType'] == type && previous['unit'] == unit) return;
    }
    final farm = parcels.single['farm_id'];
    for (final (kind, name) in [
      (CatalogKind.crop, type),
      (CatalogKind.unit, unit),
    ]) {
      final found = await db.query(
        SqliteCompanyCatalog.entriesTable,
        columns: ['id'],
        where: 'farm_id=? AND kind=? AND name=? AND active=1',
        whereArgs: [farm, kind.name, name],
        limit: 1,
      );
      if (found.isEmpty) throw const CatalogFailure('catalog.invalidSelection');
    }
  }
}
