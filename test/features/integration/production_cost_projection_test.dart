import 'dart:convert';
import 'package:agrico_deepseek/core/production/source_governance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_projection.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_export.dart';
import 'package:agrico_deepseek/features/integration/domain/production_cost_entry.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_snapshot.dart';

void main() {
  late Map<String, List<Map<String, Object?>>> tables;
  late List<Map<String, Object?>> machineAudit, personnelAudit, tradeAudit;
  void audit(
    List<Map<String, Object?>> target,
    String id,
    String create,
    String approve,
  ) {
    for (final action in [create, approve]) {
      target.add({
        'id': target.length + 1,
        'farm_id': 'f',
        'entity_id': id,
        'action': action,
        'actor_id': action == create ? 'creator' : 'approver',
        'occurred_at': '2026-10-20T10:00:00Z',
      });
    }
  }

  void machine(
    String id,
    String plan,
    String amount, {
    String currency = 'VND',
    String day = '2026-10-20',
    String status = 'approved',
    bool trace = true,
  }) {
    tables['machine_runs_v1']!.add({
      'id': id,
      'farm_id': 'f',
      'amount': amount,
      'currency': currency,
      'day': day,
      'status': status,
      'revision': 1,
      'body': '{}',
    });
    tables['machine_costs_v1']!.add({
      'source_id': id,
      'farm_id': 'f',
      'plan_id': plan,
      'amount': amount,
      'currency': currency,
      'minutes': 240,
    });
    if (trace) audit(machineAudit, id, 'run.create', 'run.approve');
  }

  void labor(
    String id,
    String plan,
    String amount, {
    String currency = 'VND',
    String status = 'approved',
    String? machineId,
  }) {
    tables['personnel_entries_v1']!.add({
      'id': id,
      'farm_id': 'f',
      'business_day': '2026-10-20',
      'currency': currency,
      'status': status,
      'revision': 1,
      'machine_id': machineId,
      'total_amount': amount,
    });
    tables['production_labor_costs_v1']!.add({
      'entry_id': id,
      'plan_id': plan,
      'amount': amount,
      'currency': currency,
      'farm_id': 'f',
    });
    audit(personnelAudit, id, 'entry.create', 'entry.approve');
  }

  IntegrationSnapshot snapshot({
    bool locked = false,
    Set<String> unavailable = const {},
  }) => IntegrationSnapshot(
    farm: 'f',
    period: '2026-10',
    tables: tables,
    closingRevision: locked ? 1 : null,
    machineAudit: machineAudit,
    sourceAudit: {'personnel': personnelAudit, 'trade': tradeAudit},
    unavailableTables: unavailable,
    sourceCoverageVerified: true,
  );
  ProductionCostGroup group(
    ProductionCostProjection p, {
    String currency = 'VND',
    String? plan,
  }) => p
      .groups(byPlan: plan != null)
      .firstWhere(
        (g) =>
            g.parcelId == 'parcel' &&
            g.currency == currency &&
            g.planId == plan,
      );
  void sale({
    String status = 'posted',
    String day = '2026-10-20',
    String? voidDay,
    String currency = 'VND',
  }) {
    tables['trade_documents_v1']!.add({
      'id': 'sale',
      'farm_id': 'f',
      'kind': 'sale',
      'status': status,
      'revision': 1,
      'day': day,
      'void_day': voidDay,
      'currency': currency,
      'body': '{}',
      'snapshot': jsonEncode({
        'lines': [
          {'planId': 'p1', 'billed': '1000', 'cost': '25'},
        ],
      }),
    });
    audit(tradeAudit, 'sale', 'create', 'post');
    if (status == 'void') audit(tradeAudit, 'sale', 'create', 'void');
  }

  setUp(() {
    tables = {
      for (final name in ProductionCostProjection.requiredTables) name: [],
    };
    tables['land_parcels'] = [
      {'id': 'parcel', 'farm_id': 'f', 'parcel_code': 'LO-001'},
    ];
    tables['production_plans_v1'] = [
      for (final pair in [('p1', 'VND'), ('p2', 'VND'), ('p3', 'LAK')])
        {
          'id': pair.$1,
          'farm_id': 'f',
          'parcel_id': 'parcel',
          'code': 'KH-${pair.$1}',
          'currency': pair.$2,
        },
    ];
    machineAudit = [];
    personnelAudit = [];
    tradeAudit = [];
  });
  test(
    'unallocated labor money is reconciled without inventing a destination',
    () {
      labor('partial', 'p1', '50');
      tables['personnel_entries_v1']!.single['total_amount'] = '100';
      final p = ProductionCostProjection(snapshot());
      expect(
        p.entries
            .firstWhere((e) => e.sourceType == 'laborUnallocated')
            .amountExact,
        '50',
      );
      expect(group(p).totalCost, isNull);
    },
  );
  test(
    'linked fuel movement is a component even if it has a production cost row',
    () {
      machine('machine', 'p1', '800000');
      tables['inventory_movements_v2']!.add({
        'id': 'fuel',
        'farm_id': 'f',
        'kind': 'issue',
        'plan_id': 'p1',
        'currency': 'VND',
        'amount_text': '100',
      });
      tables['production_material_costs_v2']!.add({
        'movement_id': 'fuel',
        'farm_id': 'f',
        'plan_id': 'p1',
        'parcel_id': 'parcel',
        'currency': 'VND',
        'amount_text': '100',
        'occurred_at': '2026-10-20T01:00:00Z',
      });
      tables['integration_fuel_issues_v1'] = [
        {'movement_id': 'fuel'},
      ];
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, '800000');
      expect(
        p.entries.firstWhere((e) => e.sourceType == 'material').eligibility,
        CostEligibility.excluded,
      );
    },
  );
  test(
    'old frozen snapshot does not fabricate source coverage certification',
    () {
      final old = IntegrationSnapshot(
        farm: 'f',
        period: '2026-10',
        tables: tables,
        closingRevision: 1,
      );
      final p = ProductionCostProjection(old);
      expect(group(p).totalCost, isNull);
      expect(p.coverageIssues, contains('historicalSourceCoverageUnverified'));
    },
  );
  test(
    'payroll correction keeps signed allocation and original payroll reference',
    () {
      labor('base', 'p1', '100');
      tables['personnel_payroll_adjustments_v1']!.add({
        'id': 'adjust',
        'farm_id': 'f',
        'payroll_id': 'payroll',
        'status': 'approved',
        'approved_revision': 1,
        'currency': 'VND',
        'day': '2026-10-21',
        'creator': 'creator',
        'created_at': '2026-10-21T01:00:00Z',
        'approver': 'approver',
        'approved_at': '2026-10-21T02:00:00Z',
      });
      tables['personnel_payroll_adjustment_costs_v1']!.add({
        'adjustment_id': 'adjust',
        'plan_id': 'p1',
        'amount': '-25',
      });
      final hash = SourceGovernance.digest(
        SourceGovernance.correction(
          tables['personnel_payroll_adjustments_v1']!.single,
          tables['personnel_payroll_adjustment_costs_v1']!,
        ),
      );
      tables[SourceGovernance.versions] = [
        {
          'farm_id': 'f',
          'source_type': 'payrollCorrection',
          'source_id': 'adjust',
          'revision': 2,
          'day': '2026-10-21',
          'status': 'approved',
          'payload_digest': hash,
          'creator': 'creator',
          'created_at': '2026-10-21T01:00:00Z',
          'approver': 'approver',
          'approved_at': '2026-10-21T02:00:00Z',
        },
      ];
      tables[SourceGovernance.audit] = [
        for (final action in ['create', 'approve'])
          {
            'farm_id': 'f',
            'source_type': 'payrollCorrection',
            'source_id': 'adjust',
            'revision': action == 'create' ? 1 : 2,
            'action': action,
            'actor_id': action == 'create' ? 'creator' : 'approver',
            'occurred_at': action == 'create'
                ? '2026-10-21T01:00:00Z'
                : '2026-10-21T02:00:00Z',
            'payload_digest': hash,
          },
      ];
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, '75');
      expect(
        p.entries
            .firstWhere((e) => e.sourceType == 'payrollCorrection')
            .correctionReference,
        'payroll',
      );
    },
  );
  test(
    'VND LAK same parcel, multiple plans and same-day independent documents stay distinct',
    () {
      labor('labor-1', 'p1', '100');
      labor('labor-2', 'p1', '50');
      machine('machine-1', 'p2', '300');
      machine('lak', 'p3', '200', currency: 'LAK');
      sale();
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, '450');
      expect(group(p).revenue, '1000');
      expect(group(p).profit, '550');
      expect(group(p, currency: 'LAK').totalCost, '200');
      expect(group(p, plan: 'p1').totalCost, '150');
      expect(group(p, plan: 'p2').totalCost, '300');
      expect(
        p.entries
            .where((e) => e.eligibility == CostEligibility.eligible)
            .length,
        5,
      );
    },
  );
  test('missing source table is not zero activity', () {
    tables.remove('machine_costs_v1');
    final p = ProductionCostProjection(snapshot());
    expect(group(p).totalCost, isNull);
    expect(group(p).status, 'INCOMPLETE');
    expect(p.coverageIssues, contains('unavailable:machine_costs_v1'));
  });
  test('unavailable SQLite table cannot masquerade as an empty table', () {
    expect(
      group(
        ProductionCostProjection(
          snapshot(unavailable: {'inventory_movements_v2'}),
        ),
      ).totalCost,
      isNull,
    );
  });
  test('complete empty source coverage is no activity with a real zero', () {
    final g = group(ProductionCostProjection(snapshot()));
    expect(g.totalCost, '0');
    expect(g.status, 'NO_ACTIVITY');
  });
  test('unapproved source is visible and does not become an approved zero', () {
    labor('draft', 'p1', '100', status: 'draft');
    final p = ProductionCostProjection(snapshot());
    expect(p.entries.single.eligibility, CostEligibility.pending);
    expect(group(p).amount(ProductionCostCategory.labor), isNull);
    expect(group(p).totalCost, isNull);
  });
  test('void source removes recognized amount without deleting history', () {
    machine('void', 'p1', '100', status: 'void');
    final p = ProductionCostProjection(snapshot());
    expect(p.entries.single.eligibility, CostEligibility.voided);
    expect(group(p).totalCost, '0');
  });
  test(
    'missing currency blocks both currency views without defaulting VND',
    () {
      labor('missing', 'p1', '100');
      tables['production_labor_costs_v1']!.single.remove('currency');
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, isNull);
      expect(group(p, currency: 'LAK').totalCost, isNull);
      expect(p.entries.single.issues, contains('missingOrInvalidCurrency'));
    },
  );
  test(
    'missing plan/parcel is reconciled and blocks falsely complete summaries',
    () {
      labor('missing', 'unknown', '100');
      final p = ProductionCostProjection(snapshot());
      expect(
        p.entries.single.issues,
        containsAll(['missingPlan', 'missingParcel']),
      );
      expect(group(p).totalCost, isNull);
    },
  );
  test(
    'wrong parcel foreign key does not disappear from its real plan group',
    () {
      tables['inventory_movements_v2']!.add({
        'id': 'm',
        'farm_id': 'f',
        'kind': 'issue',
        'amount_text': '50',
        'currency': 'VND',
        'plan_id': 'p1',
      });
      tables['production_material_costs_v2']!.add({
        'movement_id': 'm',
        'plan_id': 'p1',
        'parcel_id': 'bad',
        'amount_text': '50',
        'currency': 'VND',
        'occurred_at': '2026-10-20T01:00:00Z',
      });
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, isNull);
    },
  );
  test('legacy material missing revision and approval stays incomplete', () {
    tables['inventory_movements_v2']!.add({
      'id': 'issue',
      'farm_id': 'f',
      'kind': 'issue',
      'plan_id': 'p1',
      'amount_text': '123.456789',
      'currency': 'VND',
      'priced_by': 'pricer',
    });
    tables['production_material_costs_v2']!.add({
      'movement_id': 'issue',
      'farm_id': 'f',
      'plan_id': 'p1',
      'parcel_id': 'parcel',
      'amount_text': '123.456789',
      'currency': 'VND',
      'occurred_at': '2026-10-20T01:00:00Z',
    });
    final p = ProductionCostProjection(snapshot());
    expect(p.entries.single.amountExact, '123.456789');
    expect(p.entries.single.sourceRevision, isNull);
    expect(p.entries.single.approvedBy, isNull);
    expect(
      p.entries.single.issues,
      containsAll(['missingSourceRevision', 'missingApprovalAudit']),
    );
    expect(group(p).amount(ProductionCostCategory.material), isNull);
  });
  test('duplicate source identity quarantines both amounts', () {
    labor('same', 'p1', '100');
    tables['production_labor_costs_v1']!.add({
      ...tables['production_labor_costs_v1']!.single,
      'amount': '999',
    });
    final p = ProductionCostProjection(snapshot());
    expect(
      p.entries.where((e) => e.eligibility == CostEligibility.eligible),
      isEmpty,
    );
    expect(
      p.entries
          .where((e) => e.sourceType == 'labor')
          .every((e) => e.issues.contains('duplicateSourceIdentity')),
      isTrue,
    );
    expect(group(p).totalCost, isNull);
  });
  test(
    'building the read model repeatedly is idempotent and does not mutate snapshots',
    () {
      labor('one', 'p1', '100');
      final s = snapshot();
      final before = jsonEncode(tables);
      expect(
        group(ProductionCostProjection(s)).totalCost,
        group(ProductionCostProjection(s)).totalCost,
      );
      expect(jsonEncode(tables), before);
    },
  );
  test(
    'cash payroll and material invoice payments are not additional costs',
    () {
      labor('labor', 'p1', '100');
      tables['finance_documents_v2'] = [
        for (final id in ['payroll', 'materials', 'unrelated'])
          {
            'id': id,
            'organization_id': 'f',
            'kind': 'CHI',
            'currency': 'VND',
            'occurred_at': '2026-10-20',
            'parcel_id': 'parcel',
            'amount_minor': 100,
          },
      ];
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, '100');
      expect(
        p.entries
            .where((e) => e.sourceType == 'cash')
            .every((e) => e.eligibility == CostEligibility.excluded),
        isTrue,
      );
    },
  );
  test(
    'machine all-inclusive excludes separately marked driver and fuel expense',
    () {
      machine('run', 'p1', '800000');
      labor('driver', 'p1', '50000', machineId: 'machine');
      tables['trade_documents_v1']!.add({
        'id': 'fuel',
        'farm_id': 'f',
        'kind': 'expense',
        'status': 'posted',
        'revision': 1,
        'day': '2026-10-20',
        'currency': 'VND',
        'total': '200000',
        'body': jsonEncode({'expenseTreatment': 'includedInProduction'}),
      });
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, '800000');
    },
  );
  test(
    'other expense without approved classification is not allocated by area',
    () {
      tables['trade_documents_v1']!.add({
        'id': 'other',
        'farm_id': 'f',
        'kind': 'expense',
        'status': 'posted',
        'revision': 1,
        'day': '2026-10-20',
        'currency': 'VND',
        'total': '500',
        'body': '{}',
      });
      final p = ProductionCostProjection(snapshot());
      expect(group(p).amount(ProductionCostCategory.other), isNull);
      expect(
        p.entries.single.issues,
        contains('noApprovedProductionExpenseAllocationPolicy'),
      );
    },
  );
  test(
    'unallocated machine source money remains visible in reconciliation',
    () {
      machine('partial', 'p1', '400000');
      tables['machine_runs_v1']!.single['amount'] = '800000';
      final p = ProductionCostProjection(snapshot());
      expect(
        p.entries
            .firstWhere((e) => e.sourceType == 'machineUnallocated')
            .amountExact,
        '400000',
      );
      expect(group(p).totalCost, isNull);
    },
  );
  test(
    'period scope excludes other months and unknown dates are not assigned a month',
    () {
      machine('oct', 'p1', '100');
      machine('sep', 'p1', '999', day: '2026-09-20');
      final p = ProductionCostProjection(snapshot());
      expect(group(p).totalCost, '100');
      expect(p.entries.length, 1);
      tables['machine_runs_v1']!.first['day'] = 'bad';
      final unknown = ProductionCostProjection(snapshot());
      expect(unknown.entries.single.accountingPeriod, isNull);
      expect(group(unknown).totalCost, isNull);
    },
  );
  test('source price changes do not reprice persisted approved amounts', () {
    machine('approved', 'p1', '100');
    tables['machine_rates_v1'] = [
      {'amount': '900000'},
    ];
    expect(group(ProductionCostProjection(snapshot())).totalCost, '100');
  });
  test('audit without farm provenance is not used to invent approval', () {
    machine('audit', 'p1', '100');
    for (final e in machineAudit) {
      e.remove('farm_id');
    }
    final p = ProductionCostProjection(snapshot());
    expect(p.entries.single.approvedBy, isNull);
    expect(group(p).totalCost, isNull);
  });
  test(
    'overallocated source cannot leak as an eligible detail even before summary',
    () {
      machine('m', 'p1', '100');
      tables['machine_runs_v1']!.single['amount'] = '50';
      final p = ProductionCostProjection(snapshot());
      expect(
        p.entries.where((e) => e.eligibility == CostEligibility.eligible),
        isEmpty,
      );
      expect(
        p.entries.firstWhere((e) => e.sourceType == 'machine').issues,
        contains('allocatedExceedsSource'),
      );
      expect(group(p).totalCost, isNull);
    },
  );
  test('missing audit is incomplete and not a fabricated approver', () {
    machine('old', 'p1', '100', trace: false);
    final p = ProductionCostProjection(snapshot());
    expect(p.entries.single.approvedBy, isNull);
    expect(group(p).totalCost, isNull);
  });
  test('malformed exact amount is not converted to zero or binary double', () {
    machine('bad', 'p1', 'NaN');
    expect(group(ProductionCostProjection(snapshot())).totalCost, isNull);
  });
  test('sale posted and reversal in same period nets exactly to zero', () {
    sale(status: 'void', voidDay: '2026-10-25');
    final p = ProductionCostProjection(snapshot());
    expect(group(p).revenue, '0');
    expect(
      p.entries
          .where((e) => e.sourceType == 'saleReversal')
          .single
          .correctionReference,
      'sale',
    );
  });
  test('later period reversal is separated from the original sale period', () {
    sale(status: 'void', day: '2026-09-20', voidDay: '2026-10-25');
    expect(group(ProductionCostProjection(snapshot())).revenue, '-1000');
  });
  test(
    'cross-farm source cannot leak as an eligible cost or reconciliation row',
    () {
      machine('secret', 'p1', '100');
      tables['machine_runs_v1']!.single['farm_id'] = 'another';
      final p = ProductionCostProjection(snapshot());
      expect(p.entries, isEmpty);
      expect(group(p).totalCost, isNull);
    },
  );
  test(
    'exact export reconciles plan parcel and currency without Excel formulas',
    () {
      machine('large', 'p1', '9007199254740993.01');
      labor('small', 'p2', '0.123456');
      sale();
      final p = ProductionCostProjection(snapshot(locked: true));
      final book = Excel.createExcel();
      ProductionCostExport.append(book, p);
      book.delete('Sheet1');
      final saved = Excel.decodeBytes(book.encode()!);
      expect(saved.tables.keys, containsAll(ProductionCostExport.tabs));
      expect(
        saved['CHI PHI SAN XUAT ERP'].rows
            .skip(1)
            .firstWhere((r) => r[1]?.value.toString() == 'large')[9]!
            .value,
        TextCellValue('9007199254740993.01'),
      );
      expect(group(p).totalCost, '9007199254740993.133456');
      final plans = p
          .groups(byPlan: true)
          .where((g) => g.currency == 'VND')
          .map((g) => g.totalCost!)
          .toList();
      expect(plans, ['9007199254740993.01', '0.123456', '0']);
      expect(
        saved['GIA THANH THEO LO DAT'].rows[1][10]!.value,
        TextCellValue('9007199254740993.133456'),
      );
      expect(
        saved['GIA THANH THEO LO DAT'].rows[1][12]!.value,
        TextCellValue('true'),
      );
      expect(
        saved.tables.values
            .expand((s) => s.rows)
            .expand((r) => r)
            .where((c) => c?.value is FormulaCellValue),
        isEmpty,
      );
    },
  );
}
