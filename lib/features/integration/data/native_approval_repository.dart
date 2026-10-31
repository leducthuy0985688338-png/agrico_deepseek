import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/approval/approval_policy.dart';
import '../../../core/approval/native_approval_store.dart';
import '../../../core/approval/native_approval_guard.dart';
import '../../../core/approval/sqlite_approval_policy_store.dart';
import '../../../core/approval/sqlite_document_approval.dart';
import '../../../core/approval/transaction_database.dart';
import '../../../core/permissions/authorization.dart';
import '../../../core/permissions/live_authorization.dart';
import '../../../core/periods/period_lock.dart';
import '../../../core/production/source_governance.dart';
import '../../machines/domain/machines.dart';
import '../../machines/data/sqlite_machine_repository.dart';
import '../../personnel/data/sqlite_personnel_repository.dart';
import '../../personnel/domain/personnel.dart' show LaborMoney, ExactDecimal;
import '../../trade/data/sqlite_trade_repository.dart';
import '../../finance/data/local/sqlite_finance_document_repository.dart';
import '../../../core/identity/domain/business_reference_code.dart';
import 'production_cost_workflow_repository.dart';
import 'integration_repository.dart';
import '../../trade/domain/trade.dart' as tradeDomain;

class NativeApprovalAccessDenied extends StateError {
  NativeApprovalAccessDenied() : super('Native approval access denied.');
}

class _Source {
  _Source(this.context, this.row, this.table, this.revision);
  final ApprovalContext context;
  final Map<String, Object?> row;
  final String table;
  final int revision;
}

