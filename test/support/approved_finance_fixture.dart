import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_guard.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/approval/sqlite_document_approval.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/features/integration/data/native_approval_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'approval_b_test_support.dart';

/// Posts persisted report fixtures through the same approval and write path
/// as the app. Only the authority and identities are synthetic.
final class ApprovedFinanceFixture {
  ApprovedFinanceFixture(this.db);

  final Database db;
  final _authority = SyntheticApprovalAuthority();
  final _policies = <(String, ApprovalKind, String)>{};
  final _farms = <String>{};

  Future<void> initialize() async {
    await SqliteFinanceDocumentRepository.createSchema(db);
    await SqliteDocumentApproval.createSchema(db);
    await SqliteCompanyCatalog.createSchema(db);
    await PeriodLock.createSchema(db);
    await NativeApprovalGuard.install(db);
  }

  Future<void> post({
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? parcelId,
    String? description,
  }) async {
    final party = 'report-fixture-$organizationId';
    if (_farms.add(organizationId)) {
      _authority.partyUsers[party] = {};
      await db.insert('company_catalog_entries_v1', {
        'id': party,
        'farm_id': organizationId,
        'kind': 'supplier',
        'code': party,
        'name': party,
        'name_key': party,
        'active': 1,
        'revision': 1,
      });
    }
    final approvalKind = kind == BusinessDocumentKind.receipt
        ? ApprovalKind.cashReceipt
        : ApprovalKind.cashPayment;
    if (_policies.add((organizationId, approvalKind, currency))) {
      await syntheticPolicy(
        db,
        _authority,
        approvalKind,
        currency,
        farm: organizationId,
      );
    }
    final maker = approvalUser('report-maker', farm: organizationId);
    final reviewer = approvalUser('report-reviewer', farm: organizationId);
    NativeApprovalRepository workflow(AuthorizationSubject actor) =>
        NativeApprovalRepository(SqliteApprovalPolicyStore(
          db,
          opened: actor,
          currentSubject: () => actor,
          authority: _authority,
        ));
    final ref = NativeApprovalRef(NativeApprovalType.finance, id);
    await SqliteFinanceDocumentRepository(db).createPendingFinance(
      creator: maker,
      currentSubject: () => maker,
      id: id,
      organizationId: organizationId,
      kind: kind,
      occurredAt: occurredAt,
      amountMinor: amountMinor,
      currency: currency,
      category: category,
      parcelId: parcelId,
      description: description,
      beneficiaryPartyId: party,
    );
    await workflow(maker).submit(ref);
    final decision = await workflow(reviewer).approve(ref, 'Report fixture');
    if (!decision.allowed) {
      throw StateError('Report fixture approval denied: ${decision.reason}');
    }
  }
}
