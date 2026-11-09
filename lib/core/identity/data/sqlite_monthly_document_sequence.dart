import 'package:sqflite/sqflite.dart';

import '../domain/business_reference_code.dart';

/// Allocates a monthly number inside the caller's document-save transaction.
/// The caller must initialize the schema before beginning that transaction.
class SqliteMonthlyDocumentSequence {
  static const table = 'monthly_document_sequences';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        organization_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        year_month TEXT NOT NULL,
        last_sequence INTEGER NOT NULL CHECK(last_sequence BETWEEN 0 AND 999),
        PRIMARY KEY (organization_id, kind, year_month)
      )
    ''');
  }

  /// Reserve a number and write the document with the same [transaction].
  /// Rolling back the transaction rolls back both operations.
  Future<T> saveWithCode<T>({
    required Transaction transaction,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime documentDate,
    required Future<T> Function(String code) save,
  }) async {
    if (organizationId.trim().isEmpty || documentDate.year < 1 || documentDate.year > 9999) {
      throw const FormatException('Invalid organization or document year.');
    }
    final period = '${documentDate.year.toString().padLeft(4, '0')}'
        '${documentDate.month.toString().padLeft(2, '0')}';
    final scope = [organizationId, kind.prefix, period];
    await transaction.rawInsert(
      'INSERT OR IGNORE INTO $table (organization_id, kind, year_month, last_sequence) VALUES (?, ?, ?, 0)',
      scope,
    );
    final changed = await transaction.rawUpdate(
      'UPDATE $table SET last_sequence = last_sequence + 1 '
      'WHERE organization_id = ? AND kind = ? AND year_month = ? AND last_sequence < 999',
      scope,
    );
    if (changed != 1) {
      throw const FormatException('Monthly document sequence is full.');
    }
    final rows = await transaction.rawQuery(
      'SELECT last_sequence FROM $table WHERE organization_id = ? AND kind = ? AND year_month = ?',
      scope,
    );
    final code = BusinessReferenceCode.forDate(
      kind: kind,
      date: documentDate,
      sequence: rows.single['last_sequence']! as int,
    ).toString();
    return save(code);
  }
}