/// Native readers and dispatch; native repositories still own all money math.
class NativeApprovalRepository implements NativeApprovalStore {
  const NativeApprovalRepository(this.policies);
  final SqliteApprovalPolicyStore policies;
  Database get db => policies.db;
  SqliteDocumentApproval get engine => SqliteDocumentApproval(policies);
  String get farm => policies.opened.farmId;
  @override
  String get actorId => policies.opened.userId;
  @override
  bool canView([NativeApprovalView? item]) {
    try {
      if (item == null) {
        requireEntry(PermissionCodes.financeView);
      } else {
        require(PermissionCodes.financeView, resource: item.source.resource);
      }
      if (item != null) {
        require(viewPermission(item.ref.type), resource: item.source.resource);
        for (final p in item.source.requiredPermissions.where(
          (p) => p.endsWith('.view'),
        ))
          require(p, resource: item.source.resource);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static const tables = {
    NativeApprovalType.finance: NativeApprovalGuard.pending,
    NativeApprovalType.material: 'inventory_movements_v2',
    NativeApprovalType.machineRun: 'machine_runs_v1',
    NativeApprovalType.machineExpense: 'machine_expenses_v1',
    NativeApprovalType.fieldWork: 'personnel_entries_v1',
    NativeApprovalType.payroll: 'personnel_payrolls_v1',
    NativeApprovalType.payrollAdjustment: 'personnel_payroll_adjustments_v1',
    NativeApprovalType.trade: 'trade_documents_v1',
    NativeApprovalType.expenseAllocation:
        ProductionCostWorkflowRepository.policies,
    NativeApprovalType.command: NativeApprovalGuard.commands,
  };
  AuthorizationSubject require(String p, {ResourceContext? resource}) {
    final s = policies.currentSubject();
    if (s == null ||
        s.userId != policies.opened.userId ||
        s.membershipId != policies.opened.membershipId ||
        s.farmId != farm ||
        !const AuthorizationService().can(
          subject: s,
          permission: p,
          resource: resource ?? ResourceContext(farmId: farm),
        ))
      throw NativeApprovalAccessDenied();
    return s;
  }

  void requireEntry(String permission) {
    if (!LiveAuthorization(
      policies.currentSubject,
    ).canEnter(policies.opened, permission)) {
      throw NativeApprovalAccessDenied();
    }
  }

  static String viewPermission(NativeApprovalType t) => switch (t) {
    NativeApprovalType.machineRun ||
    NativeApprovalType.machineExpense => PermissionCodes.machineView,
    NativeApprovalType.fieldWork ||
    NativeApprovalType.payroll ||
    NativeApprovalType.payrollAdjustment => PermissionCodes.payrollView,
    NativeApprovalType.material => PermissionCodes.inventoryView,
    NativeApprovalType.trade => PermissionCodes.purchaseView,
    _ => PermissionCodes.financeView,
  };
  Future<Map<String, Object?>> one(
    DatabaseExecutor tx,
    String table,
    String id, {
    String key = 'id',
  }) async {
    final r = await tx.query(
      table,
      where: 'farm_id=? AND $key=?',
      whereArgs: [farm, id],
    );
    if (r.length != 1)
      throw StateError('Native source unavailable or ambiguous.');
    return r.single;
  }

  Future<(String, String)> author(
    DatabaseExecutor tx,
    String table,
    String id,
    String action,
  ) async {
    final rows = await tx.query(
      table,
      where: 'farm_id=? AND entity_id=? AND action=?',
      whereArgs: [farm, id, action],
      orderBy: 'id',
      limit: 1,
    );
    if (rows.isEmpty || (rows.single['actor_id'] as String).trim().isEmpty)
      throw StateError('Canonical source creator is missing.');
    return (
      rows.single['actor_id'] as String,
      rows.single['occurred_at'] as String,
    );
  }

  Future<_Source> read(DatabaseExecutor tx, NativeApprovalRef ref) async {
    final table = tables[ref.type]!;
    final r = await one(tx, table, ref.id);
    Map<String, Object?> body = r['body'] is String
        ? Map<String, Object?>.from(jsonDecode(r['body'] as String) as Map)
        : {};
    var currency =
        r['currency'] as String? ?? body['currency'] as String? ?? '';
    var total =
        r['amount_text'] as String? ??
        r['total'] as String? ??
        r['net'] as String? ??
        r['delta'] as String? ??
        body['amount'] as String? ??
        '';
    var day =
        r['day'] as String? ??
        r['business_day'] as String? ??
        r['extra_cost_day'] as String? ??
        (r['occurred_at'] as String?)?.substring(0, 10) ??
        body['day'] as String? ??
        '';
    var state = r['status'] as String? ?? 'draft';
    var revision = r['revision'] as int? ?? 0;
    final nativeRevision = revision;
    String creator = '', created = '';
    Object payload = {};
    var kind = ApprovalKind.directExpense;
    String? warehouse = r['warehouse_id'] as String?,
        machine = r['machine_id'] as String?,
        department;
    String? plan = r['plan_id'] as String?,
        party = r['worker_id'] as String? ?? r['party_id'] as String?;
    final beneficiaries = <String>{};
    var beneficiaryVerified = false;
    String? governanceType;
    var componentProofs = true;
    switch (ref.type) {
      case NativeApprovalType.finance:
        creator = r['creator'] as String;
        created = r['created_at'] as String;
        kind = body['kind'] == 'THU'
            ? ApprovalKind.cashReceipt
            : ApprovalKind.cashPayment;
        currency = body['currency'] as String;
        total = body['amountText'] as String;
        day = body['day'] as String;
        payload = body;
        plan = body['planId'] as String?;
        party = body['beneficiaryPartyId'] as String?;
      case NativeApprovalType.material:
        kind = ApprovalKind.materialIssue;
        beneficiaryVerified = true;
        governanceType = 'material';
        payload = await SourceGovernance.nativePayload(tx, 'material', ref.id);
      case NativeApprovalType.payroll:
        kind = ApprovalKind.payroll;
        governanceType = 'payrollExtra';
        payload = await SourceGovernance.nativePayload(
          tx,
          'payrollExtra',
          ref.id,
        );
        total = LaborMoney.sum(
          [
            'regular',
            'overtime',
            'piece',
            'allowance',
            'bonus',
          ].map((k) => r[k] as String),
        );
        for (final line in await tx.query(
          'personnel_payroll_lines_v1',
          where: 'payroll_id=?',
          whereArgs: [ref.id],
        )) {
          final proof = await tx.query(
            SqliteDocumentApproval.requests,
            where: "farm_id=? AND source_id=? AND state='approved'",
            whereArgs: [farm, 'fieldWork:${line['entry_id']}'],
          );
          if (proof.isEmpty) componentProofs = false;
        }
      case NativeApprovalType.payrollAdjustment:
        kind = ApprovalKind.payrollAdjustment;
        governanceType = 'payrollCorrection';
        payload = await SourceGovernance.nativePayload(
          tx,
          'payrollCorrection',
          ref.id,
        );
        final parent = await one(
          tx,
          'personnel_payrolls_v1',
          r['payroll_id'] as String,
        );
        party = parent['worker_id'] as String;
      case NativeApprovalType.expenseAllocation:
        governanceType = 'expenseAllocation';
        payload = SourceGovernance.policyPayload(r);
        final expense = await one(
          tx,
          'trade_documents_v1',
          r['source_id'] as String,
        );
        total = expense['total'] as String;
        kind = r['driver'] == 'direct'
            ? ApprovalKind.directExpense
            : ApprovalKind.overheadAllocation;
        party = expense['party_id'] as String?;
        final proof = await tx.query(
          SqliteDocumentApproval.requests,
          where:
              "farm_id=? AND source_id=? AND source_digest=? AND state='approved'",
          whereArgs: [
            farm,
            'trade:${expense['id']}',
            PeriodLock.digest(SourceGovernance.expenseSource(expense)),
          ],
        );
        if (proof.isEmpty) componentProofs = false;
      case NativeApprovalType.machineRun:
        kind = ApprovalKind.machineRun;
        final run = MachineRun.fromJson(Map<String, dynamic>.from(body));
        final rates = await tx.query(
          'machine_rates_v1',
          where: r['rate_id'] != null
              ? 'farm_id=? AND id=?'
              : 'farm_id=? AND machine_id=? AND effective_on<=?',
          whereArgs: r['rate_id'] != null
              ? [farm, r['rate_id']]
              : [farm, machine, day],
          orderBy: 'effective_on DESC,revision DESC',
          limit: 1,
        );
        if (rates.isEmpty) throw StateError('Native machine rate missing.');
        final rate = MachineRate.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(rates.single['body'] as String) as Map,
          ),
        );
        currency = rate.currency;
        total = r['amount'] != null
            ? r['amount'] as String
            : rate.cost(run.minutes);
        payload = {'run': body, 'rate': rates.single};
        party = run.operatorId;
        final a = await author(tx, 'machine_audit_v1', ref.id, 'run.create');
        creator = a.$1;
        created = a.$2;
      case NativeApprovalType.machineExpense:
        final a = await author(
          tx,
          'machine_audit_v1',
          ref.id,
          'expense.create',
        );
        creator = a.$1;
        created = a.$2;
        kind = ApprovalKind.directExpense;
        party = body['partyId'] as String?;
        payload = body;
      case NativeApprovalType.fieldWork:
        kind = ApprovalKind.fieldWork;
        final a = await author(
          tx,
          'personnel_audit_v1',
          ref.id,
          'entry.create',
        );
        creator = a.$1;
        created = a.$2;
        final type = r['work_type_id'] as String,
            basis = r['requested_basis'] as String?,
            unit = r['requested_piece_unit'] as String;
        var rates = await tx.query(
          'personnel_pay_rates_v1',
          where:
              'farm_id=? AND worker_id=? AND effective_on<=? AND work_type_id IN (?,?) AND ${basis != null
                  ? 'basis=?'
                  : r['piece_quantity'] != null
                  ? "basis='piece'"
                  : "basis IN ('hourly','daily')"}${unit.isEmpty ? '' : ' AND piece_unit=?'}',
          whereArgs: [
            farm,
            party,
            day,
            '',
            type,
            ?basis,
            if (unit.isNotEmpty) unit,
          ],
          orderBy:
              "CASE WHEN work_type_id='' THEN 1 ELSE 0 END,effective_on DESC,revision DESC,id",
        );
        if (r['rate_id'] != null)
          rates = await tx.query(
            'personnel_pay_rates_v1',
            where: 'farm_id=? AND id=?',
            whereArgs: [farm, r['rate_id']],
          );
        if (rates.isEmpty) throw StateError('Native labor rate missing.');
        final rate = SqlitePersonnelRepository.rateFromRow(rates.first);
        currency = rate.currency;
        total = r['total_amount'] != null
            ? r['total_amount'] as String
            : SqlitePersonnelRepository.earnings(r, rate)['total']!;
        payload = {
          'entry': {
            for (final e in r.entries)
              if (![
                'status',
                'revision',
                'approved_by',
                'rate_id',
                'currency',
                'regular_amount',
                'overtime_amount',
                'piece_amount',
                'total_amount',
              ].contains(e.key))
                e.key: e.value,
          },
          'rate': rates.first,
          'allocations':
              (await tx.query(
                    'production_labor_costs_v1',
                    where: 'entry_id=? AND farm_id=?',
                    whereArgs: [ref.id, farm],
                    orderBy: 'plan_id',
                  ))
                  .map(
                    (a) => {
                      for (final e in a.entries)
                        if (!['amount', 'currency'].contains(e.key))
                          e.key: e.value,
                    },
                  )
                  .toList(),
        };
        final profiles = await tx.query(
          'personnel_profiles_v1',
          where: 'farm_id=? AND worker_id=?',
          whereArgs: [farm, party],
        );
        department = profiles.singleOrNull?['department_id'] as String?;
      case NativeApprovalType.trade:
        final a = await author(tx, 'trade_audit_v1', ref.id, 'create');
        creator = a.$1;
        created = a.$2;
        kind = r['kind'] == 'purchase'
            ? ApprovalKind.purchase
            : r['kind'] == 'expense' &&
                  body['expenseTreatment'] == 'directProduction'
            ? ApprovalKind.directExpense
            : ApprovalKind.tradePosting;
        if (r['kind'] == 'expense' &&
            body['expenseTreatment'] == 'commonProduction')
          kind = ApprovalKind.overheadAllocation;
        payload = SourceGovernance.expenseSource(r);
      case NativeApprovalType.command:
        return readCommand(tx, ref, r);
    }
    if (governanceType != null) {
      final g = await SourceGovernance.get(tx, farm, governanceType, ref.id);
      if (g == null) throw StateError('Native source governance missing.');
      creator = g['creator'] as String;
      created = g['created_at'] as String;
      state = g['status'] as String;
      revision = (g['revision'] as int) - (state == 'approved' ? 1 : 0);
      if (g['payload_digest'] != PeriodLock.digest(payload))
        throw StateError('Native source digest mismatch.');
    } else if (state == 'approved' || state == 'posted') {
      revision--;
    }
    if (ref.type == NativeApprovalType.finance) {
      revision = nativeRevision;
    }
    if (party != null) {
      final p = await tx.query(
        'company_catalog_entries_v1',
        where: 'farm_id=? AND id=?',
        whereArgs: [farm, party],
      );
      if (p.isNotEmpty) {
        final a = policies.authority;
        if (a is ApprovalRelationsAuthority) {
          final users = await (a as ApprovalRelationsAuthority)
              .beneficiaryUsers(farm, party);
          if (users != null) {
            beneficiaries.addAll(users);
            beneficiaryVerified = true;
          }
        }
      }
    }
    if (party != null &&
        {
          NativeApprovalType.payroll,
          NativeApprovalType.payrollAdjustment,
        }.contains(ref.type)) {
      final profiles = await tx.query(
        'personnel_profiles_v1',
        where: 'farm_id=? AND worker_id=?',
        whereArgs: [farm, party],
      );
      department = profiles.singleOrNull?['department_id'] as String?;
    }
    String? field;
    if (plan != null) {
      final p = await one(tx, 'production_plans_v1', plan);
      field = p['parcel_id'] as String?;
    }
    final resource = ResourceContext(
      farmId: farm,
      machineId: machine,
      warehouseId: warehouse,
      departmentId: department,
      fieldId: field,
      ownerUserId: creator,
    );
    require(viewPermission(ref.type), resource: resource);
    require(PermissionCodes.financeView, resource: resource);
    // Context selection is local. The executor verifies the authority live
    // before and after posting; context construction does not duplicate that RPC.
    final active = await SqliteApprovalPolicyStore.active(
      tx,
      farm,
      kind,
      currency,
    );
    final related = await relatedExposure(tx, ref, r, total, currency, day);
    final permissions = <String>{
      PermissionCodes.financeView,
      viewPermission(ref.type),
      if (ref.type == NativeApprovalType.machineExpense)
        PermissionCodes.machineVerify,
      if (ref.type == NativeApprovalType.finance) PermissionCodes.cashView,
      if (ref.type == NativeApprovalType.finance) PermissionCodes.cashRecord,
      if (ref.type == NativeApprovalType.material)
        PermissionCodes.inventoryPrice,
      if (ref.type == NativeApprovalType.trade) ...{
        PermissionCodes.financePost,
        PermissionCodes.financeApprove,
        if (r['kind'] != 'expense') ...{
          PermissionCodes.inventoryPrice,
          r['kind'] == 'sale'
              ? PermissionCodes.inventoryIssue
              : PermissionCodes.inventoryReceive,
        },
      },
    };
    final open =
        day.length == 10 &&
        (await PeriodLock.state(tx, farm, day.substring(0, 7)))?['status'] !=
            'closed';
    return _Source(
      ApprovalContext(
        farm: farm,
        kind: kind,
        sourceId: ref.key,
        revision: revision,
        digest: PeriodLock.digest(payload),
        creator: creator,
        createdAt: created,
        currency: currency,
        total: total,
        policyVersion: active?.version ?? 0,
        state: ['draft', 'pending'].contains(state)
            ? 'pending'
            : state == 'posted'
            ? 'approved'
            : state,
        periodOpen: open,
        metadataComplete:
            creator.isNotEmpty &&
            total.isNotEmpty &&
            componentProofs &&
            (party == null
                ? !{
                    NativeApprovalType.finance,
                    NativeApprovalType.machineExpense,
                  }.contains(ref.type)
                : beneficiaryVerified),
        beneficiaries: beneficiaries,
        beneficiariesVerified: beneficiaryVerified,
        linkEvidenceVerified: true,
        relatedKey:
            '${ref.type.name}:${party ?? machine ?? plan ?? creator}:$day',
        resource: resource,
        requiredPermissions: permissions,
        relatedTotal: related.$1,
        relatedDocuments: related.$2,
      ),
      r,
      table,
      nativeRevision,
    );
  }

