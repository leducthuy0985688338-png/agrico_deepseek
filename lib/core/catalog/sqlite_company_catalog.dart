import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'company_catalog.dart';
import 'sync/catalog_sync_journal.dart';

class SqliteCompanyCatalog implements CompanyCatalogRepository {
  const SqliteCompanyCatalog(this.database);
  final Database database;
  static const entriesTable = 'company_catalog_entries_v1';
  static const requestsTable = 'company_catalog_requests_v1';
  static const auditTable = 'company_catalog_audit_v1';
  static Future<void> createSchema(Database db) async {
    await db.transaction((tx) async {
      await CatalogSyncJournal.createSchema(tx);
      await tx.execute('''CREATE TABLE IF NOT EXISTS $entriesTable (
        id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, kind TEXT NOT NULL,
        code TEXT NOT NULL, name TEXT NOT NULL, name_key TEXT NOT NULL,
        unit_id TEXT REFERENCES $entriesTable(id) ON DELETE RESTRICT,
        active INTEGER NOT NULL CHECK(active IN (0,1)), revision INTEGER NOT NULL CHECK(revision > 0),
        UNIQUE(farm_id,kind,code), UNIQUE(farm_id,kind,name_key))''');
      await tx.execute('''CREATE TABLE IF NOT EXISTS $requestsTable (
        id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, actor_uid TEXT NOT NULL,
        kind TEXT NOT NULL, code TEXT NOT NULL, name TEXT NOT NULL, reason TEXT NOT NULL,
        created_at TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('pending','approved','rejected')),
        entry_id TEXT REFERENCES $entriesTable(id) ON DELETE RESTRICT,
        resolved_by TEXT, resolved_at TEXT, resolution TEXT)''');
      await tx.execute(
        '''CREATE TABLE IF NOT EXISTS $auditTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id TEXT NOT NULL,
        actor_uid TEXT NOT NULL, occurred_at TEXT NOT NULL, reason TEXT NOT NULL,
        target_id TEXT NOT NULL, action TEXT NOT NULL, before_json TEXT, after_json TEXT NOT NULL)''',
      );
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS company_catalog_bootstrap_v1 (farm_id TEXT PRIMARY KEY)',
      );
      await tx.execute(
        '''CREATE TABLE IF NOT EXISTS company_catalog_sequences_v1 (
        farm_id TEXT NOT NULL, kind TEXT NOT NULL, last_number INTEGER NOT NULL,
        PRIMARY KEY(farm_id, kind))''',
      );
      await tx.execute(
        'CREATE INDEX IF NOT EXISTS idx_catalog_requests_actor ON $requestsTable(farm_id,actor_uid,status)',
      );
    });
  }

  static String nameKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  static CatalogEntry _entry(Map<String, Object?> row) => CatalogEntry(
    id: row['id'] as String,
    farmId: row['farm_id'] as String,
    kind: CatalogKind.values.byName(row['kind'] as String),
    code: row['code'] as String,
    name: row['name'] as String,
    unitId: row['unit_id'] as String?,
    active: row['active'] == 1,
    revision: row['revision'] as int,
  );
  static Map<String, Object?> _row(CatalogEntry e, int revision) => {
    'id': e.id,
    'farm_id': e.farmId,
    'kind': e.kind.name,
    'code': e.code,
    'name': e.name,
    'name_key': nameKey(e.name),
    'unit_id': e.unitId,
    'active': e.active ? 1 : 0,
    'revision': revision,
  };
  static Future<bool> hasTable(DatabaseExecutor db, String table) async =>
      (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      )).isNotEmpty;
  @override
  Future<List<CatalogEntry>> entries(String farmId) async => List.unmodifiable(
    (await database.query(
      entriesTable,
      where: 'farm_id=?',
      whereArgs: [farmId],
      orderBy: 'kind,code',
    )).map(_entry),
  );
  static Future<void> _audit(
    DatabaseExecutor tx, {
    required String farmId,
    required String actor,
    required DateTime time,
    required String reason,
    required String target,
    required String action,
    Map<String, Object?>? before,
    required Map<String, Object?> after,
  }) async {
    await tx.insert(auditTable, {
      'farm_id': farmId,
      'actor_uid': actor,
      'occurred_at': time.toUtc().toIso8601String(),
      'reason': reason,
      'target_id': target,
      'action': action,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': jsonEncode(after),
    });
    // One transaction commits both the business mutation and its send intent.
    // Adoption does not grant an actor permission to publish old snapshots.
    if (action != 'adopt') {
      await CatalogSyncJournal.append(
        tx,
        farmId: farmId,
        actorUid: actor,
        entity: action == 'request' || action == 'resolve'
            ? 'request'
            : 'entry',
        targetId: target,
        payload: after,
        reason: reason,
        occurredAt: time,
      );
    }
  }

  @override
  Future<void> save(
    CatalogEntry entry, {
    required int? expectedRevision,
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    required void Function() authorize,
  }) async {
    if (expectedRevision != null || entry.code.isNotEmpty) entry.validate();
    try {
      await database.transaction((tx) async {
        final actual = expectedRevision == null && entry.code.isEmpty
            ? CatalogEntry(
                id: entry.id,
                farmId: entry.farmId,
                kind: entry.kind,
                code: await _nextCode(tx, entry.farmId, entry.kind),
                name: entry.name,
                unitId: entry.unitId,
                active: entry.active,
              )
            : entry;
        await _saveInTransaction(
          tx,
          actual,
          expectedRevision: expectedRevision,
          actorUid: actorUid,
          reason: reason,
          occurredAt: occurredAt,
          authorize: authorize,
        );
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const CatalogFailure('catalog.duplicate');
      }
      rethrow;
    }
  }

  // Allocated inside the same SQLite write transaction as the entry and audit.
  // Existing codes are considered so upgrades never reuse historical numbers.
  static Future<String> _nextCode(
    DatabaseExecutor tx,
    String farmId,
    CatalogKind kind,
  ) async {
    const prefixes = <CatalogKind, String>{
      CatalogKind.unit: 'DVT',
      CatalogKind.crop: 'CT',
      CatalogKind.machine: 'MAY',
      CatalogKind.worker: 'NS',
      CatalogKind.material: 'VT',
      CatalogKind.taskType: 'CV',
      CatalogKind.supplier: 'NCC',
      CatalogKind.incomeCategory: 'DMTHU',
      CatalogKind.expenseCategory: 'DMCHI',
    };
    final prefix = prefixes[kind]!;
    final rows = await tx.query(
      entriesTable,
      columns: ['code'],
      where: 'farm_id=? AND kind=? AND code LIKE ?',
      whereArgs: [farmId, kind.name, '$prefix-%'],
    );
    var maxNumber = 0;
    final pattern = RegExp('^${RegExp.escape(prefix)}-([0-9]+)\$');
    for (final row in rows) {
      final match = pattern.firstMatch(row['code'] as String);
      if (match != null) {
        final number = int.tryParse(match.group(1)!);
        if (number != null && number > maxNumber) maxNumber = number;
      }
    }
    final existing = await tx.query(
      'company_catalog_sequences_v1',
      columns: ['last_number'],
      where: 'farm_id=? AND kind=?',
      whereArgs: [farmId, kind.name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final last = existing.single['last_number'] as int;
      if (last > maxNumber) maxNumber = last;
    }
    final next = maxNumber + 1;
    await tx.insert('company_catalog_sequences_v1', {
      'farm_id': farmId,
      'kind': kind.name,
      'last_number': next,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return '$prefix-${next.toString().padLeft(6, '0')}';
  }

  Future<void> _saveInTransaction(
    DatabaseExecutor tx,
    CatalogEntry entry, {
    required int? expectedRevision,
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    required void Function() authorize,
  }) async {
    entry.validate();
    authorize();
    final previous = await tx.query(
      entriesTable,
      where: 'id=?',
      whereArgs: [entry.id],
    );
    final old = previous.isEmpty ? null : previous.single;
    if ((old == null && expectedRevision != null) ||
        (old != null &&
            (old['revision'] != expectedRevision ||
                old['farm_id'] != entry.farmId ||
                old['kind'] != entry.kind.name ||
                old['code'] != entry.code))) {
      throw const CatalogFailure('catalog.changed');
    }
    if (entry.unitId != null) {
      final units = await tx.query(
        entriesTable,
        where: 'id=? AND farm_id=? AND kind=? AND active=1',
        whereArgs: [entry.unitId, entry.farmId, CatalogKind.unit.name],
      );
      if (units.isEmpty) throw const CatalogFailure('catalog.unitRequired');
    }
    if (entry.kind == CatalogKind.unit &&
        (!entry.active || (old != null && old['name'] != entry.name)) &&
        (await tx.query(
          entriesTable,
          columns: ['id'],
          where: !entry.active ? 'unit_id=? AND active=1' : 'unit_id=?',
          whereArgs: [entry.id],
          limit: 1,
        )).isNotEmpty) {
      throw const CatalogFailure('catalog.unitInUse');
    }
    if (old != null &&
        entry.kind == CatalogKind.material &&
        old['unit_id'] != entry.unitId) {
      throw const CatalogFailure('catalog.unitImmutable');
    }
    final next = _row(entry, (expectedRevision ?? 0) + 1);
    if (old == null) {
      await tx.insert(entriesTable, next);
    } else {
      await tx.update(
        entriesTable,
        next,
        where: 'id=? AND farm_id=?',
        whereArgs: [entry.id, entry.farmId],
      );
    }
    await projectEntry(tx, entry);
    await _audit(
      tx,
      farmId: entry.farmId,
      actor: actorUid,
      time: occurredAt,
      reason: reason,
      target: entry.id,
      action: old == null ? 'create' : 'update',
      before: old,
      after: next,
    );
    authorize();
  }

  /// Internal business projection shared by local saves and verified receives.
  /// The caller owns the transaction, identity checks and authorization.
  static Future<void> projectEntry(DatabaseExecutor tx, CatalogEntry e) async {
    if (e.kind == CatalogKind.machine || e.kind == CatalogKind.worker) {
      final old = await tx.query(
        'parcel_work_resources',
        where: 'id=?',
        whereArgs: [e.id],
      );
      if (old.isNotEmpty &&
          (old.single['farm_id'] != e.farmId ||
              old.single['kind'] != e.kind.name)) {
        throw const CatalogFailure('catalog.denied');
      }
      final row = {
        'id': e.id,
        'farm_id': e.farmId,
        'kind': e.kind.name,
        'code': e.code,
        'name': e.name,
        'active': e.active ? 1 : 0,
      };
      if (old.isEmpty) {
        await tx.insert('parcel_work_resources', row);
      } else {
        await tx.update(
          'parcel_work_resources',
          row,
          where: 'id=?',
          whereArgs: [e.id],
        );
      }
    }
    if (e.kind == CatalogKind.unit) {
      // A unit rename must update material projections atomically. Preserve
      // warehouse stock, valuation settings and movement history.
      final linkedMaterials = await tx.query(
        entriesTable,
        columns: ['id'],
        where: 'farm_id=? AND kind=? AND unit_id=?',
        whereArgs: [e.farmId, CatalogKind.material.name, e.id],
      );
      for (final material in linkedMaterials) {
        await tx.update(
          'inventory_items_v2',
          {'unit': e.name},
          where: 'id=? AND farm_id=?',
          whereArgs: [material['id'], e.farmId],
        );
      }
    }
    if (e.kind == CatalogKind.material) {
      final unit = (await tx.query(
        entriesTable,
        where: 'id=?',
        whereArgs: [e.unitId],
      )).single['name'];
      final old = await tx.query(
        'inventory_items_v2',
        where: 'id=?',
        whereArgs: [e.id],
      );
      if (old.isNotEmpty && old.single['farm_id'] != e.farmId) {
        throw const CatalogFailure('catalog.denied');
      }
      if (old.isEmpty) {
        await tx.insert('inventory_items_v2', {
          'id': e.id,
          'farm_id': e.farmId,
          'code': e.code,
          'name': e.name,
          'unit': unit,
          'unit_price': 0,
          'supplier': '',
          'stock': 0,
        });
      } else {
        await tx.update(
          'inventory_items_v2',
          {'name': e.name},
          where: 'id=?',
          whereArgs: [e.id],
        );
      }
    }
  }

  @override
  Future<void> request(
    CatalogRequest r, {
    required void Function() authorize,
  }) async {
    await database.transaction((tx) async {
      authorize();
      final row = <String, Object?>{
        'id': r.id,
        'farm_id': r.farmId,
        'actor_uid': r.actorUid,
        'kind': r.kind.name,
        'code': r.code,
        'name': r.name,
        'reason': r.reason,
        'created_at': r.createdAt.toUtc().toIso8601String(),
        'status': 'pending',
      };
      await tx.insert(requestsTable, row);
      await _audit(
        tx,
        farmId: r.farmId,
        actor: r.actorUid,
        time: r.createdAt,
        reason: r.reason,
        target: r.id,
        action: 'request',
        after: row,
      );
      authorize();
    });
  }

  @override
  Future<List<CatalogRequest>> requests(
    String farmId, {
    String? actorUid,
  }) async {
    final rows = await database.query(
      requestsTable,
      where: 'farm_id=?${actorUid == null ? '' : ' AND actor_uid=?'}',
      whereArgs: [farmId, ?actorUid],
      orderBy: 'created_at DESC,id',
    );
    return rows
        .map(
          (r) => CatalogRequest(
            id: r['id'] as String,
            farmId: farmId,
            actorUid: r['actor_uid'] as String,
            kind: CatalogKind.values.byName(r['kind'] as String),
            code: r['code'] as String,
            name: r['name'] as String,
            reason: r['reason'] as String,
            createdAt: DateTime.parse(r['created_at'] as String),
            status: r['status'] as String,
            entryId: r['entry_id'] as String?,
            resolution: r['resolution'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> resolve({
    required String farmId,
    required String requestId,
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    String? entryId,
    CatalogEntry? createEntry,
    required void Function() authorize,
  }) async {
    try {
      await database.transaction((tx) async {
        authorize();
        final rows = await tx.query(
          requestsTable,
          where: 'id=? AND farm_id=?',
          whereArgs: [requestId, farmId],
        );
        if (rows.isEmpty || rows.single['status'] != 'pending') {
          throw const CatalogFailure('catalog.changed');
        }
        final old = rows.single;
        if (createEntry != null) {
          if (entryId != null ||
              createEntry.farmId != farmId ||
              createEntry.kind.name != old['kind'] ||
              !createEntry.active) {
            throw const CatalogFailure('catalog.invalid');
          }
          if (old['actor_uid'] == actorUid) {
            throw const CatalogFailure('catalog.selfApproval');
          }
          // Approvals create a new catalog identity inside this transaction.
          // Allocate a code here, just as direct catalog creation does.
          final approvedEntry = createEntry.code.isEmpty
              ? CatalogEntry(
                  id: createEntry.id,
                  farmId: createEntry.farmId,
                  kind: createEntry.kind,
                  code: await _nextCode(tx, createEntry.farmId, createEntry.kind),
                  name: createEntry.name,
                  unitId: createEntry.unitId,
                  active: createEntry.active,
                )
              : createEntry;
          await _saveInTransaction(
            tx,
            approvedEntry,
            expectedRevision: null,
            actorUid: actorUid,
            reason: reason,
            occurredAt: occurredAt,
            authorize: authorize,
          );
          entryId = createEntry.id;
        }
        if (entryId != null) {
          if (old['actor_uid'] == actorUid) {
            throw const CatalogFailure('catalog.selfApproval');
          }
          final targets = await tx.query(
            entriesTable,
            where: 'id=? AND farm_id=? AND kind=? AND active=1',
            whereArgs: [entryId, farmId, old['kind']],
          );
          if (targets.isEmpty) throw const CatalogFailure('catalog.invalid');
        }
        final next = {
          ...old,
          'status': entryId == null ? 'rejected' : 'approved',
          'entry_id': entryId,
          'resolved_by': actorUid,
          'resolved_at': occurredAt.toUtc().toIso8601String(),
          'resolution': reason,
        };
        await tx.update(
          requestsTable,
          next,
          where: 'id=? AND farm_id=?',
          whereArgs: [requestId, farmId],
        );
        await _audit(
          tx,
          farmId: farmId,
          actor: actorUid,
          time: occurredAt,
          reason: reason,
          target: requestId,
          action: 'resolve',
          before: old,
          after: next,
        );
        authorize();
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const CatalogFailure('catalog.duplicate');
      }
      rethrow;
    }
  }

  /// Imports a pre-existing catalog identity with its original code.
  ///
  /// This is deliberately separate from the normal user-facing creation flow:
  /// migration/restore callers must explicitly choose historical-code import.
  /// Identity, uniqueness and audit rules remain enforced by [save].
  Future<void> importHistoricalEntry(
    CatalogEntry entry, {
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    required void Function() authorize,
  }) {
    if (entry.code.isEmpty) {
      throw const CatalogFailure('catalog.invalid');
    }
    return save(
      entry,
      expectedRevision: null,
      actorUid: actorUid,
      reason: reason,
      occurredAt: occurredAt,
      authorize: authorize,
    );
  }

  /// One-time adoption of already persisted values; never create entries from new form input.
  Future<void> adoptExisting(String farmId) async {
    await database.transaction((tx) async {
      if ((await tx.query(
        'company_catalog_bootstrap_v1',
        where: 'farm_id=?',
        whereArgs: [farmId],
      )).isNotEmpty) {
        return;
      }
      Future<String> adopt(
        CatalogKind kind,
        String value, {
        String? id,
        String? code,
        String? unitId,
        bool active = true,
      }) async {
        final key = nameKey(value);
        final found = await tx.query(
          entriesTable,
          where: 'farm_id=? AND kind=? AND name_key=?',
          whereArgs: [farmId, kind.name, key],
        );
        if (found.isNotEmpty && id == null) return found.single['id'] as String;
        final digest = sha256
            .convert(utf8.encode('$farmId|${kind.name}|${id ?? key}'))
            .toString()
            .substring(0, 16)
            .toUpperCase();
        final entryId = id ?? 'catalog-$digest';
        if ((await tx.query(
          entriesTable,
          where: 'id=?',
          whereArgs: [entryId],
        )).isNotEmpty) {
          return entryId;
        }
        var entryCode = code?.trim().toUpperCase() ?? 'OLD-$digest';
        if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,39}$').hasMatch(entryCode) ||
            (await tx.query(
              entriesTable,
              where: 'farm_id=? AND kind=? AND code=?',
              whereArgs: [farmId, kind.name, entryCode],
            )).isNotEmpty) {
          entryCode = 'OLD-$digest';
        }
        final name = found.isEmpty
            ? value.trim()
            : '${value.trim()} ($entryCode)';
        final row = _row(
          CatalogEntry(
            id: entryId,
            farmId: farmId,
            kind: kind,
            code: entryCode,
            name: name,
            unitId: unitId,
            active: active,
          ),
          1,
        );
        await tx.insert(entriesTable, row);
        await _audit(
          tx,
          farmId: farmId,
          actor: 'migration',
          time: DateTime.now().toUtc(),
          reason: 'Adopt persisted pre-A04 value',
          target: entryId,
          action: 'adopt',
          after: row,
        );
        return entryId;
      }

      for (final r in await tx.query(
        'parcel_work_resources',
        where: 'farm_id=?',
        whereArgs: [farmId],
      )) {
        await adopt(
          CatalogKind.values.byName(r['kind'] as String),
          r['name'] as String,
          id: r['id'] as String,
          code: r['code'] as String,
          active: r['active'] == 1,
        );
      }
      for (final r in await tx.query(
        'inventory_items_v2',
        where: 'farm_id=?',
        whereArgs: [farmId],
      )) {
        final unit = await adopt(CatalogKind.unit, r['unit'] as String);
        await adopt(
          CatalogKind.material,
          r['name'] as String,
          id: r['id'] as String,
          code: r['code'] as String,
          unitId: unit,
        );
      }
      final crops = await tx.rawQuery(
        '''SELECT c.payload_json FROM land_parcel_crops c
        JOIN land_parcels p ON p.id=c.parcel_id WHERE p.farm_id=?''',
        [farmId],
      );
      for (final r in crops) {
        final crop =
            jsonDecode(r['payload_json'] as String) as Map<String, dynamic>;
        final unit = await adopt(CatalogKind.unit, crop['unit'] as String);
        await adopt(CatalogKind.crop, crop['cropType'] as String, unitId: unit);
      }
      await tx.insert('company_catalog_bootstrap_v1', {'farm_id': farmId});
    });
  }
}
