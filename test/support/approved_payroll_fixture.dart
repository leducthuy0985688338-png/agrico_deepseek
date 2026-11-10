import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/features/integration/data/native_approval_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'approval_b_test_support.dart';

final class ApprovedPayrollFixture {
  ApprovedPayrollFixture(this.db);

  final Database db;
  final _authority = SyntheticApprovalAuthority();

  NativeApprovalRepository _workflow(String id) {
    final actor = approvalUser(id);
    return NativeApprovalRepository(SqliteApprovalPolicyStore(
      db,
      opened: actor,
      currentSubject: () => actor,
      authority: _authority,
    ));
  }

  Future<void> initialize() async {
    _authority.partyUsers['w'] = {};
    await SqliteDocumentApproval.createSchema(db);
    for (final kind in [
      ApprovalKind.fieldWork,
      ApprovalKind.payroll,
      ApprovalKind.settlement,
    ]) {
      await syntheticPolicy(db, _authority, kind, 'VND');
    }
    await NativeApprovalGuard.install(db);
  }

  Future<void> approve(NativeApprovalType type, String id) async {
    final ref = NativeApprovalRef(type, id);
    await _workflow('admin').submit(ref);
    final result = await _workflow('payroll-reviewer').approve(
      ref,
      'Independent payroll fixture review',
    );
    if (!result.allowed) throw StateError(result.reason);
  }

  Future<void> pay(String id, String amount, String day, String note) async {
    await _workflow('admin').proposeCommand(
      id: id,
      operation: 'payrollPay',
      target: const NativeApprovalRef(NativeApprovalType.payroll, 'salary'),
      payload: {'amount': amount, 'day': day, 'reason': note},
    );
    await approve(NativeApprovalType.command, id);
  }
}
