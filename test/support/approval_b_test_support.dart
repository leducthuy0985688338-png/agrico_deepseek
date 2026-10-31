import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/sqlite_approval_policy_store.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Synthetic authority only. Never imported by lib or provisioned remotely.
class SyntheticApprovalAuthority
    implements ApprovalAuthority, ApprovalRelationsAuthority {
  bool current = true;
  void Function()? onVerify;
  final Map<String, Set<String>> partyUsers = {};
  @override
  Future<Set<String>?> beneficiaryUsers(String farm, String partyId) async =>
      current ? partyUsers[partyId] : null;
  @override
  Future<String?> activationReference(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
  ) async => 'TEST-ONLY:$digest';
  @override
  Future<bool> isActivationCurrent(
    DocumentApprovalPolicy policy,
    String digest,
  ) async {
    onVerify?.call();
    return current && policy.authorityReference == 'TEST-ONLY:$digest';
  }
}

AuthorizationSubject approvalUser(
  String id, {
  String farm = 'f',
  Set<String>? permissions,
  bool active = true,
}) => AuthorizationSubject(
  userId: id,
  membershipId: id,
  farmId: farm,
  active: active,
  permissionCodes: permissions ?? PermissionCodes.values,
  dataScopes: const {DataScope.allFarm},
  validUntil: DateTime.now().add(const Duration(days: 1)),
);
Future<void> syntheticPolicy(
  Database db,
  SyntheticApprovalAuthority authority,
  ApprovalKind kind,
  String currency, {
  int version = 1,
  String selfLimit = '1000',
  String independentLimit = '1000000000000000000000000000000',
}) async {
  await SqliteApprovalPolicyStore.createSchema(db);
  var actor = approvalUser('test-policy-author');
  SqliteApprovalPolicyStore store() => SqliteApprovalPolicyStore(
    db,
    opened: actor,
    currentSubject: () => actor,
    authority: authority,
  );
  await store().propose(
    DocumentApprovalPolicy(
      farm: 'f',
      kind: kind,
      currency: currency,
      version: version,
      selfEnabled: DocumentApprovalPolicy.selfKinds.contains(kind),
      selfLimit: selfLimit,
      independentLimit: independentLimit,
      createPermission: ApprovalRules.nativeCreatePermission(kind),
      approvePermission: ApprovalRules.nativeApprovePermission(kind),
      changedBy: actor.userId,
    ),
    'Synthetic native-adapter test configuration',
  );
  actor = approvalUser('test-policy-activator');
  await store().activate(
    kind,
    currency,
    version,
    version - 1,
    'Synthetic authority; no production identity',
  );
}
