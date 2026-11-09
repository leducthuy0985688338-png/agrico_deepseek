import 'approval_policy.dart';

abstract interface class ApprovalAdministration {
  Future<List<Map<String, Object?>>> list();
  Future<void> propose(DocumentApprovalPolicy policy, String reason);
  Future<void> publishDraft(ApprovalKind kind, String currency, int version);
  Future<void> activate(
    ApprovalKind kind,
    String currency,
    int version,
    int expectedActive,
    String reason,
  );
  Future<List<Map<String, Object?>>> policyHistory();
}

/// Optional remote metadata synchronization; never grants business authority.
abstract interface class RemoteApprovalAdministration {
  Future<void> syncPolicy(ApprovalKind kind, String currency);
}
