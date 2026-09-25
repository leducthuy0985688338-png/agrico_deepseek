import 'package:sqflite/sqflite.dart';

import '../../../../core/identity/data/sqlite_monthly_document_sequence.dart';
import '../../../../core/identity/domain/business_reference_code.dart';
import '../../domain/finance_document.dart';

class SqliteFinanceDocumentRepository {
  SqliteFinanceDocumentRepository(this.database,
      {SqliteMonthlyDocumentSequence? sequence})
      : _sequence = sequence ?? SqliteMonthlyDocumentSequence();

  final Database database;
  final SqliteMonthlyDocumentSequence _sequence;
  static const table = 'finance_documents_v2';

  static Future<void> createSchema(DatabaseExecutor db) async {
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
    await db.execute('CREATE INDEX IF NOT EXISTS finance_documents_v2_scope_date '
        'ON $table (organization_id, occurred_at)');
  }

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
    if (id.trim().isEmpty || organizationId.trim().isEmpty ||
        amountMinor <= 0 || currency.trim().isEmpty || category.trim().isEmpty ||
        (parcelId != null && parcelId.trim().isEmpty)) {
      throw const FormatException('Invalid finance document.');
    }
    return database.transaction((tx) => _sequence.saveWithCode(
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
    ));
  }

  Future<List<FinanceDocument>> listByOrganization(String organizationId) async {
    final rows = await database.query(table,
      where: 'organization_id = ?',
      whereArgs: [organizationId],
      orderBy: 'occurred_at DESC, code DESC');
    return rows.map((row) => FinanceDocument(
      id: row['id']! as String,
      organizationId: row['organization_id']! as String,
      code: row['code']! as String,
      kind: BusinessReferenceCode.parse(row['code']! as String).kind,
      occurredAt: DateTime.parse(row['occurred_at']! as String),
      amountMinor: row['amount_minor']! as int,
      currency: row['currency']! as String,
      category: row['category']! as String,
      parcelId: row['parcel_id'] as String?,
      description: row['description'] as String?,
    )).toList(growable: false);
  }
}
