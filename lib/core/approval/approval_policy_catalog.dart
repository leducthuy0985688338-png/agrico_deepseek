import '../permissions/authorization.dart';
import '../periods/period_lock.dart';
import 'approval_policy.dart';

/// Authenticated, non-authoritative metadata. A fresh online verification is
/// still mandatory before any native posting. No business permission floors.
abstract interface class ApprovalPolicyCatalogAuthority {
  Future<ApprovalPolicyCatalog> catalog(
    AuthorizationSubject actor,
    ApprovalKind kind,
    String currency,
  );
  Future<String?> activateCatalog(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
    int expectedLocalActive,
  );
}

class RemoteApprovalPolicy {
  RemoteApprovalPolicy(
    Map<String, dynamic> record,
    int revision,
    String farm,
    ApprovalKind kind,
    String currency, {
    required bool active,
  }) {
    final p = Map<String, dynamic>.from(record['policy'] as Map);
    policy = DocumentApprovalPolicy(
      farm: p['farm'] as String,
      kind: ApprovalKind.values.byName(p['kind'] as String),
      currency: p['currency'] as String,
      version: p['version'] as int,
      selfEnabled: p['selfEnabled'] as bool,
      selfLimit: p['selfLimit'] as String?,
      independentLimit: p['independentLimit'] as String?,
      createPermission: p['createPermission'] as String,
      approvePermission: p['approvePermission'] as String,
      changedBy: p['changedBy'] as String,
      active: active,
      activatedBy: active ? record['activatedBy'] as String? : null,
      activatedAt: active ? record['activatedAt'] as String? : null,
      authorityReference: active ? record['reference'] as String? : null,
    );
    policy.validate();
    if (p.length != policy.toJson().length ||
        !p.keys.toSet().containsAll(policy.toJson().keys)) {
      throw const FormatException('Incomplete canonical policy payload.');
    }
    digest = record['digest'] as String;
    proposedAt = record['proposedAt'] as String;
    authorityRevision = record['authorityRevision'] as int;
    if (policy.farm != farm ||
        policy.kind != kind ||
        policy.currency != currency ||
        PeriodLock.digest(policy.toJson()) != digest ||
        record['version'] != policy.version ||
        record['proposedBy'] != policy.changedBy ||
        DateTime.tryParse(proposedAt) == null ||
        authorityRevision != revision ||
        revision < 1 ||
        (active &&
            (policy.activatedBy == policy.changedBy ||
                (policy.activatedBy ?? '').isEmpty ||
                DateTime.tryParse(policy.activatedAt ?? '') == null ||
                (policy.authorityReference ?? '').isEmpty))) {
      throw const FormatException('Invalid authenticated policy envelope.');
    }
  }
  late final DocumentApprovalPolicy policy;
  late final String digest, proposedAt;
  late final int authorityRevision;
}

class ApprovalPolicyCatalog {
  ApprovalPolicyCatalog(
    Map<String, dynamic> data,
    String farm,
    ApprovalKind kind,
    String currency,
  ) {
    authorityRevision = data['authorityRevision'] as int;
    if (data['farm'] != farm ||
        data['kind'] != kind.name ||
        data['currency'] != currency ||
        authorityRevision < 1) {
      throw const FormatException('Catalog scope mismatch.');
    }
    Map<String, Object?>? identity(dynamic value) {
      if (value == null) return null;
      final m = Map<String, Object?>.from(value as Map);
      if (m.length != 2 ||
          m['version'] is! int ||
          (m['version'] as int) < 1 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(m['digest'] as String)) {
        throw const FormatException('Invalid catalog identity.');
      }
      return Map.unmodifiable(m);
    }

    head = identity(data['head']);
    expectedActive = identity(data['expectedActive']);
    final items = data['drafts'] as List;
    if (items.length > 1) {
      throw const FormatException('Unbounded policy catalog.');
    }
    drafts = List.unmodifiable(
      items.map(
        (r) => RemoteApprovalPolicy(
          Map<String, dynamic>.from(r as Map),
          authorityRevision,
          farm,
          kind,
          currency,
          active: false,
        ),
      ),
    );
    active = data['active'] == null
        ? null
        : RemoteApprovalPolicy(
            Map<String, dynamic>.from(data['active'] as Map),
            authorityRevision,
            farm,
            kind,
            currency,
            active: true,
          );
    for (final d in drafts) {
      if (head?['digest'] != d.digest ||
          head?['version'] != d.policy.version ||
          (expectedActive != null &&
              d.policy.version <= (expectedActive!['version'] as int))) {
        throw const FormatException('Stale draft envelope.');
      }
    }
    if (active != null &&
        (expectedActive?['digest'] != active!.digest ||
            expectedActive?['version'] != active!.policy.version)) {
      throw const FormatException('Active identity mismatch.');
    }
  }
  late final int authorityRevision;
  late final Map<String, Object?>? head, expectedActive;
  late final List<RemoteApprovalPolicy> drafts;
  late final RemoteApprovalPolicy? active;
}
