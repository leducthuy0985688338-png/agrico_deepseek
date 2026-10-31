import 'dart:convert';
import '../../../core/approval/native_approval_guard.dart';
import '../../../core/approval/sqlite_document_approval.dart';
import '../../../core/periods/period_lock.dart';
import '../../../core/production/source_governance.dart';
import '../domain/production_cost_workflow.dart';
import '../domain/production_cost_entry.dart';
import '../domain/integration_snapshot.dart';
import '../domain/production_source_evidence.dart';
import '../../inventory/domain/entities/exact_decimal.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney;

/// Aggregates persisted snapshots only. Missing governance stays visible.
class ProductionCostProjection {
  ProductionCostProjection(this.snapshot) {
    _build();
  }
  final IntegrationSnapshot snapshot;
  final List<ProductionCostEntry> entries = [];
  final List<String> coverageIssues = [];

  /// Diagnostic metadata, not a substitute for source revision/approval.
  final Map<String, ProductionSourceEvidence> sourceEvidence = {};
  static const requiredTables = {
    'production_plans_v1',
    'land_parcels',
    'production_material_costs_v2',
    'inventory_movements_v2',
    'personnel_entries_v1',
    'production_labor_costs_v1',
    'personnel_payrolls_v1',
    'personnel_payroll_adjustments_v1',
    'personnel_payroll_adjustment_costs_v1',
    'machine_runs_v1',
    'machine_costs_v1',
    'trade_documents_v1',
    'finance_documents_v2',
    'integration_fuel_issues_v1',
    'integration_cash_links_v1',
    'integration_machine_links_v1',
  };
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
  Map<String, dynamic> body(Object? v) {
    try {
      return IntegrationSnapshot.json(v);
    } catch (_) {
      return {};
    }
  }

  late final Map<Object?, Map<String, Object?>> plans;
  late final Map<Object?, Map<String, Object?>> parcels;
  final Map<String, Map<String, Object?>> _governanceIndex = {};
  Map<String, Object?>? governance(String type, Object? id) =>
      _governanceIndex[jsonEncode([type, id])];
  Map<String, Object?> governed(
    Map<String, Object?> source,
    String type,
    Object? id,
  ) {
    final g = governance(type, id);
    return g == null
        ? source
        : {
            ...source,
            'revision': g['revision'],
            'creator': g['creator'],
            'created_at': g['created_at'],
            'approver': g['approver'],
            'approved_by': g['approver'],
            'approved_at': g['approved_at'],
          };
  }

  List<String> bindingIssues(String type, Object? id, Object payload) {
    final g = governance(type, id);
    if (g == null) return ['missingPersistedSourceVersion'];
    final events = snapshot
        .rows(SourceGovernance.audit)
        .where(
          (r) =>
              r['farm_id'] == snapshot.farm &&
              r['source_type'] == type &&
              r['source_id'] == id,
        )
        .toList();
    return [
      if (!{'draft', 'approved'}.contains(g['status']) ||
          g['revision'] != (g['status'] == 'approved' ? 2 : 1))
        'invalidPersistedSourceVersion',
      if (g['status'] == 'approved' &&
          (text(g['approver']) == null ||
              DateTime.tryParse(text(g['approved_at']) ?? '') == null))
        'invalidPersistedApproval',
      if (g['payload_digest'] != SourceGovernance.digest(payload))
        'approvedPayloadDigestMismatch',
      if (events
              .where(
                (e) =>
                    e['action'] == 'create' &&
                    e['revision'] == 1 &&
                    e['actor_id'] == g['creator'] &&
                    e['occurred_at'] == g['created_at'] &&
                    e['payload_digest'] == g['payload_digest'],
              )
              .length !=
          1)
        'sourceCreationEventMismatch',
      if (g['status'] == 'approved' &&
          events
                  .where(
                    (e) =>
                        e['action'] == 'approve' &&
                        e['revision'] == g['revision'] &&
                        e['actor_id'] == g['approver'] &&
                        e['occurred_at'] == g['approved_at'] &&
                        e['payload_digest'] == g['payload_digest'],
                  )
                  .length !=
              1)
        'sourceApprovalEventMismatch',
    ];
  }

  final Set<String> _seen = {};
  final Map<String, List<Map<String, Object?>>> _auditCache = {};
  List<Map<String, Object?>> audit(String type, String id) {
    final group = type.startsWith('machine')
        ? 'machine'
        : type.startsWith('labor') || type.startsWith('payroll')
        ? 'personnel'
        : 'trade';
    return _auditCache[jsonEncode([group, id])] ?? const [];
  }

  Map<Object?, List<Map<String, Object?>>> children(String table, String key) {
    final result = <Object?, List<Map<String, Object?>>>{};
    for (final row in snapshot.rows(table)) {
      result.putIfAbsent(row[key], () => []).add(row);
    }
    return result;
  }

