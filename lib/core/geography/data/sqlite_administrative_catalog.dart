import 'package:sqflite/sqflite.dart';

import '../domain/administrative_code_catalog.dart';
import '../domain/entities/administrative_unit.dart';

/// AGRICO-managed administrative codes. These are not official Lao district codes.
class SqliteAdministrativeCatalog {
  const SqliteAdministrativeCatalog(this.database);

  static const table = 'agrico_administrative_units';
  final Database database;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        level TEXT NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        alternate_name TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES $table(id),
        UNIQUE (parent_id, level, code)
      )
    ''');
    // SQLite treats NULL as distinct in UNIQUE indexes; root countries need
    // their own uniqueness constraint.
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS agrico_country_codes '
        'ON $table(code) WHERE parent_id IS NULL');
  }

  /// Idempotently install the initial four approved AGRICO codes.
  Future<void> seedInitialLocation() async {
    final now = DateTime.utc(2026).toIso8601String();
    final units = [
      ('agrico-la', null, AdministrativeLevel.country, 'LA', 'Lào'),
      ('agrico-la-svk', 'agrico-la', AdministrativeLevel.province, 'SVK', 'Savannakhet'),
      ('agrico-la-svk-nong', 'agrico-la-svk', AdministrativeLevel.district, 'NONG', 'Nong'),
      ('agrico-la-svk-nong-tako', 'agrico-la-svk-nong', AdministrativeLevel.village, 'TAKO', 'Ta Ko'),
    ];
    await database.transaction((tx) async {
      for (final (id, parent, level, code, name) in units) {
        await tx.insert(table, {
          'id': id,
          'parent_id': parent,
          'level': level.name,
          'code': code,
          'name': name,
          'active': 1,
          'created_at': now,
          'created_by': 'agrico-initial-catalog',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final existing = (await tx.query(table,
            columns: ['parent_id', 'level', 'code'],
            where: 'id = ?', whereArgs: [id])).single;
        if (existing['parent_id'] != parent || existing['level'] != level.name ||
            existing['code'] != code) {
          throw const FormatException('Initial location conflicts with an existing code.');
        }
      }
    });
  }

  Future<List<AdministrativeUnit>> all() async {
    final rows = await database.query(table, orderBy: 'level, name');
    return rows.map((row) => AdministrativeUnit(
      id: row['id']! as String,
      parentId: row['parent_id'] as String?,
      level: AdministrativeLevel.values.byName(row['level']! as String),
      code: row['code']! as String,
      name: row['name']! as String,
      alternateName: row['alternate_name'] as String?,
      active: row['active'] == 1,
      createdAt: DateTime.parse(row['created_at']! as String),
      createdBy: row['created_by']! as String,
    )).toList();
  }

  Future<AdministrativeCodeCatalog> loadCatalog() async =>
      AdministrativeCodeCatalog(await all());

  /// Add a province, district, or village under an existing active parent.
  Future<void> add(AdministrativeUnit unit) async {
    unit.validate();
    if (unit.code == null || !RegExp(r'^[A-Z0-9]+$').hasMatch(unit.code!)) {
      throw const FormatException('Administrative code must use A–Z and 0–9.');
    }
    await database.transaction((tx) async {
      if (unit.parentId != null) {
        final parents = await tx.query(table,
            columns: ['level', 'active'], where: 'id = ?', whereArgs: [unit.parentId]);
        final expected = switch (unit.level) {
          AdministrativeLevel.province => AdministrativeLevel.country,
          AdministrativeLevel.district => AdministrativeLevel.province,
          AdministrativeLevel.village => AdministrativeLevel.district,
          _ => throw const FormatException('Unsupported administrative level.'),
        };
        if (parents.length != 1 || parents.single['active'] != 1 ||
            parents.single['level'] != expected.name) {
          throw const FormatException('Invalid administrative parent.');
        }
      }
      await tx.insert(table, {
        'id': unit.id, 'parent_id': unit.parentId, 'level': unit.level.name,
        'code': unit.code, 'name': unit.name,
        'alternate_name': unit.alternateName,
        'active': unit.active ? 1 : 0,
        'created_at': unit.createdAt.toIso8601String(),
        'created_by': unit.createdBy,
      });
    });
  }
}