  Future<(String, int)> relatedExposure(
    DatabaseExecutor tx,
    NativeApprovalRef ref,
    Map<String, Object?> source,
    String total,
    String currency,
    String day,
  ) async {
    String abs(String s) => s.startsWith('-') ? s.substring(1) : s;
    var sum = ExactDecimal.parse(abs(total));
    var count = 1;
    final fields = switch (ref.type) {
      NativeApprovalType.finance => ['body'],
      NativeApprovalType.machineRun ||
      NativeApprovalType.machineExpense => ['machine_id', 'day'],
      NativeApprovalType.material => ['plan_id'],
      NativeApprovalType.trade => ['party_id', 'day', 'kind'],
      NativeApprovalType.fieldWork => [
        'worker_id',
        'business_day',
        'requested_basis',
        'requested_piece_unit',
        'work_type_id',
      ],
      _ => <String>[],
    };
    if (fields.isEmpty) return (sum.toString(), count);
    final candidates = await tx.query(
      tables[ref.type]!,
      where: 'farm_id=? AND id<>?',
      whereArgs: [farm, ref.id],
    );
    for (final other in candidates) {
      if (['void', 'rejected', 'cancelled'].contains(other['status'])) continue;
      String? amount;
      if (ref.type == NativeApprovalType.finance) {
        final a = jsonDecode(source['body'] as String) as Map,
            b = jsonDecode(other['body'] as String) as Map;
        if ([
              'day',
              'kind',
              'currency',
              'category',
              'parcelId',
            ].any((key) => a[key] != b[key]) ||
            source['creator'] != other['creator'])
          continue;
        amount = b['amountText'] as String;
      } else {
        if (fields.any((field) => source[field] != other[field])) continue;
        if (ref.type == NativeApprovalType.material &&
            (other['occurred_at'] as String).substring(0, 10) != day)
          continue;
        if (other['currency'] != null && other['currency'] != currency)
          continue;
        switch (ref.type) {
          case NativeApprovalType.machineRun:
            amount = other['amount'] as String?;
            if (amount == null) {
              final rates = await tx.query(
                'machine_rates_v1',
                where: 'farm_id=? AND machine_id=? AND effective_on<=?',
                whereArgs: [farm, other['machine_id'], day],
                orderBy: 'effective_on DESC,revision DESC',
                limit: 1,
              );
              if (rates.isEmpty)
                throw StateError('Related machine exposure unresolved.');
              final rate = MachineRate.fromJson(
                Map<String, dynamic>.from(
                  jsonDecode(rates.single['body'] as String) as Map,
                ),
              );
              if (rate.currency != currency) continue;
              amount = rate.cost(
                MachineRun.fromJson(
                  Map<String, dynamic>.from(
                    jsonDecode(other['body'] as String) as Map,
                  ),
                ).minutes,
              );
            }
          case NativeApprovalType.machineExpense:
            final b = jsonDecode(other['body'] as String) as Map;
            if (b['currency'] != currency) continue;
            amount = b['amount'] as String;
          case NativeApprovalType.material:
            amount = other['amount_text'] as String?;
          case NativeApprovalType.trade:
            amount = other['total'] as String?;
          case NativeApprovalType.fieldWork:
            amount = other['total_amount'] as String?;
            if (amount == null) {
              // Same worker/day/basis/unit/work-type group; use the same native
              // selector as the current source, never price approved history.
              final rateRows = await tx.query(
                'personnel_pay_rates_v1',
                where:
                    'farm_id=? AND worker_id=? AND effective_on<=? AND work_type_id IN (?,?)',
                whereArgs: [
                  farm,
                  source['worker_id'],
                  day,
                  '',
                  source['work_type_id'],
                ],
                orderBy:
                    "CASE WHEN work_type_id='' THEN 1 ELSE 0 END,effective_on DESC,revision DESC,id",
              );
              final matching = rateRows
                  .where(
                    (r) =>
                        source['requested_basis'] == null ||
                        r['basis'] == source['requested_basis'],
                  )
                  .where(
                    (r) =>
                        source['requested_piece_unit'] == '' ||
                        r['piece_unit'] == source['requested_piece_unit'],
                  )
                  .toList();
              if (matching.isEmpty)
                throw StateError('Related labor exposure unresolved.');
              final rate = SqlitePersonnelRepository.rateFromRow(
                matching.first,
              );
              if (rate.currency != currency) continue;
              amount = SqlitePersonnelRepository.earnings(other, rate)['total'];
            }
          default:
            break;
        }
      }
      if (amount == null)
        throw StateError('Related native exposure unresolved.');
      sum = sum + ExactDecimal.parse(abs(amount));
      count++;
    }
    return (sum.toString(), count);
  }

