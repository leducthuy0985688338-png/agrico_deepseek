import 'package:sqflite/sqflite.dart';
import '../../../core/identity/data/sqlite_monthly_document_sequence.dart';
import '../../../core/identity/domain/business_reference_code.dart';
import '../../finance/domain/finance_document.dart';
import '../../inventory/domain/entities/exact_decimal.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;

abstract final class IntegrationCash {
  static const tables = {
    'integration_cash_links_v1',
    'integration_salary_reversals_v1',
    'integration_machine_links_v1',
    'integration_report_metadata_v1',
  };
  static Future<bool> enabled(DatabaseExecutor db) async => (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='integration_cash_links_v1'",
  )).isNotEmpty;
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS integration_cash_links_v1(farm_id TEXT NOT NULL,source_id TEXT PRIMARY KEY REFERENCES personnel_payments_v1(id),finance_id TEXT NOT NULL UNIQUE REFERENCES finance_documents_v2(id),actor_id TEXT NOT NULL,linked_at TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS integration_salary_reversals_v1(id TEXT PRIMARY KEY,farm_id TEXT NOT NULL,payment_id TEXT NOT NULL UNIQUE REFERENCES personnel_payments_v1(id),finance_id TEXT NOT NULL UNIQUE REFERENCES finance_documents_v2(id),day TEXT NOT NULL,reason TEXT NOT NULL,actor_id TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS integration_machine_links_v1(farm_id TEXT NOT NULL,expense_id TEXT PRIMARY KEY REFERENCES machine_expenses_v1(id),document_id TEXT NOT NULL UNIQUE REFERENCES trade_documents_v1(id),source_amount TEXT NOT NULL,rounding TEXT NOT NULL,actor_id TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS integration_report_metadata_v1(farm_id TEXT NOT NULL,kind TEXT NOT NULL,entity_id TEXT NOT NULL,body TEXT NOT NULL,revision INTEGER NOT NULL,actor_id TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(farm_id,kind,entity_id))''',
    );
  }

  static String amount(Map<String, Object?> row) => FinanceDocument(
    id: row['id'] as String,
    organizationId: row['organization_id'] as String,
    code: row['code'] as String,
    kind: row['kind'] == 'THU'
        ? BusinessDocumentKind.receipt
        : BusinessDocumentKind.payment,
    occurredAt: DateTime.parse(row['occurred_at'] as String),
    amountMinor: row['amount_minor'] as int,
    amountScale: (row['amount_scale'] as int?) ?? 0,
    currency: row['currency'] as String,
    category: row['category'] as String,
  ).amountText;
  static Future<String> write(
    Transaction tx, {
    required String id,
    required String farm,
    required String day,
    required String amountText,
    required String currency,
    required String category,
    required String note,
    required bool receipt,
  }) async {
    LaborMoney.date(day);
    if (day.compareTo(LaborMoney.day(DateTime.now())) > 0 ||
        !{'VND', 'LAK'}.contains(currency) ||
        note.trim().isEmpty)
      throw const FormatException('Invalid financial posting.');
    final value = ExactDecimal.parse(
      ExactDecimal.parse(amountText, maxScale: 6).toString(),
      maxScale: 6,
    );
    if (value.coefficient <= BigInt.zero ||
        value.coefficient > BigInt.from(9007199254740991))
      throw const FormatException('Amount exceeds exact storage range.');
    return SqliteMonthlyDocumentSequence().saveWithCode(
      transaction: tx,
      organizationId: farm,
      kind: receipt
          ? BusinessDocumentKind.receipt
          : BusinessDocumentKind.payment,
      documentDate: DateTime.parse(day),
      save: (code) async {
        await tx.insert('finance_documents_v2', {
          'id': id,
          'organization_id': farm,
          'code': code,
          'kind': receipt ? 'THU' : 'CHI',
          'occurred_at': DateTime.parse(day).toIso8601String(),
          'amount_minor': value.coefficient.toInt(),
          'amount_scale': value.scale,
          'currency': currency,
          'category': category,
          'description': note,
        });
        return id;
      },
    );
  }

  static Future<Set<Object?>> reversed(DatabaseExecutor db) async =>
      await enabled(db)
      ? (await db.query(
          'integration_salary_reversals_v1',
          columns: ['payment_id'],
        )).map((r) => r['payment_id']).toSet()
      : {};
  static Future<List<Map<String, Object?>>> activePayments(
    DatabaseExecutor db,
    String farm, {
    String? payroll,
  }) async {
    final rows = await db.query(
      'personnel_payments_v1',
      where: 'farm_id=?${payroll == null ? '' : ' AND payroll_id=?'}',
      whereArgs: [farm, if (payroll != null) payroll],
    );
    final ids = await reversed(db);
    return rows.where((r) => !ids.contains(r['id'])).toList();
  }

  static Future<void> salary(
    Transaction tx,
    Map<String, Object?> payment,
    String actor, {
    String? existingFinanceId,
  }) async {
    if (!await enabled(tx)) return;
    if (actor.trim().isEmpty) throw const FormatException('Actor required.');
    final id = payment['id'] as String, farm = payment['farm_id'] as String;
    final prior = await tx.query(
      'integration_cash_links_v1',
      where: 'source_id=?',
      whereArgs: [id],
    );
    if (prior.isNotEmpty) {
      if (prior.single['farm_id'] != farm ||
          (existingFinanceId != null &&
              prior.single['finance_id'] != existingFinanceId))
        throw StateError('Payment already linked differently.');
      return;
    }
    if ((await reversed(tx)).contains(id))
      throw StateError('Payment is reversed.');
    final payroll = (await tx.query(
      'personnel_payrolls_v1',
      where: "id=? AND farm_id=? AND status='approved'",
      whereArgs: [payment['payroll_id'], farm],
    )).single;
    final day = payment['business_day'] as String;
    if (day.compareTo(payroll['extra_cost_day'] as String) < 0)
      throw StateError('Payment date precedes earned salary.');
    final finance = existingFinanceId ?? 'integrated:salary:$id';
    if (existingFinanceId == null) {
      await write(
        tx,
        id: finance,
        farm: farm,
        day: day,
        amountText: payment['amount'] as String,
        currency: payment['currency'] as String,
        category: 'INTEGRATED_PAYROLL',
        note: '${payroll['code']} · ${payment['note']}',
        receipt: false,
      );
    } else {
      final rows = await tx.query(
        'finance_documents_v2',
        where: 'id=? AND organization_id=?',
        whereArgs: [finance, farm],
      );
      if (rows.length != 1 ||
          rows.single['kind'] != 'CHI' ||
          rows.single['currency'] != payment['currency'] ||
          amount(rows.single) !=
              ExactDecimal.parse(payment['amount'] as String).toString() ||
          (rows.single['occurred_at'] as String).substring(0, 10) != day)
        throw StateError('Existing CHI does not match the payment.');
      if ((await tx.query(
            'trade_settlements_v1',
            where: 'finance_id=?',
            whereArgs: [finance],
          )).isNotEmpty ||
          (await tx.query(
            'trade_reversals_v1',
            where: 'finance_id=?',
            whereArgs: [finance],
          )).isNotEmpty)
        throw StateError('Cash document already belongs to another source.');
    }
    await tx.insert('integration_cash_links_v1', {
      'farm_id': farm,
      'source_id': id,
      'finance_id': finance,
      'actor_id': actor,
      'linked_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
