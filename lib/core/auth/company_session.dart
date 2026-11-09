import '../permissions/authorization.dart';
import 'company_membership.dart';

class AccessFailure implements Exception {
  const AccessFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

class AccessUnavailable implements Exception {
  const AccessUnavailable();
}

abstract interface class CompanyIdentityGateway {
  String get projectId;
  Future<String?> currentUserId();
  Future<String> signIn(String email, String password);
  Future<CompanyMembership> fetchMembership(String userId);
  Future<void> signOut();
  Future<void> resetPassword(String email);
}

abstract interface class CompanySessionStore {
  Future<CachedCompanySession?> read();
  Future<void> write(CachedCompanySession session);
  Future<void> clear();
}

class CachedCompanySession {
  const CachedCompanySession({
    required this.projectId,
    required this.membership,
    required this.verifiedAt,
    required this.lastSeenAt,
  });
  final String projectId;
  final CompanyMembership membership;
  final DateTime verifiedAt, lastSeenAt;
  bool valid(String project, String userId, DateTime now) =>
      projectId == project &&
      membership.profile.userId == userId &&
      membership.profile.active &&
      !now.isBefore(lastSeenAt) &&
      !now.isBefore(verifiedAt) &&
      now.isBefore(membership.offlineUntil);
  CachedCompanySession seen(DateTime now) => CachedCompanySession(
    projectId: projectId,
    membership: membership,
    verifiedAt: verifiedAt,
    lastSeenAt: now,
  );
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'projectId': projectId,
    'membership': membership.toJson(),
    'verifiedAt': verifiedAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
  };
  factory CachedCompanySession.fromJson(Map<String, dynamic> json) {
    final verified = DateTime.tryParse(
      json['verifiedAt'] is String ? json['verifiedAt'] as String : '',
    );
    final seen = DateTime.tryParse(
      json['lastSeenAt'] is String ? json['lastSeenAt'] as String : '',
    );
    if (json['schemaVersion'] != 1 ||
        json['projectId'] is! String ||
        (json['projectId'] as String).isEmpty ||
        json['membership'] is! Map ||
        verified == null ||
        seen == null ||
        !verified.isUtc ||
        !seen.isUtc ||
        seen.isBefore(verified)) {
      throw const FormatException('Invalid cached session.');
    }
    return CachedCompanySession(
      projectId: json['projectId'] as String,
      membership: CompanyMembership.fromJson(
        Map<String, dynamic>.from(json['membership'] as Map),
      ),
      verifiedAt: verified,
      lastSeenAt: seen,
    );
  }
}

class CompanySessionService {
  CompanySessionService({
    required this.gateway,
    required this.store,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final CompanyIdentityGateway gateway;
  final CompanySessionStore store;
  final DateTime Function() clock;
  Future<void>? _tail;
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail == null
        ? Future<T>.sync(action)
        : _tail!.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  CachedCompanySession? current;
  bool offline = false;
  // This rollout binds to the existing database farm without migrating records.
  static const supportedFarmId = 'local-farm';

  AuthorizationSubject get subject {
    final value = current;
    final now = clock().toUtc();
    if (value == null ||
        !value.valid(gateway.projectId, value.membership.profile.userId, now)) {
      throw const AccessFailure('sessionExpired');
    }
    final base = value.membership.profile.subject(now: now);
    return AuthorizationSubject(
      userId: base.userId,
      membershipId: base.membershipId,
      farmId: base.farmId,
      active: base.active,
      permissionCodes: base.permissionCodes,
      dataScopes: base.dataScopes,
      permissionScopes: base.permissionScopes,
      teamIds: base.teamIds,
      assignedFieldIds: base.assignedFieldIds,
      assignedTaskIds: base.assignedTaskIds,
      projectIds: base.projectIds,
      departmentIds: base.departmentIds,
      assignedMachineIds: base.assignedMachineIds,
      assignedWarehouseIds: base.assignedWarehouseIds,
      validUntil: value.membership.offlineUntil,
    );
  }

  Future<void> login(String email, String password) => _exclusive(() async {
    await store.clear();
    current = null;
    offline = false;
    try {
      if (email.trim().isEmpty || password.isEmpty) {
        throw const AccessFailure('credentialsRequired');
      }
      final uid = await gateway.signIn(email.trim(), password);
      await _online(uid);
    } catch (_) {
      await store.clear();
      current = null;
      await gateway.signOut();
      rethrow;
    }
  });
  Future<bool> restore() => _exclusive(() async {
    current = null;
    offline = false;
    final uid = await gateway.currentUserId();
    if (uid == null) {
      await store.clear();
      return false;
    }
    final cached = await store.read();
    try {
      await _online(uid);
      return true;
    } on AccessUnavailable {
      final now = clock().toUtc();
      if (cached != null &&
          cached.membership.profile.farmId == supportedFarmId &&
          cached.valid(gateway.projectId, uid, now)) {
        final seen = cached.seen(now);
        await store.write(seen);
        current = seen;
        offline = true;
        return true;
      }
      await store.clear();
      throw const AccessFailure('onlineRequired');
    } catch (_) {
      await store.clear();
      current = null;
      rethrow;
    }
  });
  Future<void> _online(String uid) async {
    final membership = await gateway.fetchMembership(uid);
    final now = clock().toUtc();
    if (membership.profile.userId != uid ||
        membership.profile.membershipId != uid ||
        membership.profile.farmId != supportedFarmId ||
        !membership.profile.active ||
        !now.isBefore(membership.offlineUntil)) {
      throw const AccessFailure('membershipDenied');
    }
    final value = CachedCompanySession(
      projectId: gateway.projectId,
      membership: membership,
      verifiedAt: now,
      lastSeenAt: now,
    );
    await store.write(value);
    current = value;
    offline = false;
  }

  Future<void> checkpoint() => _exclusive(() async {
    final value = current;
    final now = clock().toUtc();
    if (value == null ||
        !value.valid(gateway.projectId, value.membership.profile.userId, now)) {
      current = null;
      await store.clear();
      throw const AccessFailure('sessionExpired');
    }
    final updated = value.seen(now);
    await store.write(updated);
    current = updated;
  });
  Future<void> logout() => _exclusive(() async {
    current = null;
    offline = false;
    try {
      await store.clear();
    } finally {
      await gateway.signOut();
    }
  });
}
