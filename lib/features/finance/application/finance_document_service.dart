import 'finance_document_filter.dart';
import 'package:excel/excel.dart';

import '../../../core/identity/domain/business_reference_code.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/finance_document.dart';
import '../../farm/domain/entities/land_parcel.dart';
import '../../farm/domain/repositories/land_parcel_repository.dart';
import 'finance_v2_report.dart';

/// Finance documents currently support whole-farm access only.
class FinanceDocumentService implements FinanceDocumentStore {
  const FinanceDocumentService({
    required FinanceDocumentStore repository,
    required this.subject,
    required this.currentSubject,
    this.parcels,
  }) : _repository = repository;

  final FinanceDocumentStore _repository;
  final LandParcelRepository? parcels;
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

  bool get canView =>
      _can(PermissionCodes.financeView) && _can(PermissionCodes.cashView);
  bool get canCreate =>
      canView &&
      _can(PermissionCodes.financeCreate) &&
      _can(PermissionCodes.cashRecord);
  bool get canReport => canView && _can(PermissionCodes.reportFinance);
  bool get canExport => canReport && _can(PermissionCodes.dataExport);
  bool get canViewParcels =>
      canView && parcels != null && _can(PermissionCodes.fieldView);

  Future<List<LandParcel>> availableParcels() async {
    if (!canViewParcels) {
      return const [];
    }
    final result = await parcels!.listByFarm(organizationId);
    _require(canViewParcels, organizationId);
    if (result.any((parcel) => parcel.farmId != organizationId)) {
      throw StateError('Parcel is outside the current farm.');
    }
    return result.where((parcel) => parcel.active).toList();
  }

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

  Future<(FinanceDocument, String?)> details(String id) async {
    _require(canView, organizationId);
    if (id.trim().isEmpty) {
      throw const FormatException('Document ID is required.');
    }
    final documents = await listByOrganization(organizationId);
    final matches = documents.where((document) => document.id == id).toList();
    if (matches.length != 1) {
      throw StateError('Unknown finance document.');
    }
    final document = matches.single;
    String? label;
    if (document.parcelId != null && canViewParcels) {
      final parcels = await availableParcels();
      final linked = parcels
          .where((parcel) => parcel.id == document.parcelId)
          .toList();
      if (linked.isNotEmpty) {
        label = '${linked.first.parcelCode} · ${linked.first.name}';
      }
    }
    _require(canView, organizationId);
    return (document, label);
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
    String? beneficiaryPartyId,
  }) async {
    _require(canCreate, organizationId);
    if (parcelId != null) {
      _require(canViewParcels, organizationId);
      final parcel = await parcels!.getById(
        farmId: organizationId,
        id: parcelId,
      );
      _require(canCreate && canViewParcels, organizationId);
      if (parcel == null ||
          !parcel.active ||
          parcel.farmId != organizationId ||
          parcel.id != parcelId) {
        throw StateError('Invalid finance parcel link.');
      }
    }
    final pending = _repository;
    if (pending is PendingFinanceDocumentStore) {
      return (pending as PendingFinanceDocumentStore).createPendingFinance(
        creator: subject,
        beneficiaryPartyId: beneficiaryPartyId,
        currentSubject: currentSubject,
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
    FinanceDocumentFilter filter = const FinanceDocumentFilter(),
  }) async {
    _require(canExport, organizationId);
    final workbook = await FinanceV2Report(
      this,
    ).workbook(organizationId, filter: filter);
    // A revoked report grant must not reach the file writer after async reads.
    _require(canExport, organizationId);
    await save(workbook);
  }
}
