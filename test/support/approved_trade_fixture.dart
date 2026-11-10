import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:agrico_deepseek/features/integration/data/native_approval_repository.dart';
import 'package:agrico_deepseek/features/trade/data/sqlite_trade_repository.dart';
import 'package:agrico_deepseek/features/trade/domain/trade.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'approval_b_test_support.dart';

final class ApprovedTradeFixture {
  ApprovedTradeFixture(this.db, {this.farm = 'f'});

  final Database db;
  final String farm;
  final _authority = SyntheticApprovalAuthority();
  final _policies = <(ApprovalKind, String)>{};

  NativeApprovalRepository _workflow(String id) {
    final actor = approvalUser(id, farm: farm);
    return NativeApprovalRepository(SqliteApprovalPolicyStore(
      db, opened: actor, currentSubject: () => actor, authority: _authority,
    ));
  }

  Future<void> _policy(ApprovalKind kind, String currency) async {
    if (_policies.add((kind, currency))) {
      await syntheticPolicy(db, _authority, kind, currency, farm: farm);
    }
  }

  Future<void> initialize() async {
    await SqliteDocumentApproval.createSchema(db);
    await PeriodLock.createSchema(db);
    await NativeApprovalGuard.install(db);
  }

  Future<void> _approve(NativeApprovalRef ref) async {
    final requests = await db.query(
      SqliteDocumentApproval.requests,
      where: 'farm_id=? AND source_id=?',
      whereArgs: [farm, ref.key],
    );
    if (requests.isEmpty) await _workflow('admin').submit(ref);
    final decision = await _workflow('trade-reviewer').approve(
      ref, 'Independent trade fixture review',
    );
    if (!decision.allowed) throw StateError(decision.reason);
  }

  Future<void> post(TradeDraft draft) async {
    final party = draft.partyId;
    if (party != null) _authority.partyUsers[party] = {};
    await _policy(
      switch (draft.kind) {
        TradeKind.purchase => ApprovalKind.purchase,
        TradeKind.expense when draft.expenseTreatment == 'directProduction' =>
          ApprovalKind.directExpense,
        TradeKind.expense when draft.expenseTreatment == 'commonProduction' =>
          ApprovalKind.overheadAllocation,
        _ => ApprovalKind.tradePosting,
      },
      draft.currency,
    );
    await SqliteTradeRepository(db).create(farm, draft, 'admin');
    await _approve(NativeApprovalRef(NativeApprovalType.trade, draft.id));
  }

  Future<void> command({
    required String id,
    required String source,
    required String currency,
    required String operation,
    required Map<String, Object?> payload,
  }) async {
    await _policy(
      operation == 'tradeSettle' ? ApprovalKind.settlement : ApprovalKind.correction,
      currency,
    );
    await _workflow('admin').proposeCommand(
      id: id,
      operation: operation,
      target: NativeApprovalRef(NativeApprovalType.trade, source),
      payload: payload,
    );
    await _approve(NativeApprovalRef(NativeApprovalType.command, id));
  }
}
