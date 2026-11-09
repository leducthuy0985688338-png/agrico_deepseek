import 'package:agrico_deepseek/core/auth/company_membership.dart';
import 'package:agrico_deepseek/core/auth/company_session.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';

final start = DateTime.utc(2030, 1, 1);
CompanyMembership membership({
  String uid = 'user',
  String farm = 'local-farm',
  bool active = true,
  DateTime? deadline,
}) => CompanyMembership(
  profile: CompanyAccessProfile(
    userId: uid,
    membershipId: uid,
    farmId: farm,
    active: active,
    roles: [RoleAssignment(CompanyRole.systemAdmin)],
    offlineValidUntil: deadline ?? start.add(const Duration(days: 2)),
  ),
  offlineUntil: deadline ?? start.add(const Duration(days: 2)),
);

class MemoryStore implements CompanySessionStore {
  CachedCompanySession? value;
  @override
  Future<CachedCompanySession?> read() async => value;
  @override
  Future<void> write(CachedCompanySession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Gateway implements CompanyIdentityGateway {
  @override
  String projectId = 'project';
  String? uid;
  Object? fetchError, loginError;
  CompanyMembership grant = membership();
  int logouts = 0;
  @override
  Future<String?> currentUserId() async => uid;
  @override
  Future<String> signIn(String email, String password) async {
    if (loginError != null) {
      throw loginError!;
    }
    if (password != 'correct') {
      throw const AccessFailure('invalidCredentials');
    }
    return uid = 'user';
  }

  @override
  Future<CompanyMembership> fetchMembership(String userId) async {
    if (fetchError != null) {
      throw fetchError!;
    }
    return grant;
  }

  @override
  Future<void> signOut() async {
    uid = null;
    logouts++;
  }

  @override
  Future<void> resetPassword(String email) async {}
}
