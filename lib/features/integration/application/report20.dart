import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../../../core/reports/excel_report_layout.dart';
import '../domain/integration_snapshot.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney, MoneyRounding;
import '../../trade/domain/trade.dart' show TradeMath, ExactDecimal;
import 'report20_headers.dart';

class Report20 {
  Report20(this.snapshot);
  final IntegrationSnapshot snapshot;
  static const numericColumns = <String, Set<int>>{
    'DANH MUC': {4, 6},
    'NHAP KHO': {4, 5, 6},
    'XUAT KHO': {5, 6, 7},
    'THU CHI': {5, 6, 7, 8},
    'TH KHO VA TAI CHINH': {2, 3, 4, 5, 7, 8, 9, 13},
    'LO DAT': {2, 4},
    'LICH TAC VU': {7, 8, 9},
    'VAT TU SD': {6, 7, 8},
    'THU HOACH': {3, 4, 5, 7, 8},
    'THONG KE LO DAT': {2, 3, 4, 5, 6},
    'DANH SACH MAY': {4, 8, 10},
    'LICH SU BAO TRI': {5, 6, 7},
    'NHAT KY VAN HANH': {6, 7, 8, 12},
    'DANH SACH NV': {},
    'PHAN CONG CV': {5},
    'CHAM CONG': {5, 6},
    'BANG LUONG': {3, 4, 5, 6, 7, 8, 9},
    'NANG SUAT LD': {3, 4, 5},
    'KE HOACH SAN XUAT': {7, 8, 9, 10, 11, 12},
    'DASHBOARD': {1, 2},
  };
  final cached = <String, Map<String, String>>{};
  String col(int zero) {
    var n = zero + 1;
    var s = '';
    while (n > 0) {
      n--;
      s = String.fromCharCode(65 + n % 26) + s;
      n ~/= 26;
    }
    return s;
  }