  @override
  Future<List<NativeApprovalView>> list(Set<NativeApprovalType> types) async {
    final result = <NativeApprovalView>[];
    for (final type in types) {
      requireEntry(viewPermission(type));
      requireEntry(PermissionCodes.financeView);
      final rows = await db.query(
        tables[type]!,
        where: 'farm_id=?',
        whereArgs: [farm],
      );
      for (final row in rows) {
        if (type == NativeApprovalType.command &&
            !types.contains(
              NativeApprovalType.values.byName(row['target_type'] as String),
            ))
          continue;
        final ref = NativeApprovalRef(type, row['id'] as String);
        final _Source s;
        try {
          s = await read(db, ref);
        } on NativeApprovalAccessDenied {
          continue;
        }
        final current = require(
          viewPermission(type),
          resource: s.context.resource,
        );
        result.add(
          NativeApprovalView(
            ref,
            s.context,
            ApprovalRules.evaluate(
              s.context,
              await policies.effective(
                db,
                farm,
                s.context.kind,
                s.context.currency,
              ),
              current,
            ),
            await engine.row(db, s.context),
          ),
        );
      }
    }
    requireEntry(PermissionCodes.financeView);
    return result.where(canView).toList();
  }

  @override
  Future<void> submit(NativeApprovalRef ref) =>
      engine.submit((tx) async => (await read(tx, ref)).context);
  @override
  Future<ApprovalDecision> approve(NativeApprovalRef ref, String reason) async {
    return engine.approve(
      read: (tx) async => (await read(tx, ref)).context,
      apply: (tx) async {
        final s = await read(tx, ref),
            actor = require(
              ApprovalRules.nativeApprovePermission(s.context.kind),
              resource: s.context.resource,
            ).userId;
        if (ref.type == NativeApprovalType.command) {
          await applyCommand(tx, ref, s, actor);
          return;
        }
        final writes = <String>{
          '${s.table}:${ref.id}',
          'production_source_versions_v2:${ref.id}',
          'machine_costs_v1:${ref.id}',
          'production_labor_costs_v1:${ref.id}',
          'production_expense_costs_v2:${ref.id}',
        };
        await NativeApprovalGuard.authorized(
          tx,
          farm: farm,
          actor: actor,
          writes: writes,
          financeIds: ref.type == NativeApprovalType.finance
              ? {ref.id}
              : const {},
          apply: () async {
            final bound = TransactionDatabase(tx);
            switch (ref.type) {
              case NativeApprovalType.finance:
                final p = jsonDecode(s.row['body'] as String) as Map;
                await SqliteFinanceDocumentRepository(bound).create(
                  id: ref.id,
                  organizationId: farm,
                  kind: p['kind'] == 'THU'
                      ? BusinessDocumentKind.receipt
                      : BusinessDocumentKind.payment,
                  occurredAt: DateTime.parse(p['occurredAt'] as String),
                  amountMinor: int.parse(p['amountMinor'] as String),
                  currency: p['currency'] as String,
                  category: p['category'] as String,
                  parcelId: p['parcelId'] as String?,
                  description: p['description'] as String?,
                );
                await tx.update(
                  s.table,
                  {'status': 'approved'},
                  where: 'id=? AND farm_id=?',
                  whereArgs: [ref.id, farm],
                );
              case NativeApprovalType.material:
                await ProductionCostWorkflowRepository(bound).approveMaterial(
                  farm,
                  ref.id,
                  s.context.revision,
                  actor,
                  () => require(
                    PermissionCodes.inventoryPrice,
                    resource: s.context.resource,
                  ),
                );
              case NativeApprovalType.expenseAllocation:
                await ProductionCostWorkflowRepository(bound).approveExpense(
                  farm,
                  ref.id,
                  s.context.revision,
                  actor,
                  () => require(
                    PermissionCodes.financeApprove,
                    resource: s.context.resource,
                  ),
                );
              case NativeApprovalType.machineRun:
                await SqliteMachineRepository(
                  bound,
                ).approveRun(farm, ref.id, s.revision, actor);
              case NativeApprovalType.machineExpense:
                await SqliteMachineRepository(
                  bound,
                ).approveExpense(farm, ref.id, s.revision, actor);
              case NativeApprovalType.fieldWork:
                await SqlitePersonnelRepository(
                  bound,
                ).approveEntry(farm, ref.id, s.revision, actor);
              case NativeApprovalType.payroll:
                await SqlitePersonnelRepository(
                  bound,
                ).approvePayroll(farm, ref.id, actor);
              case NativeApprovalType.payrollAdjustment:
                await SqlitePersonnelRepository(
                  bound,
                ).approvePayrollAdjustment(farm, ref.id, actor);
              case NativeApprovalType.trade:
                await SqliteTradeRepository(
                  bound,
                ).post(farm, ref.id, s.revision, actor);
              case NativeApprovalType.command:
                throw StateError('Command was already dispatched.');
            }
          },
        );
      },
      verifyApplied: (tx, before, actor) async {
        final after = await read(tx, ref);
        return after.context.state == 'approved' &&
            after.context.digest == before.digest;
      },
      reason: reason,
    );
  }