  bool hasNativeApproval(String type, String id, String? approver) {
    if (snapshot.rows(NativeApprovalGuard.marker).isEmpty) return true;
    String? identity = switch (type) {
      'material' => 'material:$id',
      'labor' || 'laborUnallocated' => 'fieldWork:$id',
      'payrollExtra' => 'payroll:$id',
      'payrollCorrection' => 'payrollAdjustment:$id',
      'machine' || 'machineUnallocated' => 'machineRun:$id',
      'sale' || 'tradeExpense' => 'trade:$id',
      _ => null,
    };
    if (type == 'productionExpense' || type == 'productionExpenseUnallocated') {
      final policy = snapshot
          .rows('production_expense_policies_v2')
          .where((r) => r['source_id'] == id && r['farm_id'] == snapshot.farm)
          .singleOrNull;
      if (policy != null) identity = 'expenseAllocation:${policy['id']}';
    }
    if (type == 'expenseReversal' || type == 'saleReversal') {
      final commands = snapshot
          .rows(NativeApprovalGuard.commands)
          .where(
            (r) =>
                r['farm_id'] == snapshot.farm &&
                r['target_type'] == 'trade' &&
                r['target_id'] == id &&
                r['operation'] == 'tradeVoid' &&
                r['status'] == 'approved',
          )
          .toList();
      if (commands.length != 1) return false;
      identity = 'command:${commands.single['id']}';
    }
    if (identity == null) return false;
    final requests = snapshot
        .rows(SqliteDocumentApproval.requests)
        .where(
          (r) =>
              r['farm_id'] == snapshot.farm &&
              r['source_id'] == identity &&
              r['state'] == 'approved' &&
              r['decided_by'] == approver,
        )
        .toList();
    return requests.any((request) {
      final events = snapshot
          .rows(SqliteDocumentApproval.audit)
          .where(
            (e) =>
                e['farm_id'] == snapshot.farm &&
                e['source_id'] == identity &&
                e['source_revision'] == request['source_revision'] &&
                e['source_digest'] == request['source_digest'] &&
                e['policy_version'] == request['policy_version'],
          )
          .toList();
      if (events.isEmpty) return false;
      events.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      try {
        return PeriodLock.digest(
              jsonDecode(events.last['after_json'] as String),
            ) ==
            PeriodLock.digest(request);
      } catch (_) {
        return false;
      }
    });
  }

  void add({
    required String type,
    required String id,
    required String line,
    required ProductionCostCategory category,
    required Map<String, Object?> source,
    Object? plan,
    Object? amount,
    Object? currency,
    Object? day,
    Object? revision,
    Object? parcel,
    String? createAction,
    String? approveAction,
    String? correction,
    bool ready = true,
    bool excluded = false,
    bool voided = false,
    List<String> extra = const [],
  }) {
    final issues = [...extra];
    if (source['farm_id'] != null && source['farm_id'] != snapshot.farm) {
      coverageIssues.add('foreignSourceQuarantined');
      return;
    }
    String? date = text(day);
    if (date != null) {
      try {
        if (date.length != 10) date = LaborMoney.day(DateTime.parse(date));
        final parsed = DateTime.parse(date);
        if (parsed.toIso8601String().substring(0, 10) != date) date = null;
      } catch (_) {
        date = null;
      }
    }
    // Unknown dates are quarantined, never assigned to the selected month.
    if (date != null && !snapshot.inPeriod(date)) return;
    if (date == null) issues.add('missingOrInvalidEffectiveDate');
    final planId = text(plan), p = plans[planId];
    final parcelId = text(parcel) ?? text(p?['parcel_id']);
    final moneyCurrency = text(currency);
    String? exact;
    int? scale;
    try {
      if (amount is! String) throw const FormatException();
      final value = ExactDecimal.parse(amount, maxScale: 12);
      if (value.isNegative &&
          type != 'payrollCorrection' &&
          type != 'expenseReversal' &&
          type != 'saleReversal') {
        throw const FormatException();
      }
      exact = value.toString();
      scale = value.scale;
    } catch (_) {
      issues.add('missingOrInvalidExactAmount');
    }
    if (id.isEmpty || line.isEmpty) issues.add('missingSourceIdentity');
    if (!{'VND', 'LAK'}.contains(moneyCurrency)) {
      issues.add('missingOrInvalidCurrency');
    }
    if (p == null) issues.add('missingPlan');
    if (parcelId == null || !parcels.containsKey(parcelId)) {
      issues.add('missingParcel');
    }
    if (p != null &&
        (p['farm_id'] != snapshot.farm ||
            p['parcel_id'] != parcelId ||
            p['currency'] != moneyCurrency)) {
      issues.add('planScopeOrCurrencyMismatch');
    }
    if (parcelId != null && parcels[parcelId]?['farm_id'] != snapshot.farm) {
      issues.add('parcelScopeMismatch');
    }
    if (source['farm_id'] != snapshot.farm) issues.add('sourceScopeMismatch');
    final events = audit(type, id);
    final created =
        events.where((e) => e['action'] == createAction).firstOrNull ??
        const {};
    final approved =
        events.where((e) => e['action'] == approveAction).firstOrNull ??
        const {};
    final createdBy = text(source['creator']) ?? text(created['actor_id']);
    final createdAt =
        text(source['created_at']) ?? text(created['occurred_at']);
    final approvedBy =
        text(source['approver']) ??
        text(source['approved_by']) ??
        text(approved['actor_id']);
    final approvedAt =
        text(source['approved_at']) ?? text(approved['occurred_at']);
    final sourceRevision = revision is int && revision >= 0 ? revision : null;
    if (sourceRevision == null) issues.add('missingSourceRevision');
    if (createdBy == null ||
        createdAt == null ||
        DateTime.tryParse(createdAt) == null) {
      issues.add('missingCreationAudit');
    }
    if (ready &&
        (approvedBy == null ||
            approvedAt == null ||
            DateTime.tryParse(approvedAt) == null)) {
      issues.add('missingApprovalAudit');
    }
    if (ready &&
        !excluded &&
        !voided &&
        !hasNativeApproval(type, id, approvedBy)) {
      issues.add('missingNativeBApproval');
    }
    final key = jsonEncode([type, id, line]);
    if (!_seen.add(key)) {
      // Quarantine both occurrences; never silently keep the first conflicting value.
      for (var i = 0; i < entries.length; i++) {
        final old = entries[i];
        if (old.idempotencyKey == key) {
          entries[i] = _invalidate(old, 'duplicateSourceIdentity');
        }
      }
      issues.add('duplicateSourceIdentity');
    }
    entries.add(
      ProductionCostEntry(
        sourceType: type,
        sourceId: id,
        lineId: line,
        category: category,
        sourceRevision: sourceRevision,
        planId: planId,
        parcelId: parcelId,
        amountExact: exact,
        currency: moneyCurrency,
        scale: scale,
        effectiveDate: date,
        accountingPeriod: date?.substring(0, 7),
        createdBy: createdBy,
        createdAt: createdAt,
        approvedBy: approvedBy,
        approvedAt: approvedAt,
        correctionReference: correction,
        auditReference: events.isEmpty
            ? (createdAt != null && approvedAt != null ? '$type:$id' : null)
            : jsonEncode(events.map((e) => e['id']).toList()),
        approvalStatus: text(source['status']) ?? 'unrecorded',
        issues: issues,
        eligibility: excluded
            ? CostEligibility.excluded
            : voided
            ? CostEligibility.voided
            : !ready
            ? CostEligibility.pending
            : issues.isEmpty
            ? CostEligibility.eligible
            : CostEligibility.incomplete,
      ),
    );
  }

