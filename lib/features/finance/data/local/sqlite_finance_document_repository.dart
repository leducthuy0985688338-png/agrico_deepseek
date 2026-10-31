import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../../../core/identity/data/sqlite_monthly_document_sequence.dart';
import '../../../../core/identity/domain/business_reference_code.dart';
import '../../domain/finance_document.dart';
import '../../../../core/approval/native_approval_guard.dart';
import '../../../../core/permissions/authorization.dart';
import '../../../../core/periods/period_lock.dart';

class SqliteFinanceDocumentRepository
    implements FinanceDocumentStore, PendingFinanceDocumentStore {
  SqliteFinanceDocumentRepository(
    this.database, {
    SqliteMonthlyDocumentSequence? sequence,
  }) : _sequence = sequence ?? SqliteMonthlyDocumentSequence();

  final Database database;
  final SqliteMonthlyDocumentSequence _sequence;
  static const table = 'finance_documents_v2';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await NativeApprovalGuard.createSchema(db);
    await SqliteMonthlyDocumentSequence.createSchema(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL,
        code TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('THU', 'CHI')),
        occurred_at TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
        currency TEXT NOT NULL,
        category TEXT NOT NULL,
        parcel_id TEXT,
        description TEXT,
        UNIQUE (organization_id, code)
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((c) => c['name'] == 'amount_scale')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN amount_scale INTEGER NOT NULL DEFAULT 0 CHECK(amount_scale BETWEEN 0 AND 6)',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS finance_documents_v2_scope_date '
      'ON $table (organization_id, occurred_at)',
    );
  }

  @override
  Future<FinanceDocument> createPendingFinance({
    required AuthorizationSubject creator,
    required AuthorizationSubject? Function() currentSubject,
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? parcelId,
    String? description,
    String? beneficiaryPartyId,
  }) => database.transaction((tx) async {
    void check() {
      final s = currentSubject();
      if (s == null ||
          s.userId != creator.userId ||
          s.membershipId != creator.membershipId ||
          s.farmId != organizationId ||
          creator.farmId != organizationId ||
          ![
            PermissionCodes.financeCreate,
            PermissionCodes.cashRecord,
            PermissionCodes.financeView,
            PermissionCodes.cashView,
          ].every(
            (p) => const AuthorizationService().can(
              subject: s,
              permission: p,
              resource: ResourceContext(farmId: organizationId),
            ),
          ))
        throw StateError('Live finance creator permission required.');
    }

    check();
    if (id.trim().isEmpty ||
        ![
          BusinessDocumentKind.receipt,
          BusinessDocumentKind.payment,
        ].contains(kind) ||
        amountMinor <= 0 ||
        amountMinor > 9007199254740991 ||
        !{'VND', 'LAK'}.contains(currency) ||
        category.trim().isEmpty)
      throw const FormatException('Invalid pending finance document.');
    final day = occurredAt.toIso8601String().substring(0, 10);
    if ((await PeriodLock.state(
          tx,
          organizationId,
          day.substring(0, 7),
        ))?['status'] ==
        'closed')
      throw StateError('Finance period is closed.');
    final body = <String, Object?>{
      'kind': kind.prefix,
      'occurredAt': occurredAt.toIso8601String(),
      'day': day,
      'amountMinor': amountMinor.toString(),
      'amountText': amountMinor.toString(),
      'currency': currency,
      'category': category,
      'parcelId': parcelId,
      'description': description,
      'beneficiaryPartyId': beneficiaryPartyId,
    };
    final rows = await tx.query(
      NativeApprovalGuard.pending,
      where: 'id=?',
      whereArgs: [id],
    );
    final digest = PeriodLock.digest(body);
    if (rows.isNotEmpty) {
      if (rows.single['farm_id'] != organizationId ||
          rows.single['creator'] != creator.userId ||
          rows.single['digest'] != digest)
        throw StateError('Pending finance operation identity conflict.');
    } else {
      await tx.insert(NativeApprovalGuard.pending, {
        'id': id,
        'farm_id': organizationId,
        'body': PeriodLock.encode(body),
        'creator': creator.userId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'revision': 1,
        'digest': digest,
        'status': 'pending',
      });
    }
    check();
    return FinanceDocument(
      id: id,
      organizationId: organizationId,
      code: '',
      kind: kind,
      occurredAt: occurredAt,
      amountMinor: amountMinor,
      currency: currency,
      category: category,
      parcelId: parcelId,
      description: description,
    );
  });

  @override
  Future<FinanceDocument> create({
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? parcelId,
    String? description,
  }) async {
    if (kind != BusinessDocumentKind.receipt &&
        kind != BusinessDocumentKind.payment) {
      throw const FormatException('Only THU or CHI is a finance document.');
    }
    if (id.trim().isEmpty ||
        organizationId.trim().isEmpty ||
        amountMinor <= 0 ||
        currency.trim().isEmpty ||
        category.trim().isEmpty ||
        (parcelId != null && parcelId.trim().isEmpty)) {
      throw const FormatException('Invalid finance document.');
    }
    return database.transaction(
      (tx) => _sequence.saveWithCode(
        transaction: tx,
        organizationId: organizationId,
        kind: kind,
        documentDate: occurredAt,
        save: (code) async {
          final document = FinanceDocument(
            id: id,
            organizationId: organizationId,
            code: code,
            kind: kind,
            occurredAt: occurredAt,
            amountMinor: amountMinor,
            currency: currency,
            category: category,
            parcelId: parcelId,
            description: description,
          );
          await tx.insert(table, {
            'id': id,
            'organization_id': organizationId,
            'code': code,
            'kind': kind.prefix,
            // Preserve the entered document date's month used by the code.
            'occurred_at': occurredAt.toIso8601String(),
            'amount_minor': amountMinor,
            'currency': currency,
            'category': category,
            'parcel_id': parcelId,
            'description': description,
          }, conflictAlgorithm: ConflictAlgorithm.abort);
          return document;
        },
      ),
    );
  }

  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    final rows = await database.query(
      table,
      where: 'organization_id = ?',
      whereArgs: [organizationId],
      orderBy: 'occurred_at DESC, code DESC',
    );
    final available = (await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    final settlementIds = <Object?>{};
    for (final link in [
      'integration_cash_links_v1',
      'integration_salary_reversals_v1',
      'trade_settlements_v1',
      'trade_reversals_v1',
    ]) {
      if (available.contains(link))
        settlementIds.addAll(
          (await database.query(
            link,
            columns: ['finance_id'],
            where: 'farm_id=?',
            whereArgs: [organizationId],
          )).map((r) => r['finance_id']),
        );
    }
    final capitalIds = <Object?>{};
    if (available.contains('integration_report_metadata_v1')) {
      for (final row in await database.query(
        'integration_report_metadata_v1',
        where: "farm_id=? AND kind='capital'",
        whereArgs: [organizationId],
      )) {
        final tag = (jsonDecode(row['body'] as String) as Map)['capitalKind'];
        if (tag == 'contribution' || tag == 'return')
          capitalIds.add(row['entity_id']);
      }
    }
    return rows
        .map(
          (row) => FinanceDocument(
            id: row['id']! as String,
            organizationId: row['organization_id']! as String,
            code: row['code']! as String,
            kind: BusinessReferenceCode.parse(row['code']! as String).kind,
            occurredAt: DateTime.parse(row['occurred_at']! as String),
            amountMinor: row['amount_minor']! as int,
            amountScale: (row['amount_scale'] as int?) ?? 0,
            isSettlement: settlementIds.contains(row['id']),
            isFinancing: capitalIds.contains(row['id']),
            currency: row['currency']! as String,
            category: row['category']! as String,
            parcelId: row['parcel_id'] as String?,
            description: row['description'] as String?,
          ),
        )
        .toList(growable: false);
  }
}