  @override
  Future<void> reject(NativeApprovalRef ref, String reason) => engine.reject(
    (tx) async => (await read(tx, ref)).context,
    reason,
    apply:
        {
          NativeApprovalType.finance,
          NativeApprovalType.command,
        }.contains(ref.type)
        ? (tx) async {
            final s = await read(tx, ref);
            await NativeApprovalGuard.authorized(
              tx,
              farm: farm,
              actor: require(
                ApprovalRules.nativeApprovePermission(s.context.kind),
                resource: s.context.resource,
              ).userId,
              writes: {'${s.table}:${ref.id}'},
              apply: () async {
                await tx.update(
                  s.table,
                  {'status': 'rejected'},
                  where: 'farm_id=? AND id=?',
                  whereArgs: [farm, ref.id],
                );
              },
            );
          }
        : null,
  );
  @override
  Future<List<Map<String, Object?>>> history(NativeApprovalRef ref) async {
    final s = await read(db, ref);
    require(ApprovalRules.auditView, resource: s.context.resource);
    final rows = await db.query(
      SqliteDocumentApproval.audit,
      where: 'farm_id=? AND source_id=?',
      whereArgs: [farm, ref.key],
      orderBy: 'id',
    );
    require(ApprovalRules.auditView, resource: s.context.resource);
    return rows;
  }

