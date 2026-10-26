import 'dart:convert';
import '../../inventory/domain/entities/exact_decimal.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;
import '../../finance/domain/finance_document.dart';
import '../../../core/identity/domain/business_reference_code.dart';

class IntegrationSnapshot {
  IntegrationSnapshot({
    required this.farm,
    required this.period,
    required this.tables,
  });
  final String farm, period;
  final Map<String, List<Map<String, Object?>>> tables;
  List<Map<String, Object?>> rows(String table) => tables[table] ?? const [];
  Map<Object?, Map<String, Object?>> index(String table) => {
    for (final r in rows(table)) r['id']: r,
  };
  static Map<String, dynamic> json(Object? value) => value == null
      ? {}
      : Map<String, dynamic>.from(jsonDecode(value as String) as Map);
  String get from => '${period}-01';
  String get to {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period))
      throw const FormatException('Invalid report period.');
    return DateTime.utc(
      int.parse(period.substring(0, 4)),
      int.parse(period.substring(5, 7)) + 1,
      1,
    ).subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
  }

  bool inPeriod(String day) =>
      day.compareTo(from) >= 0 && day.compareTo(to) <= 0;
  Map<String, dynamic> metadata(String kind, Object? id) {
    final found = rows(
      'integration_report_metadata_v1',
    ).where((r) => r['kind'] == kind && r['entity_id'] == id);
    return found.isEmpty ? {} : json(found.single['body']);
  }

  Map<String, dynamic> parcel(Object? id) {
    final p = index('land_parcels')[id];
    return p == null ? {} : {...p, ...json(p['payload_json'])};
  }

  String parcelCode(Object? id) =>
      '${parcel(id)['parcel_code'] ?? parcel(id)['parcelCode'] ?? id ?? ''}';
  String parcelName(Object? id) => '${parcel(id)['name'] ?? ''}';
  String name(Object? id) =>
      '${index('company_catalog_entries_v1')[id]?['name'] ?? id ?? ''}';
  String code(Object? id) =>
      '${index('company_catalog_entries_v1')[id]?['code'] ?? id ?? ''}';
  String planCode(Object? id) =>
      '${index('production_plans_v1')[id]?['code'] ?? id ?? ''}';
  static String text(Object? value) => value?.toString() ?? '';
  static String sum(Iterable<String> values) => LaborMoney.sum(values);
  static String cashAmount(Map<String, Object?> r) => FinanceDocument(
    id: text(r['id']),
    organizationId: text(r['organization_id']),
    code: text(r['code']),
    kind: BusinessDocumentKind.payment,
    occurredAt: DateTime.parse(r['occurred_at'] as String),
    amountMinor: r['amount_minor'] as int,
    amountScale: (r['amount_scale'] as int?) ?? 0,
    currency: text(r['currency']),
    category: text(r['category']),
  ).amountText;
  bool controlledCash(Object? id) => [
    'integration_cash_links_v1',
    'integration_salary_reversals_v1',
    'personnel_payroll_refunds_v1',
    'trade_settlements_v1',
    'trade_reversals_v1',
  ].any((table) => rows(table).any((r) => r['finance_id'] == id));
  String capitalAmount(Map<String, Object?> row) {
    final tag = metadata('capital', row['id'])['capitalKind'];
    return tag == 'contribution'
        ? cashAmount(row)
        : tag == 'return'
        ? '-${cashAmount(row)}'
        : '';
  }

  String capitalTotal(String currency, {bool before = false}) => sum(
    rows('finance_documents_v2')
        .where(
          (r) =>
              r['currency'] == currency &&
              (before
                  ? (r['occurred_at'] as String)
                            .substring(0, 10)
                            .compareTo(from) <
                        0
                  : inPeriod((r['occurred_at'] as String).substring(0, 10))),
        )
        .map(capitalAmount)
        .where((v) => v.isNotEmpty),
  );
  Set<Object?> get salaryReversed => rows(
    'integration_salary_reversals_v1',
  ).map((r) => r['payment_id']).toSet();
  String salaryAdjustment(Object? payroll, {String? through}) => sum(
    rows('personnel_payroll_adjustments_v1')
        .where(
          (r) =>
              r['payroll_id'] == payroll &&
              r['status'] == 'approved' &&
              (through == null ||
                  (r['day']! as String).compareTo(through) <= 0),
        )
        .map((r) => r['delta']! as String),
  );
  String salaryNet(Object? payroll, {String? through}) => sum([
    index('personnel_payrolls_v1')[payroll]?['net'] as String? ?? '0',
    salaryAdjustment(payroll, through: through),
  ]);
  String salaryRefunded(Object? payroll) => sum(
    rows('personnel_payroll_refunds_v1')
        .where((r) => r['payroll_id'] == payroll)
        .map(
          (r) => r['reverses_id'] == null
              ? r['amount']! as String
              : LaborMoney.minus('0', r['amount']! as String),
        ),
  );
  String salaryPaid(Object? payroll) => LaborMoney.minus(
    sum(
      rows('personnel_payments_v1')
          .where(
            (p) =>
                p['payroll_id'] == payroll && !salaryReversed.contains(p['id']),
          )
          .map((p) => p['amount']! as String),
    ),
    salaryRefunded(payroll),
  );
  String tradePaid(Object? doc) {
    final reversed = rows(
      'trade_reversals_v1',
    ).map((r) => r['payment_id']).toSet();
    return sum(
      rows('trade_settlements_v1')
          .where((p) => p['document_id'] == doc && !reversed.contains(p['id']))
          .map((p) => p['amount'] as String),
    );
  }

  List<String> get warnings {
    final result = <String>[];
    final linked = rows(
      'integration_cash_links_v1',
    ).map((r) => r['source_id']).toSet();
    for (final p in rows('personnel_payments_v1')) {
      if (!linked.contains(p['id']) && !salaryReversed.contains(p['id']))
        result.add('Lương chưa nối sổ tiền: ${p['id']}');
    }
    final machine = {
      ...rows('integration_machine_links_v1').map((r) => r['expense_id']),
      ...rows('integration_fuel_issues_v1').map((r) => r['expense_id']),
    };
    for (final m in rows(
      'machine_expenses_v1',
    ).where((m) => m['status'] == 'approved')) {
      if (!machine.contains(m['id']))
        result.add('Khoản máy chưa phân loại nguồn: ${m['id']}');
    }
    return result;
  }

  String cashTotal(String currency, String kind, {bool before = false}) => sum(
    rows('finance_documents_v2')
        .where(
          (r) =>
              r['currency'] == currency &&
              r['kind'] == kind &&
              (before
                  ? (r['occurred_at'] as String)
                            .substring(0, 10)
                            .compareTo(from) <
                        0
                  : inPeriod((r['occurred_at'] as String).substring(0, 10))),
        )
        .map(cashAmount),
  );
  String materialCost(Object? plan, String currency) => sum(
    rows('production_material_costs_v2')
        .where(
          (r) =>
              r['plan_id'] == plan &&
              r['currency'] == currency &&
              inPeriod(
                LaborMoney.day(DateTime.parse(r['occurred_at'] as String)),
              ),
        )
        .map((r) => r['amount_text'] as String),
  );
  String laborCost(Object? plan, String currency) {
    final entries = index('personnel_entries_v1');
    final parts = rows('production_labor_costs_v1')
        .where(
          (r) =>
              r['plan_id'] == plan &&
              r['currency'] == currency &&
              entries[r['entry_id']]?['status'] == 'approved' &&
              inPeriod(entries[r['entry_id']]!['business_day'] as String),
        )
        .map((r) => r['amount'] as String);
    final additions = rows('personnel_payrolls_v1')
        .where(
          (r) =>
              r['adjustment_plan_id'] == plan &&
              r['currency'] == currency &&
              r['status'] == 'approved' &&
              inPeriod(r['extra_cost_day'] as String),
        )
        .map(
          (r) =>
              (ExactDecimal.parse(r['allowance'] as String) +
                      ExactDecimal.parse(r['bonus'] as String))
                  .toString(),
        );
    final adjustmentIndex = index('personnel_payroll_adjustments_v1');
    final corrections = rows('personnel_payroll_adjustment_costs_v1')
        .where(
          (c) =>
              c['plan_id'] == plan &&
              adjustmentIndex[c['adjustment_id']]?['status'] == 'approved' &&
              adjustmentIndex[c['adjustment_id']]?['currency'] == currency &&
              inPeriod(adjustmentIndex[c['adjustment_id']]!['day']! as String),
        )
        .map((c) => c['amount']! as String);
    return sum([...parts, ...additions, ...corrections]);
  }

  String machineCost(Object? plan, String currency) {
    final runs = index('machine_runs_v1');
    return sum(
      rows('machine_costs_v1')
          .where(
            (r) =>
                r['plan_id'] == plan &&
                r['currency'] == currency &&
                runs[r['source_id']]?['status'] == 'approved' &&
                inPeriod(runs[r['source_id']]!['day'] as String),
          )
          .map((r) => r['amount'] as String),
    );
  }

  String sales(Object? plan, String currency, {bool cogs = false}) {
    final values = <String>[];
    for (final d in rows(
      'trade_documents_v1',
    ).where((d) => d['kind'] == 'sale' && d['currency'] == currency)) {
      final snapshot = json(d['snapshot']);
      if (snapshot['lines'] == null) continue;
      final sign =
          (inPeriod(d['day'] as String) ? 1 : 0) -
          ((d['status'] == 'void' && inPeriod(d['void_day'] as String))
              ? 1
              : 0);
      if (sign == 0) continue;
      for (final line in snapshot['lines'] as List) {
        if (plan != null && line['planId'] != plan) continue;
        values.add(
          sign > 0
              ? line[cogs ? 'cost' : 'billed'] as String
              : '-${line[cogs ? 'cost' : 'billed']}',
        );
      }
    }
    return sum(values);
  }
}
