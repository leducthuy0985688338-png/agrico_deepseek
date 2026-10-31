import '../../permissions/authorization.dart';
import '../company_membership.dart';

class AccountAdminFailure implements Exception {
  const AccountAdminFailure(this.code);
  final String code;
}

class CompanyAccountRecord {
  CompanyAccountRecord({
    required this.membership,
    this.displayName = '',
    this.revision = 0,
  });
  final CompanyMembership membership;
  final String displayName;
  final int revision;
  String get uid => membership.profile.userId;
}

class AccountAuditRecord {
  const AccountAuditRecord({
    required this.actorUid,
    required this.targetUid,
    required this.occurredAt,
    required this.reason,
    required this.revision,
  });
  final String actorUid, targetUid, reason;
  final DateTime occurredAt;
  final int revision;
}

abstract interface class CompanyAccountAdminRepository {
  Future<List<CompanyAccountRecord>> list(String farmId);
  Future<List<AccountAuditRecord>> audit(String farmId);

  /// Online transaction must enforce server authority, immutable identities,
  /// expected revision, and create an audit entry with the same commit.
  Future<void> save({
    required String actorUid,
    required CompanyAccountRecord record,
    required int? expectedRevision,
    required String reason,
  });
}

class CompanyAccountAdminService {
  CompanyAccountAdminService({
    required this.repository,
    required this.subject,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final CompanyAccountAdminRepository repository;
  final AuthorizationSubject subject;
  final DateTime Function() clock;

  void _require(String permission) {
    if (!AuthorizationService(clock: clock).can(
      subject: subject,
      permission: permission,
      resource: ResourceContext(farmId: subject.farmId),
    )) {
      throw const AccountAdminFailure('denied');
    }
  }

  Future<List<CompanyAccountRecord>> list() {
    _require(PermissionCodes.accountView);
    return repository.list(subject.farmId);
  }

  Future<List<AccountAuditRecord>> audit() {
    _require(PermissionCodes.accountView);
    return repository.audit(subject.farmId);
  }

  void validate({
    required CompanyAccountRecord record,
    required String reason,
  }) {
    _require(PermissionCodes.accountManage);
    _require(PermissionCodes.roleManage);
    final profile = record.membership.profile;
    if (profile.extraPermissions.any(
      PermissionCodes.guardedApprovalPermissions.contains,
    )) {
      _require(PermissionCodes.approvalAuthorityAssign);
    }
    if (profile.farmId != subject.farmId ||
        profile.userId != profile.membershipId ||
        profile.userId == subject.userId) {
      throw const AccountAdminFailure('identity');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(profile.userId) ||
        reason.trim().isEmpty ||
        reason.trim().length > 500 ||
        record.displayName.trim().isEmpty ||
        record.displayName.length > 100 ||
        profile.roles.isEmpty ||
        profile.roles.length > 4 ||
        profile.roles.map((r) => r.role).toSet().length !=
            profile.roles.length ||
        profile.roles.any((r) => r.scopes.isEmpty) ||
        (profile.extraPermissions.isNotEmpty &&
            profile.extraPermissionScopes.isEmpty)) {
      throw const AccountAdminFailure('invalid');
    }
    for (final ids in [
      profile.projectIds,
      profile.departmentIds,
      profile.teamIds,
      profile.fieldIds,
      profile.taskIds,
      profile.machineIds,
      profile.warehouseIds,
    ]) {
      if (ids.length > 100 ||
          ids.any((v) => v.trim().isEmpty || v.length > 128)) {
        throw const AccountAdminFailure('invalid');
      }
    }
    if (!record.membership.offlineUntil.isUtc ||
        (profile.active &&
            !record.membership.offlineUntil.isAfter(clock().toUtc()))) {
      throw const AccountAdminFailure('deadline');
    }
  }

  Future<void> save({
    required CompanyAccountRecord record,
    required int? expectedRevision,
    required String reason,
  }) async {
    validate(record: record, reason: reason);
    await repository.save(
      actorUid: subject.userId,
      record: record,
      expectedRevision: expectedRevision,
      reason: reason.trim(),
    );
  }
}