  Future<_Source> readCommand(
    DatabaseExecutor tx,
    NativeApprovalRef ref,
    Map<String, Object?> r,
  ) async {
    final body = Map<String, Object?>.from(
      jsonDecode(r['body'] as String) as Map,
    );
    final target = NativeApprovalRef(
      NativeApprovalType.values.byName(r['target_type'] as String),
      r['target_id'] as String,
    );
    final source = await read(tx, target);
    if (r['status'] == 'pending' &&
        r['source_digest'] != await commandSource(tx, source))
      throw StateError(
        'Command source changed; explicit new command revision required.',
      );
    final op = r['operation'] as String;
    final kind = op == 'fuelIssue'
        ? ApprovalKind.materialIssue
        : [
            'tradeSettle',
            'payrollPay',
            'salaryLink',
            'machinePayable',
          ].contains(op)
        ? ApprovalKind.settlement
        : ApprovalKind.correction;
    final currency = source.context.currency;
    final p = await SqliteApprovalPolicyStore.active(tx, farm, kind, currency);
    final day = body['day'] as String;
    final permissions = <String>{
      PermissionCodes.financeView,
      viewPermission(target.type),
      PermissionCodes.cashRecord,
      if (kind == ApprovalKind.correction) PermissionCodes.financeCorrect,
      if (op.startsWith('payroll') || op.startsWith('salary'))
        PermissionCodes.payrollApprove,
      if (op == 'machineVoid') PermissionCodes.machineVerify,
      if (op == 'fieldVoid') PermissionCodes.attendanceVerify,
      if (op == 'tradeVoid' && source.row['kind'] != 'expense') ...{
        PermissionCodes.inventoryAdjust,
        PermissionCodes.inventoryPrice,
      },
      if (op == 'machinePayable') PermissionCodes.financePost,
      if (op == 'fuelIssue' || op == 'fuelReverse') ...{
        PermissionCodes.inventoryView,
        PermissionCodes.inventoryPrice,
        PermissionCodes.machineVerify,
        if (op == 'fuelIssue') PermissionCodes.inventoryIssue,
        if (op == 'fuelReverse') PermissionCodes.inventoryAdjust,
      },
    };
    final supplied = body['amount'] as String?;
    final nativeTotal = ExactDecimal.parse(
      source.context.relatedTotal ?? source.context.total,
    );
    final amount = op == 'fuelIssue'
        ? ExactDecimal.parse(
                (jsonDecode(source.row['body'] as String) as Map)['litres']
                    as String,
              ) *
              ExactDecimal.parse(body['price'] as String)
        : supplied == null
        ? nativeTotal
        : ExactDecimal.parse(supplied);
    final exposure = (amount.compareTo(nativeTotal) > 0 ? amount : nativeTotal)
        .toString();
    final c = ApprovalContext(
      farm: farm,
      kind: kind,
      sourceId: ref.key,
      revision: r['revision'] as int,
      digest: PeriodLock.digest({
        'operation': op,
        'target': target.key,
        'payload': body,
        'sourceDigest': r['source_digest'],
      }),
      creator: r['creator'] as String,
      createdAt: r['created_at'] as String,
      currency: currency,
      total: exposure,
      policyVersion: p?.version ?? 0,
      state: r['status'] as String,
      periodOpen:
          (await PeriodLock.state(tx, farm, day.substring(0, 7)))?['status'] !=
          'closed',
      metadataComplete: source.context.metadataComplete,
      beneficiaries: source.context.beneficiaries,
      beneficiariesVerified: source.context.beneficiariesVerified,
      linkEvidenceVerified: op != 'fuelIssue',
      relatedKey: target.key,
      relatedTotal: exposure,
      resource: source.context.resource,
      requiredPermissions: permissions,
    );
    for (final permission in [
      viewPermission(target.type),
      PermissionCodes.financeView,
    ])
      require(permission, resource: c.resource);
    return _Source(c, r, NativeApprovalGuard.commands, r['revision'] as int);
  }

