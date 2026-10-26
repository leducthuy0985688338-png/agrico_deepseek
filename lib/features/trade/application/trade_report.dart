import 'package:excel/excel.dart';
import '../../../core/reports/excel_report_layout.dart';
import '../domain/trade.dart';

class TradeReport {
  const TradeReport({
    required this.farm,
    required this.period,
    required this.documents,
    required this.lots,
    required this.payments,
    required this.cash,
  });
  final String farm, period;
  final List<TradeRecord> documents;
  final List<FinishedLot> lots;
  final List<TradePayment> payments;
  final List<Map<String, Object?>> cash;
  bool inPeriod(String day) => day.startsWith('$period-');
  Excel workbook() {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      throw const FormatException('Invalid report month.');
    }
    final e = Excel.createExcel();
    void row(String tab, List<String> cells, {Set<int> numbers = const {}}) {
      e[tab].appendRow([
        for (var i = 0; i < cells.length; i++)
          if (numbers.contains(i) &&
              RegExp(r'^-?\d+(\.\d+)?$').hasMatch(cells[i]) &&
              cells[i].replaceAll(RegExp(r'[-.]'), '').length <= 15)
            cells[i].contains('.')
                ? DoubleCellValue(double.parse(cells[i]))
                : IntCellValue(int.parse(cells[i]))
          else
            TextCellValue(cells[i]),
      ]);
    }