  void quarantineSource(String type, Object? id, String issue) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].sourceType == type && entries[i].sourceId == id) {
        entries[i] = _invalidate(entries[i], issue);
      }
    }
  }

  ProductionCostEntry _invalidate(ProductionCostEntry e, String issue) =>
      ProductionCostEntry(
        sourceType: e.sourceType,
        sourceId: e.sourceId,
        lineId: e.lineId,
        category: e.category,
        eligibility: CostEligibility.incomplete,
        approvalStatus: e.approvalStatus,
        sourceRevision: e.sourceRevision,
        planId: e.planId,
        parcelId: e.parcelId,
        amountExact: e.amountExact,
        currency: e.currency,
        scale: e.scale,
        effectiveDate: e.effectiveDate,
        accountingPeriod: e.accountingPeriod,
        createdBy: e.createdBy,
        createdAt: e.createdAt,
        approvedBy: e.approvedBy,
        approvedAt: e.approvedAt,
        auditReference: e.auditReference,
        correctionReference: e.correctionReference,
        issues: [...e.issues, issue],
      );
  void _build() {
    for (final row
        in snapshot
            .rows(SourceGovernance.versions)
            .where((r) => r['farm_id'] == snapshot.farm)) {
      final key = jsonEncode([row['source_type'], row['source_id']]);
      if (_governanceIndex.containsKey(key)) {
        coverageIssues.add('duplicatePersistedSourceVersion');
      }
      _governanceIndex[key] = row;
    }
    snapshot.to; // Validate period before filtering.
    for (final group in ['machine', 'personnel', 'trade']) {
      for (final event
          in group == 'machine'
              ? snapshot.machineAudit
              : snapshot.sourceAudit[group] ?? const <Map<String, Object?>>[]) {
        if (event['farm_id'] != snapshot.farm) {
          continue;
        }
        _auditCache
            .putIfAbsent(jsonEncode([group, event['entity_id']]), () => [])
            .add(event);
      }
    }
    if (snapshot.closingRevision != null && !snapshot.sourceCoverageVerified) {
      coverageIssues.add('historicalSourceCoverageUnverified');
    }
    plans = snapshot.index('production_plans_v1');
    parcels = snapshot.index('land_parcels');
    for (final name in [
      'production_plans_v1',
      'land_parcels',
      'personnel_entries_v1',
      'machine_runs_v1',
      'trade_documents_v1',
      'personnel_payroll_adjustments_v1',
      'personnel_payrolls_v1',
    ]) {
      final ids = snapshot.rows(name).map((r) => r['id']).toList();
      if (ids.toSet().length != ids.length) {
        coverageIssues.add('duplicateParent:$name');
      }
    }
    for (final name in requiredTables) {
      if (!snapshot.tables.containsKey(name) ||
          snapshot.unavailableTables.contains(name)) {
        coverageIssues.add('unavailable:$name');
      }
    }
    final movements = snapshot.index('inventory_movements_v2');
    final movementIds = snapshot
        .rows('inventory_movements_v2')
        .map((r) => r['id'])
        .toList();
    if (movementIds.toSet().length != movementIds.length) {
      coverageIssues.add('duplicateParent:inventory_movements_v2');
    }
    final componentMovements = snapshot
        .rows('integration_fuel_issues_v1')
        .expand((r) => [r['movement_id'], r['reversal_movement_id']])
        .whereType<String>()
        .toSet();
    for (final row in snapshot.rows('production_material_costs_v2')) {
      final nativeMovement = movements[row['movement_id']];
      final m = nativeMovement == null
          ? null
          : governed(nativeMovement, 'material', row['movement_id']);
      final evidence = ProductionSourceEvidence.material(
        row,
        m,
        plans[row['plan_id']],
      );
      final materialKey = jsonEncode([
        'material',
        text(row['movement_id']) ?? '',
        'issue',
      ]);
      if (m?['farm_id'] == snapshot.farm) {
        sourceEvidence[materialKey] = evidence;
      }
      add(
        type: 'material',
        id: text(row['movement_id']) ?? '',
        line: 'issue',
        category: ProductionCostCategory.material,
        source: {...?m, 'status': m?['status'] ?? 'posted'},
        plan: row['plan_id'],
        parcel: row['parcel_id'],
        amount: row['amount_text'],
        currency: row['currency'],
        day: row['occurred_at'],
        revision: m?['revision'],
        ready:
            governance('material', row['movement_id']) == null ||
            governance('material', row['movement_id'])?['status'] == 'approved',
        excluded: componentMovements.contains(row['movement_id']),
        extra: [
          ...evidence.issues,
          if (nativeMovement != null)
            ...bindingIssues(
              'material',
              row['movement_id'],
              SourceGovernance.material(nativeMovement, row),
            ),
          if (row['farm_id'] != snapshot.farm) 'materialCostScopeMismatch',
          if (componentMovements.contains(row['movement_id']))
            'fuelIncludedInMachineRate',
          if (m == null ||
              m['kind'] != 'issue' ||
              m['amount_text'] != row['amount_text'] ||
              m['currency'] != row['currency'] ||
              m['plan_id'] != row['plan_id'])
            'movementSnapshotMismatch',
        ],
      );
    }
    final costMovements = snapshot
        .rows('production_material_costs_v2')
        .map((r) => r['movement_id'])
        .toSet();
    for (final m
        in snapshot
            .rows('inventory_movements_v2')
            .where(
              (m) => m['kind'] == 'issue' && !costMovements.contains(m['id']),
            )) {
      add(
        type: 'materialUnlinked',
        id: text(m['id']) ?? '',
        line: 'issue',
        category: ProductionCostCategory.material,
        source: {...m, 'status': 'posted'},
        plan: m['plan_id'],
        parcel: m['parcel_id'],
        amount: m['amount_text'],
        currency: m['currency'],
        day: m['occurred_at'],
        revision: m['revision'],
        excluded:
            componentMovements.contains(m['id']) ||
            (m['plan_id'] == null && m['parcel_id'] == null),
        extra: [
          m['plan_id'] == null
              ? 'notAProductionPlanIssue'
              : 'productionCostProjectionMissing',
        ],
      );
    }
    final attendance = snapshot.index('personnel_entries_v1');
    final laborChildren = children('production_labor_costs_v1', 'entry_id');
    for (final row in snapshot.rows('production_labor_costs_v1')) {
      final source = attendance[row['entry_id']] ?? const <String, Object?>{};
      add(
        type: 'labor',
        id: text(row['entry_id']) ?? '',
        line: text(row['plan_id']) ?? '',
        category: ProductionCostCategory.labor,
        source: source,
        plan: row['plan_id'],
        amount: row['amount'],
        currency: row['currency'],
        day: source['business_day'],
        revision: source['revision'],
        createAction: 'entry.create',
        approveAction: 'entry.approve',
        ready: source['status'] == 'approved',
        voided: source['status'] == 'void',
        excluded: source['machine_id'] != null,
        extra: [
          if (source['currency'] != row['currency']) 'sourceCurrencyMismatch',
        ],
      );
    }
    for (final source in attendance.values.where(
      (e) => e['status'] == 'approved' && e['machine_id'] == null,
    )) {
      try {
        final allocated =
            (laborChildren[source['id']] ?? const <Map<String, Object?>>[])
                .fold(
                  ExactDecimal.parse('0'),
                  (s, c) => s + ExactDecimal.parse(c['amount'] as String),
                );
        final remainder =
            ExactDecimal.parse(source['total_amount'] as String) - allocated;
        if (remainder.isNegative) {
          quarantineSource('labor', source['id'], 'allocatedExceedsSource');
        }
        if (remainder.coefficient != BigInt.zero) {
          add(
            type: 'laborUnallocated',
            id: text(source['id']) ?? '',
            line: 'unallocated',
            category: ProductionCostCategory.labor,
            source: source,
            amount: remainder.toString(),
            currency: source['currency'],
            day: source['business_day'],
            revision: source['revision'],
            createAction: 'entry.create',
            approveAction: 'entry.approve',
            extra: ['unallocatedLaborCost'],
          );
        }
      } catch (_) {
        add(
          type: 'laborUnallocated',
          id: text(source['id']) ?? '',
          line: 'invalidTotal',
          category: ProductionCostCategory.labor,
          source: source,
          day: source['business_day'],
          currency: source['currency'],
          extra: ['invalidLaborSourceTotal'],
        );
      }
    }
    for (final nativePayroll in snapshot.rows('personnel_payrolls_v1')) {
      final source = governed(
        nativePayroll,
        'payrollExtra',
        nativePayroll['id'],
      );
      String? extra;
      try {
        extra =
            (ExactDecimal.parse(source['allowance'] as String) +
                    ExactDecimal.parse(source['bonus'] as String))
                .toString();
      } catch (_) {
        /* invalid data is quarantined below */
      }
      if (extra == '0') continue;
      final evidence = ProductionSourceEvidence.payroll(
        source,
        audit('payrollExtra', text(source['id']) ?? ''),
      );
      if (source['farm_id'] == snapshot.farm) {
        sourceEvidence[jsonEncode([
              'payrollExtra',
              text(source['id']) ?? '',
              'allowanceBonus',
            ])] =
            evidence;
      }
      add(
        type: 'payrollExtra',
        id: text(source['id']) ?? '',
        line: 'allowanceBonus',
        category: ProductionCostCategory.labor,
        source: source,
        plan: source['adjustment_plan_id'],
        amount: extra,
        currency: source['currency'],
        day: source['extra_cost_day'],
        revision: source['revision'],
        createAction: 'payroll.create',
        approveAction: 'payroll.approve',
        ready: source['status'] == 'approved',
        voided: source['status'] == 'cancelled',
        extra: [
          ...evidence.issues,
          ...bindingIssues(
            'payrollExtra',
            source['id'],
            SourceGovernance.payroll(
              nativePayroll,
              snapshot
                  .rows('personnel_payroll_lines_v1')
                  .where((r) => r['payroll_id'] == source['id'])
                  .toList(),
            ),
          ),
        ],
      );
    }
    final payrollBusinessKeys = <String, List<Object?>>{};
    for (final source in snapshot.rows('personnel_payrolls_v1')) {
      if (source['status'] == 'cancelled' ||
          source['farm_id'] != snapshot.farm) {
        continue;
      }
      if (source['worker_id'] == null ||
          source['period'] == null ||
          source['currency'] == null) {
        continue;
      }
      payrollBusinessKeys
          .putIfAbsent(
            jsonEncode([
              source['farm_id'],
              source['worker_id'],
              source['period'],
              source['currency'],
            ]),
            () => [],
          )
          .add(source['id']);
    }
    for (final ids in payrollBusinessKeys.values.where(
      (ids) => ids.length > 1,
    )) {
      for (final id in ids) {
        quarantineSource(
          'payrollExtra',
          id,
          'duplicatePayrollBusinessIdentity',
        );
      }
    }
    final corrections = snapshot.index('personnel_payroll_adjustments_v1');
    for (final row in snapshot.rows('personnel_payroll_adjustment_costs_v1')) {
      final nativeCorrection =
          corrections[row['adjustment_id']] ?? const <String, Object?>{};
      final source = governed(
        nativeCorrection,
        'payrollCorrection',
        row['adjustment_id'],
      );
      add(
        type: 'payrollCorrection',
        id: text(row['adjustment_id']) ?? '',
        line: text(row['plan_id']) ?? '',
        category: ProductionCostCategory.labor,
        source: source,
        plan: row['plan_id'],
        amount: row['amount'],
        currency: source['currency'],
        day: source['day'],
        revision: source['approved_revision'],
        correction: text(source['payroll_id']),
        ready: source['status'] == 'approved',
        voided: source['status'] == 'cancelled',
        extra: bindingIssues(
          'payrollCorrection',
          row['adjustment_id'],
          SourceGovernance.correction(
            nativeCorrection,
            snapshot
                .rows('personnel_payroll_adjustment_costs_v1')
                .where((r) => r['adjustment_id'] == row['adjustment_id'])
                .toList(),
          ),
        ),
      );
    }
    final correctionVersions = <String, List<Object?>>{};
    for (final source in corrections.values) {
      if (source['farm_id'] != snapshot.farm ||
          source['status'] != 'approved') {
        continue;
      }
      correctionVersions
          .putIfAbsent(
            jsonEncode([source['payroll_id'], source['approved_revision']]),
            () => [],
          )
          .add(source['id']);
    }
    for (final ids in correctionVersions.values.where(
      (ids) => ids.length > 1,
    )) {
      for (final id in ids) {
        quarantineSource(
          'payrollCorrection',
          id,
          'duplicatePayrollCorrectionVersion',
        );
      }
    }
    final runs = snapshot.index('machine_runs_v1');
    final machineChildren = children('machine_costs_v1', 'source_id');
    for (final pair in [
      (attendance, laborChildren, 'labor', 'business_day'),
      (runs, machineChildren, 'machine', 'day'),
    ]) {
      for (final source in pair.$1.values.where(
        (r) => r['status'] == 'draft' && (pair.$2[r['id']] ?? const []).isEmpty,
      )) {
        add(
          type: pair.$3,
          id: text(source['id']) ?? '',
          line: 'unallocatedDraft',
          category: pair.$3 == 'labor'
              ? ProductionCostCategory.labor
              : ProductionCostCategory.machine,
          source: source,
          day: source[pair.$4],
          currency: source['currency'],
          revision: source['revision'],
          ready: false,
          extra: ['unapprovedSourceWithoutAllocation'],
        );
      }
    }
    for (final row in snapshot.rows('machine_costs_v1')) {
      final source = runs[row['source_id']] ?? const <String, Object?>{};
      add(
        type: 'machine',
        id: text(row['source_id']) ?? '',
        line: text(row['plan_id']) ?? '',
        category: ProductionCostCategory.machine,
        source: source,
        plan: row['plan_id'],
        amount: row['amount'],
        currency: row['currency'],
        day: source['day'],
        revision: source['revision'],
        createAction: 'run.create',
        approveAction: 'run.approve',
        ready: source['status'] == 'approved',
        voided: source['status'] == 'void',
        correction: text(body(source['body'])['note']),
        extra: [
          if (source['currency'] != row['currency']) 'sourceCurrencyMismatch',
        ],
      );
    }
    for (final source in runs.values.where((r) => r['status'] == 'approved')) {
      try {
        final allocated =
            (machineChildren[source['id']] ?? const <Map<String, Object?>>[])
                .fold(
                  ExactDecimal.parse('0'),
                  (s, c) => s + ExactDecimal.parse(c['amount'] as String),
                );
        final remainder =
            ExactDecimal.parse(source['amount'] as String) - allocated;
        if (remainder.isNegative) {
          quarantineSource('machine', source['id'], 'allocatedExceedsSource');
        }
        if (remainder.coefficient != BigInt.zero) {
          add(
            type: 'machineUnallocated',
            id: text(source['id']) ?? '',
            line: 'unallocated',
            category: ProductionCostCategory.machine,
            source: source,
            amount: remainder.toString(),
            currency: source['currency'],
            day: source['day'],
            revision: source['revision'],
            createAction: 'run.create',
            approveAction: 'run.approve',
            extra: ['unallocatedMachineCost'],
          );
        }
      } catch (_) {
        add(
          type: 'machineUnallocated',
          id: text(source['id']) ?? '',
          line: 'invalidTotal',
          category: ProductionCostCategory.machine,
          source: source,
          day: source['day'],
          currency: source['currency'],
          extra: ['invalidMachineSourceTotal'],
        );
      }
    }
    for (final source in snapshot.rows('trade_documents_v1')) {
      final kind = source['kind'], draft = body(source['body']);
      if (kind == 'expense') {
        if ({
              'directProduction',
              'commonProduction',
            }.contains(draft['expenseTreatment']) &&
            snapshot
                .rows('production_expense_policies_v2')
                .any(
                  (r) =>
                      r['source_id'] == source['id'] &&
                      r['farm_id'] == snapshot.farm,
                )) {
          expense(source);
          continue;
        }
        final classification = ProductionExpensePolicy.classify(
          'tradeExpense',
          draft['expenseTreatment'],
        );
        add(
          type: 'tradeExpense',
          id: text(source['id']) ?? '',
          line: 'expense',
          category: ProductionCostCategory.other,
          source: source,
          plan: source['plan_id'],
          amount: source['total'],
          currency: source['currency'],
          day: source['day'],
          revision: source['revision'],
          createAction: 'create',
          approveAction: 'post',
          ready: source['status'] == 'posted',
          voided: source['status'] == 'void',
          excluded:
              draft['expenseTreatment'] == 'includedInProduction' ||
              draft['expenseTreatment'] == 'periodExpense',
          extra: [
            'noApprovedProductionExpenseAllocationPolicy',
            'expenseClass:${classification.name}',
          ],
        );
      }
      if (kind != 'sale') continue;
      final sale = body(source['snapshot']);
      if (sale['lines'] is! List) {
        add(
          type: 'sale',
          id: text(source['id']) ?? '',
          line: 'missingLines',
          category: ProductionCostCategory.revenue,
          source: source,
          day: source['day'],
          currency: source['currency'],
          ready: source['status'] == 'posted',
          voided: source['status'] == 'void',
        );
        continue;
      }
      for (var i = 0; i < (sale['lines'] as List).length; i++) {
        final rawLine = sale['lines'][i];
        if (rawLine is! Map) {
          add(
            type: 'sale',
            id: text(source['id']) ?? '',
            line: 'invalid-$i',
            category: ProductionCostCategory.revenue,
            source: source,
            day: source['day'],
            currency: source['currency'],
            ready: source['status'] == 'posted',
            extra: ['invalidSaleLine'],
          );
          continue;
        }
        final line = rawLine;
        final id = text(source['id']) ?? '';
        final originalInPeriod = snapshot.inPeriod(text(source['day']) ?? '');
        final voidInPeriod =
            source['status'] == 'void' &&
            snapshot.inPeriod(text(source['void_day']) ?? '');
        if (originalInPeriod) {
          add(
            type: 'sale',
            id: id,
            line: '$i',
            category: ProductionCostCategory.revenue,
            source: source,
            plan: line['planId'],
            amount: line['billed'],
            currency: source['currency'],
            day: source['day'],
            revision: source['revision'],
            createAction: 'create',
            approveAction: 'post',
            ready: source['status'] == 'posted' || source['status'] == 'void',
          );
        }
        if (voidInPeriod) {
          String? negative;
          try {
            negative =
                (ExactDecimal.parse('0') -
                        ExactDecimal.parse(line['billed'] as String))
                    .toString();
          } catch (_) {
            /* quarantined */
          }
          add(
            type: 'saleReversal',
            id: id,
            line: '$i',
            category: ProductionCostCategory.revenue,
            source: source,
            plan: line['planId'],
            amount: negative,
            currency: source['currency'],
            day: source['void_day'],
            revision: source['revision'],
            correction: id,
            createAction: 'create',
            approveAction: 'void',
            ready: true,
          );
        }
      }
    }
    // Cash is reconciliation-only, regardless of date or matching amount.
    for (final row
        in snapshot
            .rows('finance_documents_v2')
            .where((r) => {'CHI', 'THU'}.contains(r['kind']))) {
      add(
        type: 'cash',
        id: text(row['id']) ?? '',
        line: 'paymentOnly',
        category: ProductionCostCategory.other,
        source: {...row, 'farm_id': row['organization_id']},
        parcel: row['parcel_id'],
        currency: row['currency'],
        day: row['occurred_at'],
        excluded: true,
        extra: ['cashIsNotProductionAccrual'],
      );
    }
  }

  void expense(Map<String, Object?> source) {
    final id = text(source['id']) ?? '';
    final matches = snapshot
        .rows('production_expense_policies_v2')
        .where((r) => r['source_id'] == id && r['farm_id'] == snapshot.farm)
        .toList();
    if (matches.length != 1) {
      coverageIssues.add('ambiguousExpensePolicy');
      return;
    }
    final policy = matches.single;
    final g = governance('expenseAllocation', policy['id']);
    final issues = <String>[
      ...bindingIssues(
        'tradeExpense',
        id,
        SourceGovernance.expenseSource(source),
      ),
      if (governance('tradeExpense', id)?['status'] != 'approved')
        'nativeExpenseNotApproved',
      ...bindingIssues(
        'expenseAllocation',
        policy['id'],
        SourceGovernance.policyPayload(policy),
      ),
      if (g == null) 'missingExpenseApprovalIdentity',
      if (policy['source_digest'] !=
          SourceGovernance.digest(SourceGovernance.expenseSource(source)))
        'expenseSourceDigestMismatch',
    ];
    final rows = snapshot
        .rows('production_expense_costs_v2')
        .where((r) => r['policy_id'] == policy['id'])
        .toList();
    try {
      final weights = (jsonDecode(policy['weights_json'] as String) as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();
      ExpenseAllocationProposal(
        expenseId: id,
        driver: CostAllocationDriver.values.byName(policy['driver'] as String),
        baseUnits: policy['base_units'] as int,
        moneyScale: policy['money_scale'] as int,
        weights: weights
            .map(
              (r) => CostAllocationWeight(
                r['planId'] as String,
                r['units'] as int,
                r['evidence'] as String,
              ),
            )
            .toList(),
      ).validate();
      final expected = LaborMoney.allocate(
        source['total'] as String,
        weights.map((r) => r['units'] as int).toList(),
        policy['base_units'] as int,
        policy['money_scale'] as int,
      );
      if (g?['status'] == 'approved' &&
          (rows.length != weights.length ||
              rows.any((r) {
                final i = weights.indexWhere(
                  (w) => w['planId'] == r['plan_id'],
                );
                return i < 0 ||
                    r['farm_id'] != snapshot.farm ||
                    r['currency'] != source['currency'] ||
                    r['parcel_id'] != plans[r['plan_id']]?['parcel_id'] ||
                    r['amount'] != expected[i];
              }) ||
              rows.map((r) => r['plan_id']).toSet().length != rows.length)) {
        issues.add('approvedExpenseAllocationMismatch');
      }
      final metadata = <String, Object?>{
        ...source,
        ...?g,
        'farm_id': snapshot.farm,
        'status': g?['status'] ?? 'draft',
      };
      final ready =
          g?['status'] == 'approved' &&
          {'posted', 'void'}.contains(source['status']);
      if (rows.isEmpty) {
        add(
          type: 'productionExpense',
          id: id,
          line: 'unallocated',
          category: ProductionCostCategory.other,
          source: metadata,
          amount: source['total'],
          currency: source['currency'],
          day: source['day'],
          revision: g?['revision'],
          ready: false,
          voided:
              source['status'] == 'void' &&
              g?['status'] == 'draft' &&
              issues.isEmpty,
          extra: [...issues, 'expenseAllocationNotApproved'],
        );
      }
      for (final row in rows) {
        if (snapshot.inPeriod(source['day'] as String)) {
          add(
            type: 'productionExpense',
            id: id,
            line: text(row['plan_id']) ?? '',
            category: ProductionCostCategory.other,
            source: metadata,
            plan: row['plan_id'],
            parcel: row['parcel_id'],
            amount: row['amount'],
            currency: row['currency'],
            day: source['day'],
            revision: g?['revision'],
            ready: ready,
            extra: issues,
          );
        }
        if (source['status'] == 'void' &&
            snapshot.inPeriod(text(source['void_day']) ?? '')) {
          final voidEvents = (snapshot.sourceAudit['trade'] ?? [])
              .where(
                (e) =>
                    e['farm_id'] == snapshot.farm &&
                    e['entity_id'] == id &&
                    e['action'] == 'void',
              )
              .toList();
          final event = voidEvents.singleOrNull;
          add(
            type: 'expenseReversal',
            id: id,
            line: text(row['plan_id']) ?? '',
            category: ProductionCostCategory.other,
            source: governed(
              {
                ...metadata,
                'approver': event?['actor_id'],
                'approved_at': event?['occurred_at'],
              },
              'expenseReversal',
              id,
            ),
            plan: row['plan_id'],
            parcel: row['parcel_id'],
            amount:
                (ExactDecimal.parse('0') -
                        ExactDecimal.parse(row['amount'] as String))
                    .toString(),
            currency: row['currency'],
            day: source['void_day'],
            revision: source['revision'],
            correction: id,
            ready:
                ready &&
                governance('expenseReversal', id)?['status'] == 'approved',
            extra: [
              ...issues,
              ...bindingIssues(
                'expenseReversal',
                id,
                SourceGovernance.expenseReversal(source),
              ),
              if (event == null) 'expenseReversalAuditMissing',
            ],
          );
        }
      }
      if (ready &&
          !(source['status'] == 'void' &&
              text(source['void_day'])?.substring(0, 7) ==
                  text(source['day'])?.substring(0, 7))) {
        final remaining =
            ExactDecimal.parse(source['total'] as String) -
            rows.fold(
              ExactDecimal.parse('0'),
              (s, r) => s + ExactDecimal.parse(r['amount'] as String),
            );
        if (remaining.coefficient != BigInt.zero) {
          add(
            type: 'productionExpenseUnallocated',
            id: id,
            line: 'unallocated',
            category: ProductionCostCategory.other,
            source: metadata,
            amount: remaining.toString(),
            currency: source['currency'],
            day: source['day'],
            revision: g?['revision'],
            extra: [...issues, 'unallocatedProductionExpense'],
          );
        }
      }
    } catch (_) {
      add(
        type: 'productionExpense',
        id: id,
        line: 'invalidPolicy',
        category: ProductionCostCategory.other,
        source: source,
        amount: source['total'],
        currency: source['currency'],
        day: source['day'],
        extra: ['invalidProductionExpensePolicy'],
      );
    }
  }

  List<ProductionCostGroup> groups({bool byPlan = false}) {
    final keys = <(String, String?)>{};
    for (final p in plans.values) {
      if (p['farm_id'] == snapshot.farm && text(p['parcel_id']) != null) {
        keys.add((p['parcel_id'] as String, byPlan ? p['id'] as String : null));
      }
    }
    return [
      for (final key in keys)
        for (final currency in ['VND', 'LAK'])
          ProductionCostGroup(
            parcelId: key.$1,
            planId: key.$2,
            currency: currency,
            coverageIssues: List.unmodifiable(coverageIssues),
            entries: List.unmodifiable(
              entries.where(
                (e) =>
                    (!parcels.containsKey(e.parcelId) ||
                        e.parcelId == key.$1 ||
                        plans[e.planId]?['parcel_id'] == key.$1) &&
                    (!byPlan || e.planId == null || e.planId == key.$2) &&
                    (e.currency == null ||
                        !{'VND', 'LAK'}.contains(e.currency) ||
                        e.currency == currency),
              ),
            ),
          ),
    ];
  }
}