  Future<String> commandSource(DatabaseExecutor tx, _Source source) async =>
      PeriodLock.digest({
        'payload': source.context.digest,
        'row': source.row,
        'nativeRevision': source.revision,
        if (source.table == 'personnel_payrolls_v1')
          'adjustments': await tx.query(
            'personnel_payroll_adjustments_v1',
            where: "farm_id=? AND payroll_id=? AND status='approved'",
            whereArgs: [farm, source.row['id']],
            orderBy: 'approved_revision',
          ),
      });
  @override
  Future<void> proposeCommand({
    required String id,
    required String operation,
    required NativeApprovalRef target,
    required Map<String, Object?> payload,
  }) => db.transaction((tx) async {
    const allowed = {
      'tradeSettle': {NativeApprovalType.trade},
      'tradeReverse': {NativeApprovalType.trade},
      'tradeVoid': {NativeApprovalType.trade},
      'machineVoid': {
        NativeApprovalType.machineRun,
        NativeApprovalType.machineExpense,
      },
      'fieldVoid': {NativeApprovalType.fieldWork},
      'payrollPay': {NativeApprovalType.payroll},
      'payrollRefund': {NativeApprovalType.payroll},
      'payrollRefundReverse': {NativeApprovalType.payroll},
      'salaryLink': {NativeApprovalType.payroll},
      'salaryReverse': {NativeApprovalType.payroll},
      'machinePayable': {NativeApprovalType.machineExpense},
      'fuelIssue': {NativeApprovalType.machineExpense},
      'fuelReverse': {NativeApprovalType.machineExpense},
      'financeReverse': {NativeApprovalType.finance},
    };
    if (id.trim().isEmpty ||
        !(allowed[operation]?.contains(target.type) ?? false))
      throw const FormatException('Unsupported native approval command.');
    final source = await read(tx, target);
    final actor = require(
      PermissionCodes.financeCreate,
      resource: source.context.resource,
    );
    if (source.context.state != 'approved')
      throw StateError('Approved native source required.');
    if (!source.context.metadataComplete)
      throw StateError('Native source evidence is incomplete.');
    final proofs = await tx.query(
      SqliteDocumentApproval.requests,
      where:
          "farm_id=? AND source_id=? AND source_revision=? AND source_digest=? AND state='approved'",
      whereArgs: [
        farm,
        source.context.sourceId,
        source.context.revision,
        source.context.digest,
      ],
    );
    if (proofs.isEmpty)
      throw StateError(
        'Native source must have its own B approval before settlement/correction.',
      );
    if (operation == 'financeReverse' &&
        payload['amount'] != null &&
        ExactDecimal.parse(
              payload['amount'] as String,
            ).compareTo(ExactDecimal.parse(source.context.total)) !=
            0)
      throw const FormatException(
        'Finance reversal must preserve the complete original amount.',
      );
    if (operation == 'fuelIssue' || operation == 'fuelReverse') {
      if (source.row['kind'] != 'fuel')
        throw StateError('Fuel source required.');
      if (operation == 'fuelIssue') {
        final price = ExactDecimal.parse(
          payload['price'] as String,
          maxScale: 6,
        );
        if (price.coefficient <= BigInt.zero ||
            payload['day'] != source.row['day']) {
          throw StateError(
            'Positive exact fuel price and original issue day required.',
          );
        }
      }
    }
    final day = payload['day'];
    if (day is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
        (await PeriodLock.state(tx, farm, day.substring(0, 7)))?['status'] ==
            'closed')
      throw StateError('Valid open command period required.');
    if (operation.endsWith('Void') ||
        operation.contains('Reverse') ||
        operation.contains('Refund')) {
      require(
        PermissionCodes.financeCorrect,
        resource: source.context.resource,
      );
      if ((payload['reason'] as String? ?? '').trim().isEmpty)
        throw StateError('Correction reason required.');
    }
    if (payload['amount'] != null) {
      final a = ExactDecimal.parse(payload['amount'] as String, maxScale: 6);
      if (a.isNegative || a.coefficient == BigInt.zero)
        throw const FormatException('Positive exact payment required.');
    }
    final old = await tx.query(
      NativeApprovalGuard.commands,
      where: 'farm_id=? AND id=?',
      whereArgs: [farm, id],
    );
    final encoded = PeriodLock.encode(payload),
        digest = await commandSource(tx, source);
    if (old.isNotEmpty) {
      if (old.single['creator'] != actor.userId ||
          old.single['operation'] != operation ||
          old.single['target_id'] != target.id ||
          old.single['target_type'] != target.type.name ||
          old.single['body'] != encoded ||
          old.single['source_digest'] != digest)
        throw StateError('Command idempotency identity conflict.');
      return;
    }
    await tx.insert(NativeApprovalGuard.commands, {
      'id': id,
      'farm_id': farm,
      'revision': 1,
      'operation': operation,
      'target_type': target.type.name,
      'target_id': target.id,
      'body': encoded,
      'source_digest': digest,
      'creator': actor.userId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
    });
    require(PermissionCodes.financeCreate, resource: source.context.resource);
  });

