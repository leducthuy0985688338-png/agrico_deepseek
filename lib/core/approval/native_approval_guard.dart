import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../periods/period_lock.dart';
import 'sqlite_document_approval.dart';

/// Installed by the application bootstrap, independently of policy activation.
/// Module-only SQLite fixtures are not a bootstrapped application database.
abstract final class NativeApprovalGuard {
  static const marker = 'native_approval_schema_v2';
  static const lease = 'native_approval_execution_v2';
  static const pending = 'finance_pending_documents_v2';
  static const commands = 'native_approval_commands_v2';
  static const reversals = 'finance_document_reversals_v2';
  static Future<bool> enabled(DatabaseExecutor db) async =>
      (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [marker],
      )).isNotEmpty &&
      (await db.query(marker)).isNotEmpty;
  static Future<void> removeForRestore(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'approval_b_%' OR name LIKE 'approval_audit_%' OR name LIKE 'approval_policy_%' OR name LIKE 'document_approval_%')",
    );
    for (final row in rows) {
      final name = row['name'] as String;
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
        throw StateError('Invalid approval guard.');
      }
      await db.execute('DROP TRIGGER "$name"');
    }
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    if (tables.contains(lease) && (await db.query(lease)).isNotEmpty) {
      throw StateError('Approval execution cannot survive backup/restore.');
    }
    if (!tables.contains(pending)) return;
    for (final row in await db.query(pending)) {
      final body = jsonDecode(row['body'] as String) as Map;
      if (row['digest'] != PeriodLock.digest(body) ||
          (row['creator'] as String).isEmpty ||
          row['revision'] != 1) {
        throw StateError('Invalid native finance source identity.');
      }
      final posted = tables.contains('finance_documents_v2')
          ? await db.query(
              'finance_documents_v2',
              where: 'id=?',
              whereArgs: [row['id']],
            )
          : <Map<String, Object?>>[];
      if (row['status'] == 'approved') {
        if (posted.length != 1 ||
            posted.single['organization_id'] != row['farm_id'] ||
            posted.single['currency'] != body['currency'] ||
            posted.single['kind'] != body['kind'] ||
            posted.single['amount_minor'].toString() != body['amountMinor'] ||
            posted.single['occurred_at'] != body['occurredAt']) {
          throw StateError(
            'Approved finance must match its native ledger exactly.',
          );
        }
        await requireProof(
          db,
          row,
          'finance:${row['id']}',
          row['digest'] as String,
        );
      } else if (posted.isNotEmpty)
        throw StateError('Unapproved finance cannot have a ledger entry.');
    }
    if (tables.contains(commands))
      for (final row in await db.query(commands)) {
        if (row['status'] != 'approved') continue;
        final digest = PeriodLock.digest({
          'operation': row['operation'],
          'target': '${row['target_type']}:${row['target_id']}',
          'payload': jsonDecode(row['body'] as String),
          'sourceDigest': row['source_digest'],
        });
        await requireProof(db, row, 'command:${row['id']}', digest);
      }
    if (tables.contains(reversals)) {
      for (final link in await db.query(reversals)) {
        final original = await db.query(
          'finance_documents_v2',
          where: 'id=? AND organization_id=?',
          whereArgs: [link['source_id'], link['farm_id']],
        );
        final reversed = await db.query(
          'finance_documents_v2',
          where: 'id=? AND organization_id=?',
          whereArgs: [link['finance_id'], link['farm_id']],
        );
        final command = await db.query(
          commands,
          where:
              "farm_id=? AND id=? AND status='approved' AND operation='financeReverse'",
          whereArgs: [link['farm_id'], link['command_id']],
        );
        if (original.length != 1 ||
            reversed.length != 1 ||
            command.length != 1 ||
            command.single['target_type'] != 'finance' ||
            command.single['target_id'] != link['source_id'] ||
            link['finance_id'] != 'finance-reversal:${link['command_id']}' ||
            original.single['amount_minor'] !=
                reversed.single['amount_minor'] ||
            original.single['currency'] != reversed.single['currency'] ||
            reversed.single['kind'] !=
                (original.single['kind'] == 'THU' ? 'CHI' : 'THU') ||
            reversed.single['category'] != 'APPROVED_REVERSAL' ||
            (reversed.single['occurred_at'] as String).substring(0, 10) !=
                (jsonDecode(command.single['body'] as String) as Map)['day']) {
          throw StateError(
            'Finance reversal does not match independently approved original.',
          );
        }
      }
    }
  }

  static Future<void> requireProof(
    DatabaseExecutor db,
    Map<String, Object?> source,
    String id,
    String digest,
  ) async {
    final rows = await db.query(
      SqliteDocumentApproval.requests,
      where:
          "farm_id=? AND source_id=? AND source_revision=? AND source_digest=? AND state='approved' AND creator=?",
      whereArgs: [
        source['farm_id'],
        id,
        source['revision'],
        digest,
        source['creator'],
      ],
    );
    if (rows.isEmpty || rows.any((r) => r['decided_by'] == null)) {
      throw StateError('Native posting has no matching B approval proof.');
    }
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $reversals(source_id TEXT PRIMARY KEY REFERENCES finance_documents_v2(id),
      farm_id TEXT NOT NULL,command_id TEXT NOT NULL UNIQUE,finance_id TEXT NOT NULL UNIQUE REFERENCES finance_documents_v2(id))''',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $marker(version INTEGER PRIMARY KEY CHECK(version=1))',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $lease(singleton INTEGER PRIMARY KEY CHECK(singleton=1),
      farm_id TEXT NOT NULL,actor_id TEXT NOT NULL,writes_json TEXT NOT NULL,finance_json TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $pending(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,
      body TEXT NOT NULL,creator TEXT NOT NULL,created_at TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),
      digest TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('pending','approved','rejected')))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS $commands(id TEXT NOT NULL,farm_id TEXT NOT NULL,
      revision INTEGER NOT NULL CHECK(revision>0),operation TEXT NOT NULL,target_type TEXT NOT NULL,target_id TEXT NOT NULL,
      body TEXT NOT NULL,source_digest TEXT NOT NULL,creator TEXT NOT NULL,created_at TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('pending','approved','rejected')),PRIMARY KEY(farm_id,id,revision))''',
    );
  }

  static Future<void> install(DatabaseExecutor db) async {
    await createSchema(db);
    if ((await db.query(lease)).isNotEmpty) {
      throw StateError('Unfinished approval execution; fail closed.');
    }
    final names = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    Future<void> trigger(
      String table,
      String op,
      String key,
      String farm,
      String condition, {
      bool cash = false,
    }) async {
      if (!names.contains(table)) return;
      final allowed = cash
          ? "EXISTS(SELECT 1 FROM $lease l,json_each(l.finance_json) j WHERE l.farm_id=$farm AND j.value=$key)"
          : "EXISTS(SELECT 1 FROM $lease l,json_each(l.writes_json) j WHERE l.farm_id=$farm AND j.value='$table:'||$key)";
      await db.execute(
        "CREATE TRIGGER IF NOT EXISTS approval_b_${table}_${op.toLowerCase()} BEFORE $op ON $table WHEN ($condition) AND NOT ($allowed) BEGIN SELECT RAISE(ABORT,'APPROVAL_B_REQUIRED'); END",
      );
    }

    for (final table in [
      'machine_runs_v1',
      'machine_expenses_v1',
      'personnel_entries_v1',
      'personnel_payrolls_v1',
      'personnel_payroll_adjustments_v1',
      'trade_documents_v1',
    ]) {
      await trigger(
        table,
        'INSERT',
        'NEW.id',
        'NEW.farm_id',
        "NEW.status NOT IN ('draft')",
      );
      await trigger(
        table,
        'UPDATE',
        'NEW.id',
        'NEW.farm_id',
        "NEW.status NOT IN ('draft') OR OLD.status NOT IN ('draft')",
      );
      await trigger(table, 'DELETE', 'OLD.id', 'OLD.farm_id', '1');
    }
    if (names.contains('production_source_versions_v2')) {
      await trigger(
        'production_source_versions_v2',
        'UPDATE',
        'NEW.source_id',
        'NEW.farm_id',
        "NEW.status='approved'",
      );
      await trigger(
        'production_source_versions_v2',
        'INSERT',
        'NEW.source_id',
        'NEW.farm_id',
        "NEW.status='approved'",
      );
    }
    for (final pair in [
      ('machine_costs_v1', 'source_id'),
      ('production_labor_costs_v1', 'entry_id'),
      ('production_expense_costs_v2', 'policy_id'),
    ]) {
      await trigger(
        pair.$1,
        'INSERT',
        'NEW.${pair.$2}',
        'NEW.farm_id',
        "NEW.amount IS NOT NULL",
      );
      await trigger(
        pair.$1,
        'UPDATE',
        'NEW.${pair.$2}',
        'NEW.farm_id',
        "NEW.amount IS NOT NULL OR OLD.amount IS NOT NULL",
      );
      await trigger(pair.$1, 'DELETE', 'OLD.${pair.$2}', 'OLD.farm_id', '1');
    }
    for (final pair in [
      ('personnel_payments_v1', 'id'),
      ('personnel_payroll_refunds_v1', 'id'),
      ('trade_settlements_v1', 'id'),
      ('trade_reversals_v1', 'id'),
      ('integration_salary_reversals_v1', 'id'),
      ('integration_cash_links_v1', 'source_id'),
      (reversals, 'source_id'),
      ('integration_machine_links_v1', 'expense_id'),
      ('integration_fuel_issues_v1', 'expense_id'),
    ]) {
      for (final op in ['INSERT', 'UPDATE', 'DELETE']) {
        final p = op == 'DELETE' ? 'OLD' : 'NEW';
        await trigger(pair.$1, op, '$p.${pair.$2}', '$p.farm_id', '1');
      }
    }
    if (names.contains('finance_documents_v2')) {
      await trigger(
        'finance_documents_v2',
        'INSERT',
        'NEW.id',
        'NEW.organization_id',
        '1',
        cash: true,
      );
      for (final op in ['UPDATE', 'DELETE']) {
        await db.execute(
          "CREATE TRIGGER IF NOT EXISTS approval_b_finance_documents_v2_${op.toLowerCase()} BEFORE $op ON finance_documents_v2 BEGIN SELECT RAISE(ABORT,'IMMUTABLE_POSTED_FINANCE'); END",
        );
      }
    }
    for (final table in [pending, commands]) {
      await trigger(table, 'UPDATE', 'NEW.id', 'NEW.farm_id', '1');
      await trigger(table, 'DELETE', 'OLD.id', 'OLD.farm_id', '1');
      await db.execute(
        "CREATE TRIGGER IF NOT EXISTS approval_b_${table}_create BEFORE INSERT ON $table WHEN NEW.status<>'pending' BEGIN SELECT RAISE(ABORT,'PENDING_REQUIRED'); END",
      );
      final immutable = table == pending
          ? 'OLD.digest<>NEW.digest'
          : 'OLD.operation<>NEW.operation OR OLD.target_type<>NEW.target_type OR OLD.target_id<>NEW.target_id OR OLD.source_digest<>NEW.source_digest';
      await db.execute(
        "CREATE TRIGGER IF NOT EXISTS approval_b_${table}_immutable BEFORE UPDATE ON $table WHEN OLD.status<>'pending' OR NEW.status NOT IN ('approved','rejected') OR OLD.farm_id<>NEW.farm_id OR OLD.id<>NEW.id OR OLD.revision<>NEW.revision OR OLD.creator<>NEW.creator OR OLD.created_at<>NEW.created_at OR OLD.body<>NEW.body OR ($immutable) BEGIN SELECT RAISE(ABORT,'IMMUTABLE_NATIVE_APPROVAL_SOURCE'); END",
      );
    }
    for (final audit in [
      'machine_audit_v1',
      'personnel_audit_v1',
      'trade_audit_v1',
    ]) {
      if (!names.contains(audit)) continue;
      for (final op in ['UPDATE', 'DELETE']) {
        await db.execute(
          "CREATE TRIGGER IF NOT EXISTS approval_b_${audit}_${op.toLowerCase()} BEFORE $op ON $audit BEGIN SELECT RAISE(ABORT,'IMMUTABLE_NATIVE_AUDIT'); END",
        );
      }
    }
    await db.insert(marker, {
      'version': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<T> authorized<T>(
    Transaction tx, {
    required String farm,
    required String actor,
    required Set<String> writes,
    Set<String> financeIds = const {},
    required Future<T> Function() apply,
  }) async {
    await tx.insert(lease, {
      'singleton': 1,
      'farm_id': farm,
      'actor_id': actor,
      'writes_json': jsonEncode(writes.toList()..sort()),
      'finance_json': jsonEncode(financeIds.toList()..sort()),
    });
    try {
      return await apply();
    } finally {
      await tx.delete(lease, where: 'singleton=1');
    }
  }
}
