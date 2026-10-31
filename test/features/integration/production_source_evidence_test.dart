import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agrico_deepseek/features/integration/domain/production_source_evidence.dart';
import 'package:agrico_deepseek/features/integration/domain/production_cost_entry.dart';
import 'package:agrico_deepseek/features/integration/domain/integration_snapshot.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_projection.dart';
import 'package:agrico_deepseek/features/integration/application/production_cost_export.dart';
import 'package:agrico_deepseek/features/integration/application/legacy_cost_reconciliation.dart';

void main() {
  sqfliteFfiInit();
  late Map<String, Object?> movement, cost, plan, payroll;
  late List<Map<String, Object?>> events;
  setUp(() {
    plan = {
      'id': 'p',
      'farm_id': 'f',
      'parcel_id': 'parcel',
      'season_id': 's',
      'currency': 'VND',
    };
    movement = {
      'id': 'issue',
      'code': 'XK-1',
      'farm_id': 'f',
      'item_id': 'item',
      'kind': 'issue',
      'plan_id': 'p',
      'quantity_units': 1500000,
      'unit_price_text': '2',
      'amount_text': '3',
      'currency': 'VND',
      'priced_by': 'pricer',
      'occurred_at': '2026-10-20T01:00:00Z',
      'zero_price_confirmed': 0,
    };
    cost = {
      ...movement,
      'movement_id': 'issue',
      'parcel_id': 'parcel',
      'season_id': 's',
    };
    payroll = {
      'id': 'payroll',
      'farm_id': 'f',
      'worker_id': 'worker',
      'period': '2026-10',
      'code': 'LUONG-1',
      'status': 'approved',
      'currency': 'VND',
      'allowance': '10',
      'bonus': '2',
      'adjustment_plan_id': 'p',
      'extra_cost_day': '2026-10-20',
    };
    events = [
      for (final action in ['payroll.create', 'payroll.approve'])
        {
          'id': action,
          'farm_id': 'f',
          'entity_id': 'payroll',
          'action': action,
          'actor_id': 'actor',
          'occurred_at': '2026-10-20T01:00:00Z',
        },
    ];
  });
  ProductionSourceEvidence material() =>
      ProductionSourceEvidence.material(cost, movement, plan);
  ProductionCostProjection payrollProjection(
    List<Map<String, Object?>> rows, {
    List<Map<String, Object?>> corrections = const [],
    List<Map<String, Object?>> allocations = const [],
  }) => ProductionCostProjection(
    IntegrationSnapshot(
      farm: 'f',
      period: '2026-10',
      sourceCoverageVerified: true,
      sourceAudit: {'personnel': events},
      tables: {
        for (final name in ProductionCostProjection.requiredTables) name: [],
        'production_plans_v1': [plan],
        'land_parcels': [
          {'id': 'parcel', 'farm_id': 'f'},
        ],
        'personnel_payrolls_v1': rows,
        'personnel_payroll_adjustments_v1': corrections,
        'personnel_payroll_adjustment_costs_v1': allocations,
      },
    ),
  );
  test('payroll replay retains one idempotency key and remains incomplete', () {
    final a = payrollProjection([payroll]);
    final b = payrollProjection([payroll]);
    expect(a.entries.single.idempotencyKey, b.entries.single.idempotencyKey);
    expect(a.entries.single.amountExact, '12');
    expect(a.entries.single.eligibility, CostEligibility.incomplete);
    payroll['bonus'] = '3';
    final c = payrollProjection([payroll]);
    expect(c.entries.single.idempotencyKey, a.entries.single.idempotencyKey);
    expect(
      c.sourceEvidence.values.single.observedIdentity,
      isNot(a.sourceEvidence.values.single.observedIdentity),
    );
    expect(c.entries.single.sourceRevision, isNull);
  });
  test(
    'finance THU and CHI remain cash reconciliation, not new revenue or cost',
    () {
      final p = ProductionCostProjection(
        IntegrationSnapshot(
          farm: 'f',
          period: '2026-10',
          sourceCoverageVerified: true,
          tables: {
            for (final name in ProductionCostProjection.requiredTables)
              name: [],
            'production_plans_v1': [plan],
            'land_parcels': [
              {'id': 'parcel', 'farm_id': 'f'},
            ],
            'finance_documents_v2': [
              for (final kind in ['THU', 'CHI'])
                {
                  'id': kind,
                  'organization_id': 'f',
                  'kind': kind,
                  'currency': 'VND',
                  'occurred_at': '2026-10-20',
                  'amount_minor': 99,
                },
            ],
          },
        ),
      );
      expect(p.entries.length, 2);
      expect(
        p.entries.every((e) => e.eligibility == CostEligibility.excluded),
        isTrue,
      );
      expect(
        p.groups().every((g) => g.totalCost == '0' && g.revenue == '0'),
        isTrue,
      );
    },
  );
  test(
    'different IDs cannot bypass active worker period currency identity',
    () {
      final p = payrollProjection([
        payroll,
        {...payroll, 'id': 'other'},
      ]);
      expect(
        p.entries.every(
          (e) => e.issues.contains('duplicatePayrollBusinessIdentity'),
        ),
        isTrue,
      );
    },
  );
  test(
    'cancelled payroll and replacement do not duplicate active extra cost',
    () {
      final p = payrollProjection([
        {...payroll, 'status': 'cancelled'},
        {...payroll, 'id': 'new'},
      ]);
      expect(
        p.entries.where((e) => e.eligibility == CostEligibility.voided).length,
        1,
      );
      expect(
        p.entries.every(
          (e) => !e.issues.contains('duplicatePayrollBusinessIdentity'),
        ),
        isTrue,
      );
      expect(p.entries.last.eligibility, CostEligibility.incomplete);
    },
  );
  test(
    'reused approved correction version quarantines both saved signed amounts',
    () {
      final p = payrollProjection(
        [],
        corrections: [
          for (final id in ['a', 'b'])
            {
              'id': id,
              'farm_id': 'f',
              'payroll_id': 'original',
              'status': 'approved',
              'approved_revision': 2,
              'currency': 'VND',
              'day': '2026-10-20',
              'creator': 'creator',
              'created_at': '2026-10-20T01:00:00Z',
              'approver': 'reviewer',
              'approved_at': '2026-10-20T02:00:00Z',
            },
        ],
        allocations: [
          for (final id in ['a', 'b'])
            {'adjustment_id': id, 'plan_id': 'p', 'amount': '-2'},
        ],
      );
      expect(p.entries.length, 2);
      expect(
        p.entries.every(
          (e) => e.issues.contains('duplicatePayrollCorrectionVersion'),
        ),
        isTrue,
      );
      expect(
        p.entries.every(
          (e) =>
              e.amountExact == '-2' &&
              e.eligibility == CostEligibility.incomplete,
        ),
        isTrue,
      );
    },
  );
  test('native immutable issue is not independently approved or versioned', () {
    final e = material();
    expect(e.state, 'immutableIssueWithoutApproval');
    expect(
      e.issues,
      containsAll([
        'materialRevisionNotPersisted',
        'materialIndependentApprovalNotRecorded',
      ]),
    );
    expect(e.issues.where((i) => i.startsWith('movement')), isEmpty);
  });
  for (final key in [
    'farm_id',
    'item_id',
    'plan_id',
    'quantity_units',
    'unit_price_text',
    'amount_text',
    'currency',
    'priced_by',
    'occurred_at',
    'zero_price_confirmed',
  ]) {
    test('material verifies persisted source field $key', () {
      cost[key] = 'changed';
      expect(material().issues, contains('movementFieldMismatch:$key'));
    });
  }
  test('material detects mismatched document and season', () {
    cost['movement_id'] = 'other';
    cost['season_id'] = 'other';
    expect(
      material().issues,
      containsAll([
        'movementDocumentIdentityMismatch',
        'movementDestinationMismatch',
      ]),
    );
  });
  test(
    'material verifies arithmetic from persisted units and historical price',
    () {
      movement['amount_text'] = cost['amount_text'] = '4';
      expect(material().issues, contains('movementArithmeticMismatch'));
    },
  );
  test(
    'material zero snapshot requires the original explicit confirmation',
    () {
      movement['amount_text'] = cost['amount_text'] = '0';
      movement['unit_price_text'] = cost['unit_price_text'] = '0';
      expect(material().issues, contains('movementArithmeticMismatch'));
      cost['zero_price_confirmed'] = movement['zero_price_confirmed'] = 1;
      expect(material().issues, isNot(contains('movementArithmeticMismatch')));
    },
  );
  test('equal empty pricer fields do not establish source evidence', () {
    cost['priced_by'] = movement['priced_by'] = '';
    expect(
      material().issues,
      contains('movementRequiredFieldMissing:priced_by'),
    );
    expect(material().state, 'sourceMismatch');
  });
  test('missing source is distinct from immutable missing governance', () {
    expect(
      ProductionSourceEvidence.material(cost, null, plan).state,
      'missingSource',
    );
  });
  test(
    'recorded approval evidence is distinct and does not infer the pricer',
    () {
      movement.addAll({
        'revision': 2,
        'approved_by': 'reviewer',
        'approved_at': '2026-10-20T02:00:00Z',
      });
      expect(material().state, 'recordedApprovalEvidence');
      expect(material().issues, isEmpty);
      expect(cost.containsKey('approved_by'), isFalse);
    },
  );
  for (final marker in ['status', 'reversal_id', 'reverses_id']) {
    test(
      'material $marker remains reversal evidence, never a guessed negative cost',
      () {
        movement[marker] = marker == 'status' ? 'void' : 'reversal';
        expect(material().state, 'voidOrReversalObserved');
        expect(
          material().issues,
          contains('materialReversalRequiresReconciliation'),
        );
      },
    );
  }
  test(
    'audit IDs identify observations but do not fabricate a payroll revision',
    () {
      final e = ProductionSourceEvidence.payroll(payroll, events);
      expect(e.issues, ['payrollDurableVersionMissing']);
      expect(payroll.containsKey('revision'), isFalse);
    },
  );
  test(
    'payroll observation identity is stable across order and payment state',
    () {
      final before = ProductionSourceEvidence.payroll(
        payroll,
        events,
      ).observedIdentity;
      final reordered = Map<String, Object?>.fromEntries(
        payroll.entries.toList().reversed,
      );
      reordered['paid'] = '12';
      expect(
        ProductionSourceEvidence.payroll(
          reordered,
          events.reversed,
        ).observedIdentity,
        before,
      );
      reordered['bonus'] = '3';
      expect(
        ProductionSourceEvidence.payroll(reordered, events).observedIdentity,
        isNot(before),
      );
    },
  );
  test(
    'ambiguous or foreign payroll approval audit cannot certify identity',
    () {
      events.add({...events.last});
      expect(
        ProductionSourceEvidence.payroll(payroll, events).issues,
        contains('payrollAuditIdentityUnverified:payroll.approve'),
      );
      events.removeLast();
      events.last['farm_id'] = 'foreign';
      expect(
        ProductionSourceEvidence.payroll(payroll, events).issues,
        contains('payrollAuditIdentityUnverified:payroll.approve'),
      );
    },
  );
  for (final pair in [
    ('cash', null, ProductionExpenseClass.paymentOnly),
    ('settlement', null, ProductionExpenseClass.paymentOnly),
    (
      'tradeExpense',
      'periodExpense',
      ProductionExpenseClass.administrativeOrPeriod,
    ),
    (
      'tradeExpense',
      'includedInProduction',
      ProductionExpenseClass.includedInSource,
    ),
    (
      'tradeExpense',
      'directProduction',
      ProductionExpenseClass.directProduction,
    ),
    (
      'tradeExpense',
      'commonProduction',
      ProductionExpenseClass.commonProduction,
    ),
    ('tradeExpense', 'unapproved', ProductionExpenseClass.unqualified),
  ]) {
    test('expense classification ${pair.$1}/${pair.$2} is diagnostic only', () {
      expect(ProductionExpensePolicy.classify(pair.$1, pair.$2), pair.$3);
    });
  }
  test(
    'projection and five-sheet readback preserve fail-closed source diagnostics',
    () {
      final tables = {
        for (final name in ProductionCostProjection.requiredTables)
          name: <Map<String, Object?>>[],
      };
      tables['production_plans_v1'] = [plan];
      tables['land_parcels'] = [
        {'id': 'parcel', 'farm_id': 'f'},
      ];
      tables['inventory_movements_v2'] = [movement];
      tables['production_material_costs_v2'] = [cost];
      tables['personnel_payrolls_v1'] = [payroll];
      tables['trade_documents_v1'] = [
        for (final treatment in ['directProduction', 'commonProduction'])
          {
            'id': treatment,
            'farm_id': 'f',
            'kind': 'expense',
            'status': 'posted',
            'revision': 1,
            'day': '2026-10-20',
            'currency': 'VND',
            'total': '7',
            'body': jsonEncode({'expenseTreatment': treatment}),
          },
      ];
      final before = jsonEncode(tables);
      final snapshot = IntegrationSnapshot(
        farm: 'f',
        period: '2026-10',
        tables: tables,
        sourceAudit: {'personnel': events},
        sourceCoverageVerified: true,
      );
      final p = ProductionCostProjection(snapshot);
      expect(
        p.entries.every((e) => e.eligibility == CostEligibility.incomplete),
        isTrue,
      );
      expect(
        p.entries.singleWhere((e) => e.sourceType == 'material').approvedBy,
        isNull,
      );
      expect(
        p.entries
            .singleWhere((e) => e.sourceType == 'payrollExtra')
            .sourceRevision,
        isNull,
      );
      expect(p.entries.where((e) => e.sourceType == 'tradeExpense').length, 2);
      expect(
        p.groups().singleWhere((g) => g.currency == 'VND').totalCost,
        isNull,
      );
      final book = Excel.createExcel();
      ProductionCostExport.append(book, p);
      book.delete('Sheet1');
      final bytes = book.encode()!;
      final read = Excel.decodeBytes(bytes);
      for (final tab in ProductionCostExport.tabs) {
        expect(read.tables.containsKey(tab), isTrue);
      }
      final rows = read.tables[ProductionCostExport.tabs.last]!.rows;
      expect(rows.first.length, 17);
      expect(rows[1][15]!.value.toString(), 'immutableIssueWithoutApproval');
      expect(
        rows[1][16]!.value.toString(),
        p.sourceEvidence[p.entries.first.idempotencyKey]!.observedIdentity,
      );
      expect(jsonEncode(tables), before);
      final dir = Platform.environment['AGRICO_PROVENANCE_EVIDENCE_DIR'];
      if (dir != null) {
        File(
          '$dir/provenance-five-sheet-readback.xlsx',
        ).writeAsBytesSync(bytes);
      }
    },
  );

  group('legacy review without ingestion', () {
    ProductionCostEntry v2({
      String amount = '9007199254740993.01',
      String currency = 'VND',
    }) => ProductionCostEntry(
      sourceType: 'material',
      sourceId: 'v2-issue',
      lineId: 'issue',
      category: ProductionCostCategory.material,
      eligibility: CostEligibility.eligible,
      approvalStatus: 'approved',
      sourceRevision: 1,
      planId: 'p',
      parcelId: 'parcel',
      amountExact: amount,
      currency: currency,
      effectiveDate: '2026-10-20',
      approvedBy: 'reviewer',
      approvedAt: '2026-10-20T02:00:00Z',
    );
    Map<String, Object?> legacy() => {
      'id': 'legacy',
      'source': 'material',
      'source_id': 'old-issue',
      'category': 'material',
      'field_id': 'parcel',
      'plan_id': 'p',
      'date': '2026-10-20',
      'amount': '9007199254740993.01',
      'currency': 'VND',
      'revision': 1,
      'status': 'approved',
      'approved_by': 'reviewer',
      'approved_at': '2026-10-20T02:00:00Z',
    };
    List<LegacyCostComparison> compare(
      List<Map<String, Object?>> rows, {
      List<ProductionCostEntry>? entries,
      bool mapped = true,
    }) => LegacyCostReconciliation.compare(
      legacyRows: rows,
      v2Entries: entries ?? [v2()],
      links: [
        if (mapped)
          LegacyCostSourceLink(
            source: 'material',
            sourceId: 'old-issue',
            v2Key: v2().idempotencyKey,
            evidenceReference: 'synthetic-reviewed-link',
          ),
      ],
    );
    test(
      'explicit evidenced identity mapping can match all dimensions exactly',
      () {
        final rows = [legacy()];
        final before = jsonEncode(rows);
        expect(compare(rows).single.exactMatch, isTrue);
        expect(jsonEncode(rows), before);
      },
    );
    test(
      'actual native legacy gaps remain multi-label, never assigned defaults',
      () {
        final row = legacy()
          ..remove('currency')
          ..remove('revision')
          ..remove('approved_by');
        row['amount'] = 9007199254740992.0;
        final result = compare([row]).single;
        expect(
          result.issues,
          containsAll([
            'missingCurrency',
            'missingApprovalOrRevision',
            'legacyAmountNotExactText',
          ]),
        );
        expect(result.exactMatch, isFalse);
      },
    );
    test('same date and amount cannot create a source link', () {
      expect(
        compare([legacy()], mapped: false).single.issues,
        contains('unmatchedSource'),
      );
    });
    test('duplicate legacy sources quarantine both observations', () {
      expect(
        compare([
          legacy(),
          {...legacy(), 'id': 'second'},
        ]).every((r) => r.issues.contains('duplicateLegacySource')),
        isTrue,
      );
    });
    test('amount comparison uses BigInt precision above 15 digits', () {
      expect(
        compare(
          [legacy()],
          entries: [v2(amount: '9007199254740993.02')],
        ).single.issues,
        contains('amountMismatch'),
      );
    });
    test('LAK and VND cannot match and no FX is guessed', () {
      expect(
        compare([legacy()], entries: [v2(currency: 'LAK')]).single.issues,
        contains('dimensionMismatch:currency'),
      );
    });
    test('duplicate V2 keys are not resolved by first writer preference', () {
      expect(
        compare([legacy()], entries: [v2(), v2()]).single.issues,
        contains('duplicateV2Source'),
      );
    });
    test('legacy date parcel plan category are all compared independently', () {
      final row = legacy()
        ..addAll({
          'date': '2026-10-21',
          'field_id': 'other',
          'plan_id': 'other',
          'category': 'fuel',
        });
      expect(
        compare([row]).single.issues,
        containsAll([
          'dimensionMismatch:date',
          'dimensionMismatch:parcel',
          'dimensionMismatch:plan',
          'dimensionMismatch:category',
        ]),
      );
    });
    test(
      'synthetic reconciliation evidence is serializable without changing money',
      () {
        final results = [
          compare([legacy()]).single.toJson(),
          compare([legacy()..remove('currency')]).single.toJson(),
          compare([legacy()], mapped: false).single.toJson(),
        ];
        expect(results.first['v2AmountExact'], '9007199254740993.01');
        final dir = Platform.environment['AGRICO_PROVENANCE_EVIDENCE_DIR'];
        if (dir != null) {
          File('$dir/LEGACY-SYNTHETIC-READBACK.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
          );
        }
      },
    );
    test('persisted revision mismatch cannot be certified as exact', () {
      expect(
        compare([legacy()..['revision'] = 2]).single.issues,
        contains('sourceVersionMismatch'),
      );
    });
    test('invalid V2 exact text remains a review issue without throwing', () {
      expect(
        compare([legacy()], entries: [v2(amount: 'NaN')]).single.issues,
        contains('v2ExactAmountInvalid'),
      );
    });
    test('ambiguous or undocumented source mappings cannot be exact', () {
      final link = LegacyCostSourceLink(
        source: 'material',
        sourceId: 'old-issue',
        v2Key: v2().idempotencyKey,
        evidenceReference: '',
      );
      final missing = LegacyCostReconciliation.compare(
        legacyRows: [legacy()],
        v2Entries: [v2()],
        links: [link],
      );
      expect(missing.single.issues, contains('unmatchedSource'));
      final repeated = LegacyCostReconciliation.compare(
        legacyRows: [legacy()],
        v2Entries: [v2()],
        links: [link, link],
      );
      expect(repeated.single.issues, contains('ambiguousSourceMapping'));
    });
    test(
      'SQLite native legacy extract is unchanged and cannot acquire missing governance',
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        addTearDown(db.close);
        await db.execute(
          'CREATE TABLE production_costs(id TEXT, source TEXT, source_id TEXT, category TEXT, field_id TEXT, date TEXT, amount REAL)',
        );
        await db.insert('production_costs', {
          'id': 'native-legacy',
          'source': 'material',
          'source_id': 'old-issue',
          'category': 'material',
          'field_id': 'parcel',
          'date': '2026-10-20T01:00:00Z',
          'amount': 3.0,
        });
        final before = await db.query('production_costs');
        final schema = await db.rawQuery('PRAGMA table_info(production_costs)');
        final result = compare(before).single;
        expect(
          result.issues,
          containsAll([
            'missingCurrency',
            'missingApprovalOrRevision',
            'legacyAmountNotExactText',
          ]),
        );
        expect(await db.query('production_costs'), before);
        expect(
          await db.rawQuery('PRAGMA table_info(production_costs)'),
          schema,
        );
      },
    );
  });
}