  Future<void> applyCommand(
    Transaction tx,
    NativeApprovalRef ref,
    _Source s,
    String actor,
  ) async {
    final command = s.row, op = command['operation'] as String;
    final target = NativeApprovalRef(
      NativeApprovalType.values.byName(command['target_type'] as String),
      command['target_id'] as String,
    );
    final source = await read(tx, target);
    final p = Map<String, Object?>.from(
      jsonDecode(command['body'] as String) as Map,
    );
    String text(String key) {
      final v = p[key];
      if (v is! String || v.trim().isEmpty)
        throw FormatException('Command $key required.');
      return v;
    }

    final id = ref.id, day = text('day');
    final writes = <String>{
      '${s.table}:$id',
      '${source.table}:${target.id}',
      'production_source_versions_v2:${target.id}',
      'personnel_payments_v1:$id',
      'integration_cash_links_v1:$id',
      'personnel_payroll_refunds_v1:$id',
      'trade_settlements_v1:$id',
      'trade_reversals_v1:$id',
      'integration_salary_reversals_v1:$id',
      '${NativeApprovalGuard.reversals}:${target.id}',
      'integration_fuel_issues_v1:${target.id}',
      if (op == 'machinePayable') ...{
        'trade_documents_v1:machine-payable:${target.id}',
        'production_source_versions_v2:machine-payable:${target.id}',
        'integration_machine_links_v1:${target.id}',
      },
    };
    final finances = <String>{};
    switch (op) {
      case 'financeReverse':
        finances.add('finance-reversal:$id');
      case 'tradeSettle':
        finances.add('trade-payment:$id');
      case 'tradeReverse':
        finances.add('trade-reversal:$id');
      case 'payrollPay':
        finances.add('integrated:salary:$id');
      case 'payrollRefund':
      case 'payrollRefundReverse':
        finances.add('integrated:salary-refund:$id');
      case 'salaryReverse':
        finances.add('integrated:salary-reversal:$id');
      case 'salaryLink':
        final payment = await one(
          tx,
          'personnel_payments_v1',
          text('paymentId'),
        );
        if (payment['payroll_id'] != target.id)
          throw StateError('Payment belongs to another payroll.');
        writes.add('integration_cash_links_v1:${payment['id']}');
        finances.add('integrated:salary:${payment['id']}');
    }
    await NativeApprovalGuard.authorized(
      tx,
      farm: farm,
      actor: actor,
      writes: writes,
      financeIds: finances,
      apply: () async {
        final bound = TransactionDatabase(tx),
            trade = SqliteTradeRepository(
              TransactionDatabase(tx),
              requestedBy: command['creator'] as String,
            );
        final personnel = SqlitePersonnelRepository(bound);
        switch (op) {
          case 'financeReverse':
            final original = Map<String, Object?>.from(
              jsonDecode(source.row['body'] as String) as Map,
            );
            if ((await tx.query(
              NativeApprovalGuard.reversals,
              where: 'source_id=?',
              whereArgs: [target.id],
            )).isNotEmpty)
              throw StateError('Finance source already reversed.');
            await SqliteFinanceDocumentRepository(bound).create(
              id: 'finance-reversal:$id',
              organizationId: farm,
              kind: original['kind'] == 'THU'
                  ? BusinessDocumentKind.payment
                  : BusinessDocumentKind.receipt,
              occurredAt: DateTime.parse(day),
              amountMinor: int.parse(original['amountMinor'] as String),
              currency: original['currency'] as String,
              category: 'APPROVED_REVERSAL',
              parcelId: original['parcelId'] as String?,
              description: '${target.id}: ${text('reason')}',
            );
            await tx.insert(NativeApprovalGuard.reversals, {
              'source_id': target.id,
              'farm_id': farm,
              'command_id': id,
              'finance_id': 'finance-reversal:$id',
            });
          case 'fuelIssue':
            await IntegrationRepository(bound).fuelIssue(
              farm,
              target.id,
              text('itemId'),
              text('price'),
              false,
              actor,
            );
          case 'fuelReverse':
            await IntegrationRepository(
              bound,
            ).reverseFuel(farm, target.id, day, text('reason'), actor);
          case 'machinePayable':
            final detail = jsonDecode(source.row['body'] as String) as Map;
            final supplier = detail['partyId'];
            if (supplier is! String || supplier.isEmpty)
              throw StateError('Verified native machine supplier required.');
            await IntegrationRepository(bound).machinePayable(
              farm,
              target.id,
              supplier,
              text('reference'),
              tradeDomain.MoneyRounding.values.byName(text('rounding')),
              actor,
              requestedBy: command['creator'] as String,
            );
          case 'tradeSettle':
            await trade.settle(
              farm,
              id,
              target.id,
              text('amount'),
              source.context.currency,
              day,
              text('reference'),
              actor,
            );
          case 'tradeReverse':
            final payment = await one(
              tx,
              'trade_settlements_v1',
              text('paymentId'),
            );
            if (payment['document_id'] != target.id)
              throw StateError('Payment source mismatch.');
            await trade.reversePayment(
              farm,
              text('paymentId'),
              id,
              day,
              text('reason'),
              actor,
            );
          case 'tradeVoid':
            await trade.voidDocument(
              farm,
              target.id,
              source.revision,
              day,
              text('reason'),
              actor,
            );
          case 'machineVoid':
            final machines = SqliteMachineRepository(bound);
            if (target.type == NativeApprovalType.machineRun)
              await machines.voidRun(
                farm,
                target.id,
                source.revision,
                text('reason'),
                actor,
              );
            else
              await machines.voidExpense(
                farm,
                target.id,
                source.revision,
                text('reason'),
                actor,
              );
          case 'fieldVoid':
            await personnel.voidEntry(
              farm,
              target.id,
              source.revision,
              text('reason'),
              actor,
            );
          case 'payrollPay':
            await personnel.recordPayment(
              farm,
              id,
              target.id,
              text('amount'),
              source.context.currency,
              day,
              text('reason'),
              actor,
            );
          case 'payrollRefund':
          case 'payrollRefundReverse':
            await personnel.refundPayroll(
              farm,
              id,
              target.id,
              text('amount'),
              source.context.currency,
              day,
              text('reason'),
              actor,
              reversesId: op == 'payrollRefundReverse'
                  ? text('refundId')
                  : null,
            );
          case 'salaryLink':
            await IntegrationRepository(bound).linkSalary(
              farm,
              text('paymentId'),
              actor,
              existingFinanceId: p['financeId'] as String?,
            );
          case 'salaryReverse':
            final payment = await one(
              tx,
              'personnel_payments_v1',
              text('paymentId'),
            );
            if (payment['payroll_id'] != target.id)
              throw StateError('Payment source mismatch.');
            await IntegrationRepository(bound).reverseSalary(
              farm,
              text('paymentId'),
              id,
              day,
              text('reason'),
              actor,
            );
          default:
            throw StateError('Unsupported command operation.');
        }
        await tx.update(
          s.table,
          {'status': 'approved'},
          where: 'farm_id=? AND id=? AND revision=?',
          whereArgs: [farm, id, s.revision],
        );
      },
    );
  }
}