  Excel workbook() {
    final s = snapshot;
    s.to;
    final e = Excel.createExcel();
    final catalog = s.index('company_catalog_entries_v1'),
        plans = s.index('production_plans_v1');
    final items = s.index('inventory_items_v2'),
        workers = s.index('personnel_entries_v1'),
        runs = s.index('machine_runs_v1');
    final headers = {
      for (final entry in report20Headers.entries) entry.key: [...entry.value],
    };
    for (final key in headers.keys) {
      if (key != 'DASHBOARD')
        headers[key]!.addAll(['Tiền tệ', 'Trạng thái / nguồn']);
    }
    headers['TH KHO VA TAI CHINH']!.add('Tồn đầu kỳ');
    headers['TH KHO VA TAI CHINH']![9] = 'DÒNG TIỀN THU−CHI';
    headers['THONG KE LO DAT']![5] = 'THU BÁN − CHI PHÍ SX TRONG KỲ';
    headers['KE HOACH SAN XUAT']![7] = 'NHÂN CÔNG DỰ KIẾN (GIỜ)';
    headers['KE HOACH SAN XUAT']![8] = 'NHÂN CÔNG THỰC TẾ (GIỜ)';
    headers['KE HOACH SAN XUAT']![10] = 'MÁY THỰC TẾ (GIỜ)';
    headers['THU HOACH']![8] = 'DOANH THU BÁN LÔ TRONG KỲ';

    final rows = <String, List<List<String>>>{
      for (final key in headers.keys) key: [],
    };
    void add(
      String tab,
      List<Object?> values, {
      String currency = '',
      String state = '',
    }) {
      final head = headers[tab]!;
      final original = report20Headers[tab]!.length;
      final line = values.take(original).map(IntegrationSnapshot.text).toList();
      while (line.length < original) line.add('');
      if (tab != 'DASHBOARD') line.addAll([currency, state]);
      while (line.length < head.length) line.add('');
      rows[tab]!.add(line);
    }

    String name(Object? id) => s.name(id);
    String code(Object? id) => s.code(id);
    String pc(Object? id) => s.parcelCode(id);
    String pn(Object? id) => s.parcelName(id);
    Map<String, dynamic> json(Object? v) => IntegrationSnapshot.json(v);
    String value(Object? v) => IntegrationSnapshot.text(v);
    String sum(Iterable<String> values) => IntegrationSnapshot.sum(values);
    String minus(String a, String b) => TradeMath.subtract(a, b);
    String day(Object? stamp) =>
        LaborMoney.day(DateTime.parse(stamp as String));
    String qty(int units) => ExactDecimal.quantityFromUnits(units).toString();
    String localTime(Object? stamp) => stamp == null
        ? ''
        : DateTime.parse(stamp as String)
              .toUtc()
              .add(const Duration(hours: 7))
              .toIso8601String()
              .substring(0, 16)
              .replaceAll('T', ' ');
    String hours(int minutes) =>
        LaborMoney.fraction('$minutes', 1, 60, 6, MoneyRounding.halfUp);
    bool included(Object? day) => s.inPeriod(value(day));
    final moves = s.rows('inventory_movements_v2').toList()
      ..sort(
        (a, b) =>
            (a['occurred_at'] as String).compareTo(b['occurred_at'] as String),
      );
    for (final c in catalog.values) {
      if (!{'material', 'product'}.contains(c['kind'])) continue;
      final item = items[c['id']];
      if (item == null) continue;
      add('DANH MUC', [
        c['code'],
        c['name'],
        c['kind'],
        item['unit'],
        item['unit_price_text'] ?? '',
        item['supplier'],
        s.metadata('stock', item['id'])['minimumQuantity'] ?? '',
        c['active'] == 1 ? 'Đang dùng' : 'Ngừng',
      ], state: value(c['id']));
    }
    for (final m in moves.where((m) => included(day(m['occurred_at'])))) {
      final item = items[m['item_id']]!;
      final receipt = m['kind'] == 'receipt';
      final links = s
          .rows('trade_stock_links_v1')
          .where((l) => l['movement_id'] == m['id']);
      final doc = links.isEmpty
          ? null
          : s.index('trade_documents_v1')[links.single['document_id']];
      final party = doc == null
          ? ''
          : value(json(doc['snapshot'])['partyName']);
      final quantity = qty(m['quantity_units'] as int);
      if (receipt)
        add(
          'NHAP KHO',
          [
            day(m['occurred_at']),
            m['code'],
            item['code'],
            item['name'],
            quantity,
            m['unit_price_text'] ?? '',
            m['amount_text'] ?? '',
            party,
            doc?['code'] ?? m['id'],
          ],
          currency: value(m['currency']),
          state:
              '${value(m['id'])} · kho:${value(m['warehouse_id'])}${m['transfer_id'] == null ? '' : ' · chuyển kho:${value(m['transfer_id'])}'}',
        );
      else
        add(
          'XUAT KHO',
          [
            day(m['occurred_at']),
            m['code'],
            m['plan_id'] == null ? (doc?['kind'] ?? 'Xuất khác') : 'Sản xuất',
            item['code'],
            item['name'],
            quantity,
            m['unit_price_text'] ?? '',
            m['amount_text'] ?? '',
            party,
            doc?['code'] ?? m['id'],
          ],
          currency: value(m['currency']),
          state:
              '${value(m['id'])} · kho:${value(m['warehouse_id'])}${m['transfer_id'] == null ? '' : ' · chuyển kho:${value(m['transfer_id'])}'}',
        );
    }
    for (final item in items.values) {
      final own = moves.where((m) => m['item_id'] == item['id']);
      int units(bool receipt, bool before) => own
          .where(
            (m) =>
                (m['kind'] == 'receipt') == receipt &&
                (before
                    ? day(m['occurred_at']).compareTo(s.from) < 0
                    : included(day(m['occurred_at']))),
          )
          .fold<int>(0, (n, m) => n + (m['quantity_units'] as int));
      final opening = units(true, true) - units(false, true),
          incoming = units(true, false),
          outgoing = units(false, false);
      final minimum = value(s.metadata('stock', item['id'])['minimumQuantity']);
      final below =
          minimum.isNotEmpty &&
          ExactDecimal.parse(
                qty(opening + incoming - outgoing),
              ).compareTo(ExactDecimal.parse(minimum)) <
              0;
      add('TH KHO VA TAI CHINH', [
        item['code'],
        item['name'],
        qty(incoming),
        qty(outgoing),
        qty(opening + incoming - outgoing),
        minimum,
        minimum.isEmpty
            ? 'Chưa khai báo tồn tối thiểu'
            : below
            ? 'Dưới tồn tối thiểu'
            : 'Đủ tồn',
        '',
        '',
        '',
        'Đơn vị: ${item['unit']}',
      ]);
      rows['TH KHO VA TAI CHINH']!.last[headers['TH KHO VA TAI CHINH']!.indexOf(
        'Tồn đầu kỳ',
      )] = qty(
        opening,
      );
    }
    for (final currency in ['VND', 'LAK']) {
      final receipts = s.cashTotal(currency, 'THU'),
          payments = s.cashTotal(currency, 'CHI');
      add('TH KHO VA TAI CHINH', [
        '',
        'Tổng tiền $currency',
        '',
        '',
        '',
        '',
        '',
        '${receipts}',
        '${payments}',
        minus(receipts, payments),
        'Tổng tiền toàn đơn vị; không phân bổ lặp theo mặt hàng',
      ], currency: currency);
    }
    final cash = s.rows('finance_documents_v2').toList()
      ..sort((a, b) {
        final cmp = (a['occurred_at'] as String).compareTo(
          b['occurred_at'] as String,
        );
        return cmp == 0
            ? (a['code'] as String).compareTo(b['code'] as String)
            : cmp;
      });
    final balances = {
      for (final c in ['VND', 'LAK'])
        c: minus(
          s.cashTotal(c, 'THU', before: true),
          s.cashTotal(c, 'CHI', before: true),
        ),
    };
    for (final f in cash.where(
      (f) => included(value(f['occurred_at']).substring(0, 10)),
    )) {
      final currency = f['currency'] as String;
      final amount = IntegrationSnapshot.cashAmount(f),
          receipt = f['kind'] == 'THU';
      balances[currency] = receipt
          ? sum([balances[currency] ?? '0', amount])
          : minus(balances[currency] ?? '0', amount);
      final salary = s
          .rows('integration_cash_links_v1')
          .where((l) => l['finance_id'] == f['id']);
      final trade = s
          .rows('trade_settlements_v1')
          .where((l) => l['finance_id'] == f['id']);
      Object? party;
      String partyName = '';
      if (salary.isNotEmpty) {
        final p = s.index('personnel_payments_v1')[salary.single['source_id']]!;
        party = s.index('personnel_payrolls_v1')[p['payroll_id']]!['worker_id'];
        partyName = name(party);
      }
      final refunds = s
          .rows('personnel_payroll_refunds_v1')
          .where((r) => r['finance_id'] == f['id']);
      if (refunds.isNotEmpty) {
        final p = s.index(
          'personnel_payrolls_v1',
        )[refunds.single['payroll_id']]!;
        party = p['worker_id'];
        partyName = p['worker_name_snapshot']! as String;
      }
      if (trade.isNotEmpty) {
        final d = s.index('trade_documents_v1')[trade.single['document_id']]!;
        party = d['party_id'];
        partyName = value(json(d['snapshot'])['partyName']);
      }
      add(
        'THU CHI',
        [
          value(f['occurred_at']).substring(0, 10),
          f['code'],
          party == null ? '' : code(party),
          partyName,
          f['description'],
          s.capitalAmount(f),
          receipt ? amount : '0',
          receipt ? '0' : amount,
          balances[currency],
          f['category'],
        ],
        currency: currency,
        state: value(f['id']),
      );
    }
    for (final p in s.rows('land_parcels')) {
      final id = p['id'], payload = s.parcel(id), m = s.metadata('parcel', id);
      add('LO DAT', [
        pc(id),
        pn(id),
        payload['areaM2'] ?? '',
        m['soilType'] ?? '',
        m['pH'] ?? '',
        m['preparedOn'] ?? '',
        payload['note'] ?? '',
      ], state: value(p['active'] == 1 ? 'Đang dùng' : 'Ngừng'));
    }
    for (final task in s.rows('farm_tasks_v2')) {
      if (!included(value(task['due_at']).substring(0, 10))) continue;
      final extension = s.index('production_plan_tasks_v1')[task['id']];
      final plan = extension == null ? null : plans[extension['plan_id']];
      final parcel = task['parcel_id'] ?? plan?['parcel_id'];
      add('PHAN CONG CV', [
        value(task['due_at']).substring(0, 10),
        code(task['worker_resource_id']),
        name(task['worker_resource_id']),
        pc(parcel),
        task['title'],
        extension?['quantity'] ?? '',
        extension?['unit'] ?? '',
      ], state: value(task['status']));
    }
    for (final a in s.rows('production_labor_costs_v1')) {
      final entry = workers[a['entry_id']];
      if (entry == null ||
          entry['status'] != 'approved' ||
          !included(entry['business_day']))
        continue;
      final plan = plans[a['plan_id']]!;
      final t = s.index('farm_tasks_v2')[a['task_id']];
      final rate = s.index('personnel_pay_rates_v1')[entry['rate_id']];
      final standard = (rate?['standard_minutes'] as int?) ?? 480;
      final days = LaborMoney.fraction(
        '${a['regular_minutes']}',
        1,
        standard,
        6,
        MoneyRounding.halfUp,
      );
      add(
        'LICH TAC VU',
        [
          entry['business_day'],
          pc(plan['parcel_id']),
          pn(plan['parcel_id']),
          s.index('production_plan_tasks_v1')[a['task_id']]?['stage'] ?? '',
          t?['title'] ?? 'Công đã duyệt',
          name(entry['worker_id']),
          code(entry['worker_id']),
          days,
          rate?['rate'] ?? '',
          a['amount'],
          '${s.planCode(a['plan_id'])}; OT ${a['overtime_minutes']} phút',
        ],
        currency: value(a['currency']),
        state: value(entry['id']),
      );
    }
    for (final c
        in s
            .rows('production_material_costs_v2')
            .where((c) => included(day(c['occurred_at'])))) {
      add(
        'VAT TU SD',
        [
          day(c['occurred_at']),
          pc(c['parcel_id']),
          pn(c['parcel_id']),
          code(c['item_id']),
          c['item_name'],
          c['unit'],
          qty(c['quantity_units'] as int),
          c['unit_price_text'],
          c['amount_text'],
          '',
          '',
          s.planCode(c['plan_id']),
        ],
        currency: value(c['currency']),
        state: value(c['movement_id']),
      );
    }
    for (final d
        in s
            .rows('trade_documents_v1')
            .where((d) => d['kind'] == 'harvest' && included(d['day']))) {
      final draft = json(d['body']), m = s.metadata('harvest', d['id']);
      final plan = plans[d['plan_id']];
      final parcel = plan?['parcel_id'];
      final lines = draft['lines'] as List;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i] as Map;
        final revenue = <String>[];
        final prices = <String>{};
        final lotIds = s
            .rows('trade_lots_v1')
            .where(
              (lot) =>
                  lot['harvest_id'] == d['id'] && lot['item_id'] == l['ref'],
            )
            .map((lot) => lot['id'])
            .toSet();
        for (final sale
            in s
                .rows('trade_documents_v1')
                .where(
                  (sale) =>
                      sale['kind'] == 'sale' &&
                      sale['currency'] == d['currency'],
                )) {
          final saleSnapshot = json(sale['snapshot']);
          if (saleSnapshot['lines'] == null) continue;
          final saleBody = json(sale['body']);
          final sign =
              (included(sale['day']) ? 1 : 0) -
              (sale['status'] == 'void' && included(sale['void_day']) ? 1 : 0);
          if (sign == 0) continue;
          final details = saleSnapshot['lines'] as List;
          for (var j = 0; j < details.length; j++)
            if (lotIds.contains(details[j]['lotId'])) {
              revenue.add(
                sign > 0
                    ? details[j]['billed'] as String
                    : '-${details[j]['billed']}',
              );
              if (sign > 0 &&
                  ((items[l['ref']]?['unit'] as String?) ?? '').toLowerCase() ==
                      'kg')
                prices.add('${(saleBody['lines'] as List)[j]['price']}');
            }
        }

        add(
          'THU HOACH',
          [
            d['day'],
            pc(parcel),
            pn(parcel),
            i == 0 ? s.parcel(parcel)['areaM2'] ?? '' : '',
            i == 0 ? m['freshKg'] ?? '' : '',
            i == 0 ? m['dryKg'] ?? '' : '',
            m['quality'] ?? '',
            prices.length == 1 ? prices.single : '',
            sum(revenue),
            '${d['code']} · ${name(l['ref'])} ${l['quantity']} ${items[l['ref']]?['unit'] ?? ''}; ${s.planCode(d['plan_id'])}',
          ],
          currency: value(d['currency']),
          state: value(d['status']),
        );
      }
    }
    for (final parcel
        in s.rows('land_parcels').where((p) => p['kind'] == 'fieldPlot')) {
      final id = parcel['id'];
      final ownPlans = plans.values.where((p) => p['parcel_id'] == id);
      final planIds = ownPlans.map((p) => p['id']).toSet();
      final harvests = s
          .rows('trade_documents_v1')
          .where(
            (d) =>
                d['kind'] == 'harvest' &&
                d['status'] == 'posted' &&
                included(d['day']) &&
                planIds.contains(d['plan_id']),
          )
          .map((d) => d['id'])
          .toSet();
      final lots = s
          .rows('trade_lots_v1')
          .where((lot) => harvests.contains(lot['harvest_id']))
          .toList();
      final area = num.tryParse(value(s.parcel(id)['areaM2']));
      String yieldKg = '';
      if (area != null &&
          area > 0 &&
          lots.isNotEmpty &&
          lots.map((l) => l['item_id']).toSet().length == 1 &&
          lots.every((l) => value(l['unit']).toLowerCase() == 'kg')) {
        final denominator = ExactDecimal.parse(area.toStringAsFixed(6));
        if (denominator.coefficient > BigInt.zero &&
            denominator.coefficient <= BigInt.from(9007199254740991))
          yieldKg = LaborMoney.fraction(
            qty(lots.fold<int>(0, (n, l) => n + (l['original_units'] as int))),
            1000000,
            denominator.coefficient.toInt(),
            6,
            MoneyRounding.halfUp,
          );
      }
      for (final currency in ['VND', 'LAK']) {
        final eligible = ownPlans.where((p) => p['currency'] == currency);
        final costs = sum(
          eligible.map(
            (p) => sum([
              s.materialCost(p['id'], currency),
              s.laborCost(p['id'], currency),
              s.machineCost(p['id'], currency),
            ]),
          ),
        );
        final revenue = sum(eligible.map((p) => s.sales(p['id'], currency)));
        add('THONG KE LO DAT', [
          pc(id),
          pn(id),
          s.parcel(id)['areaM2'] ?? '',
          costs,
          revenue,
          minus(revenue, costs),
          yieldKg,
          s.metadata('parcel', id)['evaluation'] ?? '',
          'Chênh lệch thu bán – chi phí SX phát sinh kỳ; chưa phân bổ giá thành tồn cuối kỳ. Diện tích lấy một lần từ thửa.',
        ], currency: currency);
      }
    }
    for (final m in catalog.values.where((r) => r['kind'] == 'machine')) {
      final id = m['id'],
          profile = s
              .rows('machine_profiles_v1')
              .where((r) => r['machine_id'] == id)
              .firstOrNull;
      final p = profile == null ? <String, dynamic>{} : json(profile['body']),
          meta = s.metadata('machine', id);
      final services =
          s
              .rows('machine_expenses_v1')
              .where(
                (r) =>
                    r['machine_id'] == id &&
                    r['kind'] == 'maintenance' &&
                    r['status'] == 'approved',
              )
              .toList()
            ..sort((a, b) => value(b['day']).compareTo(value(a['day'])));
      final ownRuns = runs.values.where(
        (r) => r['machine_id'] == id && r['status'] == 'approved',
      );
      final minutes = ownRuns.fold<int>(0, (n, r) {
        final b = json(r['body']);
        return n +
            DateTime.parse(
              b['endsAt'] as String,
            ).difference(DateTime.parse(b['startsAt'] as String)).inMinutes -
            (b['idleMinutes'] as int);
      });
      for (final currency in ['VND', 'LAK']) {
        add('DANH SACH MAY', [
          m['code'],
          m['name'],
          meta['type'] ?? p['model'] ?? '',
          meta['manufacturer'] ?? '',
          meta['year'] ?? '',
          meta['purchasedOn'] ?? '',
          m['active'] == 1 ? 'Đang dùng' : 'Ngừng',
          meta['warrantyUntil'] ?? '',
          hours(minutes),
          services.isEmpty ? '' : services.first['day'],
          sum(
            services
                .where((r) => json(r['body'])['currency'] == currency)
                .map((r) => json(r['body'])['amount'] as String),
          ),
          p['notes'] ?? '',
        ], currency: currency);
      }
    }
    for (final r
        in s
            .rows('machine_expenses_v1')
            .where((r) => r['kind'] == 'maintenance' && included(r['day']))) {
      final b = json(r['body']), m = s.metadata('maintenance', r['id']);
      add(
        'LICH SU BAO TRI',
        [
          code(r['machine_id']),
          name(r['machine_id']),
          r['day'],
          b['note'],
          m['parts'] ?? '',
          m['quantity'] ?? '',
          m['unitPrice'] ?? '',
          b['amount'],
          m['performer'] ?? '',
          b['reference'],
        ],
        currency: value(b['currency']),
        state: value(r['status']),
      );
    }
    for (final r in runs.values.where((r) => included(r['day']))) {
      final b = json(r['body']);
      final detail = s.metadata('run', r['id']);
      final allocations = b['allocations'] as List;
      final minutes =
          DateTime.parse(
            b['endsAt'] as String,
          ).difference(DateTime.parse(b['startsAt'] as String)).inMinutes -
          (b['idleMinutes'] as int);
      final first = allocations.isEmpty
          ? null
          : plans[allocations.first['planId']];
      add(
        'NHAT KY VAN HANH',
        [
          r['day'],
          code(r['machine_id']),
          name(r['machine_id']),
          name(b['operatorId']),
          localTime(b['startsAt']),
          localTime(b['endsAt']),
          hours(b['idleMinutes'] as int),
          hours(minutes),
          b['outputUnit'] == 'm2' ? b['outputQuantity'] ?? '' : '',
          pc(first?['parcel_id']),
          pn(first?['parcel_id']),
          allocations
              .map((a) => s.index('farm_tasks_v2')[a['taskId']]?['title'] ?? '')
              .where((v) => value(v).isNotEmpty)
              .join('; '),
          detail['fuelConsumedLitres'] ?? '',
          detail['conditionBefore'] ?? '',
          detail['conditionAfter'] ?? '',
          detail['incident'] ?? '',
          b['note'],
          allocations
              .map((a) => '${s.planCode(a['planId'])}: ${a['minutes']} phút')
              .join('; '),
        ],
        currency: value(r['currency']),
        state: '${r['status']}; tiền ${r['amount'] ?? ''}',
      );
    }
    final profiles = {
      for (final p in s.rows('personnel_profiles_v1'))
        p['worker_id']: json(p['profile_json']),
    };
    for (final w in catalog.values.where((r) => r['kind'] == 'worker')) {
      final p = profiles[w['id']] ?? <String, dynamic>{};
      final applicable =
          s
              .rows('personnel_pay_rates_v1')
              .where(
                (rate) =>
                    rate['worker_id'] == w['id'] &&
                    value(rate['effective_on']).compareTo(s.to) <= 0,
              )
              .toList()
            ..sort((a, b) {
              final cmp = value(
                b['effective_on'],
              ).compareTo(value(a['effective_on']));
              return cmp != 0
                  ? cmp
                  : (b['revision'] as int).compareTo(a['revision'] as int);
            });
      final seenRates = <String>{};
      final rateLabels = <String>[];
      for (final rate in applicable) {
        final key =
            '${rate['basis']}|${rate['piece_unit']}|${rate['work_type_id']}';
        if (seenRates.add(key))
          rateLabels.add(
            '${rate['rate']} ${rate['currency']}/${rate['basis']} ${rate['piece_unit']}; từ ${rate['effective_on']}',
          );
      }
      add('DANH SACH NV', [
        w['code'],
        w['name'],
        p['birthOn'] ?? '',
        p['gender'] ?? '',
        p['identityNo'] ?? '',
        p['phone'] ?? '',
        p['address'] ?? '',
        p['position'] ?? '',
        p['department'] ?? '',
        s.metadata('worker', w['id'])['title'] ?? '',
        p['contractStart'] ?? '',
        p['contractEnd'] ?? '',
        rateLabels.join('; '),
        p['bankAccount'] ?? '',
      ], state: w['active'] == 1 ? 'Đang dùng' : 'Ngừng');
    }
    for (final r in workers.values.where((r) => included(r['business_day']))) {
      final allocations = s
          .rows('production_labor_costs_v1')
          .where((a) => a['entry_id'] == r['id'])
          .toList();
      final plan = allocations.isEmpty
          ? null
          : plans[allocations.first['plan_id']];
      add(
        'CHAM CONG',
        [
          r['business_day'],
          code(r['worker_id']),
          name(r['worker_id']),
          localTime(r['starts_at']),
          localTime(r['ends_at']),
          hours(r['break_minutes'] as int),
          hours((r['regular_minutes'] as int) + (r['overtime_minutes'] as int)),
          r['status'],
          pc(plan?['parcel_id']),
          pn(plan?['parcel_id']),
          allocations.map((a) => s.planCode(a['plan_id'])).join('; '),
          r['approved_by'] ?? '',
        ],
        currency: value(r['currency']),
        state: value(r['id']),
      );
    }
    for (final p
        in s
            .rows('personnel_payrolls_v1')
            .where((p) => p['period'] == s.period)) {
      final lines = s
          .rows('personnel_payroll_lines_v1')
          .where((l) => l['payroll_id'] == p['id']);
      final days = sum(
        lines.map((l) {
          final entry = workers[l['entry_id']]!;
          final rate = s.index('personnel_pay_rates_v1')[entry['rate_id']]!;
          return LaborMoney.fraction(
            '${entry['regular_minutes']}',
            1,
            rate['standard_minutes'] as int,
            6,
            MoneyRounding.halfUp,
          );
        }),
      );
      add(
        'BANG LUONG',
        [
          p['period'],
          code(p['worker_id']),
          p['worker_name_snapshot'],
          days,
          sum([
            p['regular'] as String,
            p['overtime'] as String,
            p['piece'] as String,
          ]),
          sum([p['allowance'] as String, p['bonus'] as String]),
          sum([
            p['regular'] as String,
            p['overtime'] as String,
            p['piece'] as String,
            p['allowance'] as String,
            p['bonus'] as String,
          ]),
          p['advance'],
          s.metadata('payroll', p['id'])['insurance'] ?? '',
          p['net'],
        ],
        currency: value(p['currency']),
        state:
            '${p['code']}; ${p['status']}; khấu trừ ${p['deduction']}; đã trả ${s.salaryPaid(p['id'])}; còn ${minus(s.salaryNet(p['id']), s.salaryPaid(p['id']))}; điều chỉnh ${s.salaryAdjustment(p['id'])}; lương hiệu lực ${s.salaryNet(p['id'])}',
      );
    }
    for (final a
        in s
            .rows('personnel_payroll_adjustments_v1')
            .where((r) => included(r['day']))) {
      final p = s.index('personnel_payrolls_v1')[a['payroll_id']]!;
      add(
        'BANG LUONG',
        [
          a['day'],
          code(p['worker_id']),
          p['worker_name_snapshot'],
          '',
          '',
          '',
          '',
          '',
          '',
          a['status'] == 'approved' ? a['delta'] : '',
        ],
        currency: value(a['currency']),
        state:
            '${a['code']} · ${a['status']} · nguồn ${p['code']} · ${a['reason']} · lập ${a['creator']} · duyệt ${a['approver'] ?? ''}',
      );
    }
    for (final w in catalog.values.where((c) => c['kind'] == 'worker')) {
      final records = workers.values.where(
        (r) =>
            r['worker_id'] == w['id'] &&
            r['status'] == 'approved' &&
            included(r['business_day']),
      );
      final units = records
          .where((r) => r['output_quantity'] != null)
          .map((r) => '${r['work_type_id']}|${r['output_unit']}')
          .toSet();
      for (final unit in units) {
        final group = records.where(
          (r) => '${r['work_type_id']}|${r['output_unit']}' == unit,
        );
        final output = sum(group.map((r) => r['output_quantity'] as String));
        final minutes = group.fold<int>(
          0,
          (n, r) =>
              n +
              (r['regular_minutes'] as int) +
              (r['overtime_minutes'] as int),
        );
        final days = sum(
          group.map((r) {
            final rate = s.index('personnel_pay_rates_v1')[r['rate_id']]!;
            return LaborMoney.fraction(
              '${r['regular_minutes']}',
              1,
              rate['standard_minutes'] as int,
              6,
              MoneyRounding.halfUp,
            );
          }),
        );
        add(
          'NANG SUAT LD',
          [
            s.period,
            w['code'],
            w['name'],
            days,
            output,
            minutes == 0
                ? ''
                : LaborMoney.fraction(
                    output,
                    60,
                    minutes,
                    6,
                    MoneyRounding.halfUp,
                  ),
            '',
          ],
          state:
              '${unit.split('|').last}/giờ; ${unit.split('|').first.isEmpty ? 'Chung' : name(unit.split('|').first)}; không tự xếp loại',
        );
      }
    }
    for (final p in plans.values) {
      final currency = p['currency'] as String;
      final machineMinutes = s
          .rows('machine_costs_v1')
          .where(
            (a) =>
                a['plan_id'] == p['id'] &&
                runs[a['source_id']]?['status'] == 'approved',
          )
          .fold<int>(0, (n, a) => n + (a['minutes'] as int));
      final laborMinutes = s
          .rows('production_labor_costs_v1')
          .where(
            (a) =>
                a['plan_id'] == p['id'] &&
                workers[a['entry_id']]?['status'] == 'approved',
          )
          .fold<int>(
            0,
            (n, a) =>
                n +
                (a['regular_minutes'] as int) +
                (a['overtime_minutes'] as int),
          );
      final completions =
          s
              .rows('production_plan_audit_v1')
              .where(
                (a) =>
                    a['entity_id'] == p['id'] &&
                    (a['action'] as String).endsWith('->completed'),
              )
              .toList()
            ..sort(
              (a, b) =>
                  value(b['occurred_at']).compareTo(value(a['occurred_at'])),
            );
      final completed = p['status'] == 'completed' && completions.isNotEmpty
          ? day(completions.first['occurred_at'])
          : '';
      add(
        'KE HOACH SAN XUAT',
        [
          p['code'],
          pc(p['parcel_id']),
          pn(p['parcel_id']),
          p['crop'],
          p['starts_on'],
          p['ends_on'],
          completed,
          p['labor_hours'],
          hours(laborMinutes),
          p['machine_shifts'],
          hours(machineMinutes),
          p['material_budget'],
          s.materialCost(p['id'], currency),
          p['status'],
        ],
        currency: currency,
        state:
            'Nhân công ${s.laborCost(p['id'], currency)}; ca máy ${s.machineCost(p['id'], currency)}; tiền thực tế trong kỳ',
      );
    }
    final warning = s.warnings;
    add('DASHBOARD', [
      'Kỳ phát sinh',
      s.period,
      '',
      'Số dư công nợ tại lúc xuất; không phải chốt sổ quá khứ',
    ]);
    add('DASHBOARD', [
      'Doanh thu bán trong kỳ',
      s.sales(null, 'VND'),
      s.sales(null, 'LAK'),
      'Ghi nhận bán và đảo bán theo ngày chứng từ',
    ]);
    add('DASHBOARD', [
      'Giá vốn xuất Admin',
      s.sales(null, 'VND', cogs: true),
      s.sales(null, 'LAK', cogs: true),
      'Giá vốn đã khai báo, không tự hấp thụ chi phí SX',
    ]);
    add('DASHBOARD', [
      'Lãi gộp',
      minus(s.sales(null, 'VND'), s.sales(null, 'VND', cogs: true)),
      minus(s.sales(null, 'LAK'), s.sales(null, 'LAK', cogs: true)),
      'Không phải lợi nhuận toàn công ty',
    ]);
    add('DASHBOARD', [
      'Vốn góp ròng đã phân loại đầu kỳ',
      s.capitalTotal('VND', before: true),
      s.capitalTotal('LAK', before: true),
      'Chỉ lấy phiếu thu/chi Admin đã phân loại; không suy đoán vốn vay hoặc lợi nhuận.',
    ]);
    add('DASHBOARD', [
      'Góp vốn − hoàn vốn trong kỳ',
      s.capitalTotal('VND'),
      s.capitalTotal('LAK'),
      'Góp vốn dương, hoàn vốn âm; vẫn nằm trong dòng tiền, không cộng thu/chi lần nữa.',
    ]);
    add('DASHBOARD', [
      'Vốn góp ròng đã phân loại cuối kỳ',
      sum([s.capitalTotal('VND', before: true), s.capitalTotal('VND')]),
      sum([s.capitalTotal('LAK', before: true), s.capitalTotal('LAK')]),
      'Không phải số dư tiền mặt hay lợi nhuận.',
    ]);
    final approvedRuns = runs.values
        .where((r) => r['status'] == 'approved' && included(r['day']))
        .toList();
    final measured = approvedRuns
        .where(
          (r) => value(
            s.metadata('run', r['id'])['fuelConsumedLitres'],
          ).isNotEmpty,
        )
        .toList();
    add('DASHBOARD', [
      'Nhiên liệu tiêu thụ đã đo (lít)',
      measured.isEmpty
          ? ''
          : sum(
              measured.map(
                (r) => value(s.metadata('run', r['id'])['fuelConsumedLitres']),
              ),
            ),
      '',
      '${measured.length}/${approvedRuns.length} ca đã nhập số đo. Không coi lít đã cấp là lít tiêu thụ; không tăng chi phí trọn gói.',
    ]);
    add('DASHBOARD', [
      'Ngưỡng tồn tối thiểu',
      '',
      '',
      'Ngưỡng hiện tại lúc xuất; cảnh báo so với tồn cuối kỳ báo cáo. Ô trống là chưa khai báo; số 0 là ngưỡng được nhập rõ.',
    ]);
    add('DASHBOARD', [
      'Thu tiền',
      s.cashTotal('VND', 'THU'),
      s.cashTotal('LAK', 'THU'),
      'Sổ tiền chung, gồm trả lương và bút toán đảo',
    ]);
    add('DASHBOARD', [
      'Chi tiền',
      s.cashTotal('VND', 'CHI'),
      s.cashTotal('LAK', 'CHI'),
      'Chi tiền không cộng lại vào chi phí sản xuất',
    ]);
    add('DASHBOARD', [
      'Dòng tiền thu−chi',
      minus(s.cashTotal('VND', 'THU'), s.cashTotal('VND', 'CHI')),
      minus(s.cashTotal('LAK', 'THU'), s.cashTotal('LAK', 'CHI')),
      'Không dùng làm lợi nhuận',
    ]);
    for (final ar in [true, false]) {
      String debt(String currency) => sum(
        s
            .rows('trade_documents_v1')
            .where(
              (d) =>
                  d['status'] == 'posted' &&
                  d['kind'] != 'harvest' &&
                  (d['kind'] == 'sale') == ar &&
                  d['currency'] == currency,
            )
            .map((d) => minus(d['total'] as String, s.tradePaid(d['id']))),
      );
      add('DASHBOARD', [
        ar ? 'Phải thu hiện tại' : 'Phải trả mua/chi phí hiện tại',
        debt('VND'),
        debt('LAK'),
        'Theo chứng từ, không bù trừ khác tiền tệ',
      ]);
    }
    String salaryBalance(String currency, {bool receivable = false}) => sum(
      s
          .rows('personnel_payrolls_v1')
          .where((p) => p['status'] == 'approved' && p['currency'] == currency)
          .map((p) {
            final value = minus(s.salaryNet(p['id']), s.salaryPaid(p['id']));
            final negative = ExactDecimal.parse(value).isNegative;
            return receivable
                ? (negative ? minus('0', value) : '0')
                : (negative ? '0' : value);
          }),
    );
    add('DASHBOARD', [
      'Lương phải trả hiện tại',
      salaryBalance('VND'),
      salaryBalance('LAK'),
      'Sau điều chỉnh, không bù trừ khoản phải thu nhân viên khác',
    ]);
    add('DASHBOARD', [
      'Nhân viên phải hoàn hiện tại',
      salaryBalance('VND', receivable: true),
      salaryBalance('LAK', receivable: true),
      'Thu hoàn mới tạo THU; duyệt điều chỉnh không tạo dòng tiền',
    ]);
    add('DASHBOARD', [
      'Chưa nối nguồn',
      '${warning.length}',
      '',
      'Cần xử lý trước khi coi sổ tiền đầy đủ',
    ]);
    for (final w in warning)
      add('DASHBOARD', [
        w,
        '',
        '',
        'Nguồn còn nguyên, chưa tự nhập lịch sử vào sổ tiền',
      ]);
    add('DASHBOARD', [
      'Thời điểm xuất',
      DateTime.now().toUtc().toIso8601String(),
      '',
      'UTC; ngày nghiệp vụ UTC+7',
    ]);
    add('DASHBOARD', [
      'Trường chưa ghi nhận',
      '',
      '',
      'Ô trống là chưa có nguồn; không suy đoán pH, bảo hiểm, khối lượng khô, ngưỡng đánh giá hoặc ngày hoàn tất. Bổ sung qua Thông tin báo cáo.',
    ]);
    add('DASHBOARD', [
      'Thời gian công / máy',
      '',
      '',
      'Các giờ bắt đầu/kết thúc hiển thị UTC+7; tiền thực tế trong kỳ; số giờ kế hoạch lũy kế đến lúc xuất. Năng suất chỉ ghép cùng loại việc và đơn vị.',
    ]);
    add('DASHBOARD', [
      'Phạm vi chi phí',
      '',
      '',
      'Vật tư xuất + nhân công phân bổ + giá ca máy trọn gói; nhiên liệu, bảo dưỡng, thanh toán không cộng lại.',
    ]);
    // Native source calculations remain authoritative for exact values. Safe
    // numeric summaries also carry transparent Excel links and cached results.
    for (final entry in headers.entries) {
      final tab = e[entry.key];
      tab.appendRow(entry.value.map((v) => TextCellValue(v)).toList());
      for (final line in rows[entry.key]!) {
        tab.appendRow(
          line.asMap().entries.map<CellValue>((cell) {
            final v = cell.value;
            if ((numericColumns[entry.key]?.contains(cell.key) ?? false) &&
                RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(v) &&
                v.replaceAll(RegExp(r'[-.]'), '').length <= 15)
              return v.contains('.')
                  ? DoubleCellValue(double.parse(v))
                  : IntCellValue(int.parse(v));
            return TextCellValue(v);
          }).toList(),
        );
      }
      for (var c = 0; c < entry.value.length; c++) {
        tab.setColumnWidth(c, c == 0 ? 24 : 30);
      }
    }
    final safeStock =
        rows['NHAP KHO']!.every((r) => r[4].replaceAll('.', '').length <= 15) &&
        rows['XUAT KHO']!.every((r) => r[5].replaceAll('.', '').length <= 15) &&
        rows['TH KHO VA TAI CHINH']!
            .take(items.length)
            .every(
              (r) => [
                2,
                3,
                4,
                13,
              ].every((c) => r[c].replaceAll(RegExp(r'[-.]'), '').length <= 15),
            );
    if (safeStock) {
      for (var i = 0; i < items.length; i++) {
        final n = i + 2;
        final sheet = e['TH KHO VA TAI CHINH'];
        final opening = headers['TH KHO VA TAI CHINH']!.indexOf('Tồn đầu kỳ');
        void formula(int c, String f, String result) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: n - 1))
              .value = FormulaCellValue(
            f,
          );
          cached.putIfAbsent('TH KHO VA TAI CHINH', () => {})['${col(c)}$n'] =
              result;
        }

        final source = rows['TH KHO VA TAI CHINH']![i];
        formula(
          2,
          rows['NHAP KHO']!.isEmpty
              ? '0'
              : 'SUMIF(\'NHAP KHO\'!C2:C${rows['NHAP KHO']!.length + 1},A$n,\'NHAP KHO\'!E2:E${rows['NHAP KHO']!.length + 1})',
          source[2],
        );
        formula(
          3,
          rows['XUAT KHO']!.isEmpty
              ? '0'
              : 'SUMIF(\'XUAT KHO\'!D2:D${rows['XUAT KHO']!.length + 1},A$n,\'XUAT KHO\'!F2:F${rows['XUAT KHO']!.length + 1})',
          source[3],
        );
        formula(4, '${col(opening)}$n+C$n-D$n', source[4]);
      }
    }
    e.delete('Sheet1');
    return e;
  }

  List<int> bytes() {
    cached.clear();
    final workbookData = workbook();
    final archive = ZipDecoder().decodeBytes(
      encodeReportWorkbook(workbookData),
    );
    final book = XmlDocument.parse(
      utf8.decode(archive.findFile('xl/workbook.xml')!.content as List<int>),
    );
    final rels = XmlDocument.parse(
      utf8.decode(
        archive.findFile('xl/_rels/workbook.xml.rels')!.content as List<int>,
      ),
    );
    final targets = {
      for (final r in rels.findAllElements('Relationship'))
        r.getAttribute('Id'): r.getAttribute('Target')!,
    };
    final modified = <String, List<int>>{};
    for (final sheet in book.findAllElements('sheet')) {
      final values = cached[sheet.getAttribute('name')];
      if (values == null) continue;
      final target = targets[sheet.getAttribute('r:id')]!;
      final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile(path)!.content as List<int>),
      );
      for (final c in xml.findAllElements('c')) {
        final value = values[c.getAttribute('r')];
        if (value == null) continue;
        c.children.removeWhere((n) => n is XmlElement && n.name.local == 'v');
        c.children.add(XmlElement(XmlName('v'), [], [XmlText(value)]));
      }
      modified[path] = utf8.encode(xml.toXmlString());
    }
    book.rootElement.children.removeWhere(
      (n) => n is XmlElement && n.name.local == 'calcPr',
    );
    book.rootElement.children.add(
      XmlElement(XmlName('calcPr'), [
        XmlAttribute(XmlName('calcMode'), 'auto'),
        XmlAttribute(XmlName('fullCalcOnLoad'), '1'),
      ]),
    );
    modified['xl/workbook.xml'] = utf8.encode(book.toXmlString());
    final out = Archive();
    for (final f in archive) {
      final data = modified[f.name] ?? f.content as List<int>;
      out.addFile(ArchiveFile(f.name, data.length, data));
    }
    return ZipEncoder().encode(out)!;
  }
}