    for (final pair in [
      ['AGRICO', 'Thu hoạch, thành phẩm, mua bán và công nợ'],
      ['Farm', farm],
      ['Month', period],
      ['Exported UTC', DateTime.now().toUtc().toIso8601String()],
      [
        'Scope',
        'Document and cash activity by selected UTC+7 month. Inventory and receivable/payable balances are current at export, not historical month-end. Current void status is shown.',
      ],
      [
        'Money',
        'VND/LAK separate. Invoice total explicitly rounded to whole currency; exact line decimals retained and rounded invoice total allocated conservatively to lines.',
      ],
      [
        'Inventory cost',
        'Finished-goods unit cost entered by Admin at harvest, not automatic absorption of all farm costs. COGS uses the separate Admin-entered issue cost snapshot; it is not silently derived from the receipt price.',
      ],
      [
        'Profit',
        'Revenue from posted sales, not cash receipts. Purchases remain inventory; payments do not create a second expense. Period expenses exclude components already included in production.',
      ],
      [
        'Boundaries',
        'Internal commercial documents; no automatic tax, exchange rate, bank balance or legal invoice claim. Existing payroll/machine observation ledgers are not automatically settled by this report.',
      ],
    ]) {
      row('THONG TIN', pair);
    }
    const tabs = {
      TradeKind.harvest: 'THU HOACH',
      TradeKind.sale: 'BAN HANG',
      TradeKind.purchase: 'MUA HANG',
      TradeKind.expense: 'CHI PHI',
    };
    for (final kind in TradeKind.values) {
      final tab = tabs[kind]!;
      row(tab, [
        'Code',
        'Day',
        'Status',
        'Party code snapshot',
        'Party name snapshot',
        'Source plan ID',
        'Line source ID',
        'Item snapshot',
        'Unit',
        'Quantity',
        'Unit price exact',
        'Line amount exact',
        'Billed line whole currency',
        'Invoice total',
        'Currency',
        'Cost snapshot',
        'Due date',
        'External reference',
        'Cost treatment',
        'Admin issue unit price',
      ]);
      for (final r in documents.where(
        (r) => r.draft.kind == kind && inPeriod(r.draft.day),
      )) {
        final d = r.draft;
        final detail = r.snapshots['lines'] as List?;
        final amounts = TradeMath.lineAmounts(d);
        for (var i = 0; i < d.lines.length; i++) {
          final l = d.lines[i];
          final s = detail == null
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(detail[i] as Map);
          row(
            tab,
            [
              r.code,
              d.day,
              r.status,
              r.snapshots['partyCode'] as String? ?? '',
              r.snapshots['partyName'] as String? ?? '',
              d.planId ?? s['planId'] as String? ?? '',
              l.ref,
              s['name'] as String? ?? l.label,
              s['unit'] as String? ?? '',
              l.quantity,
              l.price,
              l.rawAmount,
              amounts[i],
              i == 0 ? d.billed : '',
              d.currency,
              s['cost'] as String? ?? '',
              d.dueOn ?? '',
              d.reference,
              d.expenseTreatment ?? '',
              l.issuePrice ?? '',
            ],
            numbers: {9, 10, 11, 12, 13, 15},
          );
        }
      }
    }
    row('TON THANH PHAM', [
      'Lot',
      'Harvest ID',
      'Plan ID',
      'Harvest day',
      'Product ID',
      'Name snapshot',
      'Unit',
      'Original quantity',
      'Current quantity',
      'Unit cost snapshot',
      'Currency',
      'Current value',
    ]);
    for (final l in lots) {
      row(
        'TON THANH PHAM',
        [
          l.code,
          l.harvestId,
          l.planId,
          l.day,
          l.itemId,
          l.itemName,
          l.unit,
          ExactDecimal.quantityFromUnits(l.originalUnits).toString(),
          l.quantity,
          l.price,
          l.currency,
          (ExactDecimal.parse(l.quantity) * ExactDecimal.parse(l.price))
              .toString(),
        ],
        numbers: {7, 8, 9, 11},
      );
    }
    row('THU CHI', [
      'Code',
      'Day',
      'Kind',
      'Amount',
      'Currency',
      'Category',
      'Description',
      'Finance ID',
    ]);
    for (final f in cash.where(
      (f) => inPeriod((f['occurred_at'] as String).substring(0, 10)),
    )) {
      if (f['organization_id'] != farm) {
        throw StateError('Cash book farm mismatch.');
      }
      row(
        'THU CHI',
        [
          f['code'] as String,
          (f['occurred_at'] as String).substring(0, 10),
          f['kind'] as String,
          '${f['amount_minor']}',
          f['currency'] as String,
          f['category'] as String,
          f['description'] as String? ?? '',
          f['id'] as String,
        ],
        numbers: {3},
      );
    }
    row('CONG NO', [
      'Code',
      'AR/AP',
      'Party',
      'Original day',
      'Due date',
      'Invoice total',
      'Paid net',
      'Current remaining',
      'Currency',
      'Overdue days',
    ]);
    final debt = documents.where(
      (r) => r.status == 'posted' && r.draft.kind != TradeKind.harvest,
    );
    final today = DateTime.parse(TradeMath.day());
    for (final r in debt) {
      final overdue = today.difference(DateTime.parse(r.draft.dueOn!)).inDays;
      row(
        'CONG NO',
        [
          r.code,
          r.draft.kind == TradeKind.sale ? 'AR' : 'AP',
          r.snapshots['partyName'] as String? ?? r.draft.partyId!,
          r.draft.day,
          r.draft.dueOn!,
          r.draft.billed,
          r.paid,
          r.balance,
          r.draft.currency,
          '${overdue > 0 ? overdue : 0}',
        ],
        numbers: {5, 6, 7, 9},
      );
    }
    row('TUOI NO', [
      'Currency',
      'AR/AP',
      'Not overdue',
      '1–30 days',
      '31–60 days',
      '61–90 days',
      'Over 90 days',
      'Total',
    ]);
    for (final currency in ['VND', 'LAK']) {
      for (final ar in [true, false]) {
        final buckets = List.filled(5, '0');
        for (final r in debt.where(
          (r) =>
              r.draft.currency == currency &&
              (r.draft.kind == TradeKind.sale) == ar,
        )) {
          final days = today.difference(DateTime.parse(r.draft.dueOn!)).inDays;
          final bucket = days <= 0
              ? 0
              : days <= 30
              ? 1
              : days <= 60
              ? 2
              : days <= 90
              ? 3
              : 4;
          buckets[bucket] = TradeMath.total([buckets[bucket], r.balance]);
        }
        row(
          'TUOI NO',
          [currency, ar ? 'AR' : 'AP', ...buckets, TradeMath.total(buckets)],
          numbers: {2, 3, 4, 5, 6, 7},
        );
      }
    }
    row('THANH TOAN', [
      'Payment ID',
      'Source document',
      'Finance code',
      'Day',
      'Amount',
      'Currency',
      'Reference',
      'Reversed',
    ]);
    final byId = {for (final d in documents) d.draft.id: d};
    for (final p in payments.where((p) => inPeriod(p.day))) {
      row(
        'THANH TOAN',
        [
          p.id,
          byId[p.documentId]?.code ?? p.documentId,
          p.financeCode,
          p.day,
          p.amount,
          p.currency,
          p.reference,
          p.reversed ? 'Yes' : 'No',
        ],
        numbers: {4},
      );
    }
    row('KET QUA KY', [
      'Currency',
      'Sales revenue',
      'Finished-goods COGS',
      'Gross margin',
      'Period expenses',
      'Indicative result',
      'Receipts',
      'Payments',
      'Cash movement',
      'Production components excluded',
    ]);
    for (final currency in ['VND', 'LAK']) {
      final docs = documents.where(
        (r) =>
            r.status == 'posted' &&
            r.draft.currency == currency &&
            inPeriod(r.draft.day),
      );
      final sales = docs.where((r) => r.draft.kind == TradeKind.sale);
      final revenue = TradeMath.total(sales.map((r) => r.draft.billed));
      final cogs = TradeMath.total(
        sales.expand(
          (r) => (r.snapshots['lines'] as List).map(
            (l) => (l as Map)['cost'] as String,
          ),
        ),
      );
      final expense = TradeMath.total(
        docs
            .where(
              (r) =>
                  r.draft.kind == TradeKind.expense &&
                  r.draft.expenseTreatment == 'periodExpense',
            )
            .map((r) => r.draft.billed),
      );
      final component = TradeMath.total(
        docs
            .where(
              (r) =>
                  r.draft.kind == TradeKind.expense &&
                  r.draft.expenseTreatment == 'includedInProduction',
            )
            .map((r) => r.draft.billed),
      );
      String cashTotal(String kind) => TradeMath.total(
        cash
            .where(
              (f) =>
                  f['currency'] == currency &&
                  f['kind'] == kind &&
                  inPeriod((f['occurred_at'] as String).substring(0, 10)),
            )
            .map((f) => '${f['amount_minor']}'),
      );
      final thu = cashTotal('THU'), chi = cashTotal('CHI');
      row(
        'KET QUA KY',
        [
          currency,
          revenue,
          cogs,
          TradeMath.subtract(revenue, cogs),
          expense,
          TradeMath.subtract(TradeMath.subtract(revenue, cogs), expense),
          thu,
          chi,
          TradeMath.subtract(thu, chi),
          component,
        ],
        numbers: {1, 2, 3, 4, 5, 6, 7, 8, 9},
      );
    }
    row('THEO KE HOACH', [
      'Plan ID',
      'Currency',
      'Sales revenue allocated',
      'COGS allocated',
      'Gross margin',
    ]);
    final planValues = <String, List<String>>{};
    for (final r in documents.where(
      (r) =>
          r.status == 'posted' &&
          r.draft.kind == TradeKind.sale &&
          inPeriod(r.draft.day),
    )) {
      for (final detail in r.snapshots['lines'] as List) {
        final l = detail as Map;
        final key = '${l['planId']}|${r.draft.currency}';
        final totals = planValues.putIfAbsent(key, () => ['0', '0']);
        totals[0] = TradeMath.total([totals[0], l['billed'] as String]);
        totals[1] = TradeMath.total([totals[1], l['cost'] as String]);
      }
    }
    for (final entry in planValues.entries) {
      final key = entry.key.split('|');
      row(
        'THEO KE HOACH',
        [
          key[0],
          key[1],
          entry.value[0],
          entry.value[1],
          TradeMath.subtract(entry.value[0], entry.value[1]),
        ],
        numbers: {2, 3, 4},
      );
    }
    e.delete('Sheet1');
    for (final sheet in e.tables.values) {
      for (var col = 0; col < sheet.maxColumns; col++) {
        sheet.setColumnWidth(col, 26);
      }
    }
    return e;
  }

  List<int> bytes() => encodeReportWorkbook(workbook());
}
