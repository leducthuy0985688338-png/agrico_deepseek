import 'package:excel/excel.dart';

import '../../../core/identity/domain/business_reference_code.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/finance_document.dart';
import 'finance_v2_report.dart';

/// Finance documents currently support whole-farm access only.
class FinanceDocumentService implements FinanceDocumentStore {
  const FinanceDocumentService({
    required FinanceDocumentStore repository,
    required this.subject,
    required this.currentSubject,
  }) : _repository = repository;

  final FinanceDocumentStore _repository;
  final AuthorizationSubject subject;
  final AuthorizationSubject? Function() currentSubject;
  String get organizationId => subject.farmId;

  bool _can(String permission) {
    final live = currentSubject();
    return live != null &&
        live.userId == subject.userId &&
        live.membershipId == subject.membershipId &&
        live.farmId == subject.farmId &&
        live.validUntil != null &&
        const AuthorizationService().can(
          subject: live,
          permission: permission,
          resource: ResourceContext(farmId: organizationId),
        );
  }

  bool get canView => _can(PermissionCodes.financeView);
  bool get canCreate => canView && _can(PermissionCodes.financeCreate);
  bool get canExport => canView && _can(PermissionCodes.reportFinance);

  void _require(bool allowed, String requestedOrganization) {
    if (!allowed || requestedOrganization != organizationId) {
      throw StateError('Finance access denied.');
    }
  }

  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    _require(canView, organizationId);
    final documents = await _repository.listByOrganization(organizationId);
    _require(canView, organizationId);
    if (documents.any(
      (document) => document.organizationId != organizationId,
    )) {
      throw StateError('Finance document is outside the current farm.');
    }
    return documents;
  }

  @override
  Future<FinanceDocument> create({
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
    _require(canCreate, organizationId);
    return _repository.create(
      id: id,
      organizationId: organizationId,
      kind: kind,
      occurredAt: occurredAt,
      amountMinor: amountMinor,
      currency: currency,
      category: category,
      parcelId: parcelId,
      description: description,
    );
  }

  Future<void> exportReport({
    required Future<void> Function(Excel) save,
  }) async {
    _require(canExport, organizationId);
    final workbook = await FinanceV2Report(this).workbook(organizationId);
    // A revoked report grant must not reach the file writer after async reads.
    _require(canExport, organizationId);
    await save(workbook);
  }
}
