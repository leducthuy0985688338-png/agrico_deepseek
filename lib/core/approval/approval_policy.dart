import '../permissions/authorization.dart';
import '../../features/inventory/domain/entities/exact_decimal.dart';

enum ApprovalKind {
  cashReceipt,
  cashPayment,
  settlement,
  payroll,
  payrollExtra,
  payrollAdjustment,
  purchase,
  overheadAllocation,
  correction,
  materialIssue,
  machineRun,
  fieldWork,
  directExpense,
  tradePosting,
}

enum ApprovalOutcome { allowed, independentRequired, denied }

class DocumentApprovalPolicy {
  const DocumentApprovalPolicy({
    required this.farm,
    required this.kind,
    required this.currency,
    required this.version,
    required this.selfEnabled,
    required this.createPermission,
    required this.approvePermission,
    required this.changedBy,
    this.selfLimit,
    this.independentLimit,
    this.activatedBy,
    this.activatedAt,
    this.authorityReference,
    this.active = false,
  });
  final String farm, currency, createPermission, approvePermission, changedBy;
  final String? selfLimit,
      independentLimit,
      activatedBy,
      activatedAt,
      authorityReference;
  final int version;
  final bool selfEnabled, active;
  final ApprovalKind kind;
  static const selfKinds = {
    ApprovalKind.materialIssue,
    ApprovalKind.machineRun,
    ApprovalKind.fieldWork,
    ApprovalKind.directExpense,
  };
  bool get independentOnly => !selfKinds.contains(kind);
  void validate() {
    if (farm.trim().isEmpty ||
        !{'VND', 'LAK'}.contains(currency) ||
        version < 1 ||
        createPermission.isEmpty ||
        approvePermission.isEmpty ||
        changedBy.isEmpty ||
        (independentOnly && selfEnabled)) {
      throw const FormatException('Invalid approval policy.');
    }
    for (final limit in [selfLimit, independentLimit]) {
      if (limit != null && ExactDecimal.parse(limit).isNegative) {
        throw const FormatException('Negative approval limit.');
      }
    }
    if (selfEnabled && selfLimit == null) {
      throw const FormatException('Explicit self limit required.');
    }
  }

  Map<String, Object?> toJson() => {
    'farm': farm,
    'kind': kind.name,
    'currency': currency,
    'version': version,
    'selfEnabled': selfEnabled,
    'selfLimit': selfLimit,
    'independentLimit': independentLimit,
    'createPermission': createPermission,
    'approvePermission': approvePermission,
    'changedBy': changedBy,
  };
}

class ApprovalContext {
  ApprovalContext({
    required this.farm,
    required this.kind,
    required this.sourceId,
    required this.revision,
    required this.digest,
    required this.creator,
    required this.createdAt,
    required this.currency,
    required this.total,
    required this.policyVersion,
    this.state = 'pending',
    this.periodOpen = false,
    this.metadataComplete = false,
    this.relatedKey,
    this.linkEvidenceVerified = false,
    this.beneficiariesVerified = false,
    Set<String> beneficiaries = const {},
    this.relatedTotal,
    this.relatedDocuments = 1,
    this.resource,
    this.requiredPermissions = const {},
  }) : beneficiaries = Set.unmodifiable(beneficiaries);
  final String farm,
      sourceId,
      digest,
      creator,
      createdAt,
      currency,
      total,
      state;
  final int revision, policyVersion, relatedDocuments;
  final String? relatedKey, relatedTotal;
  final bool periodOpen,
      metadataComplete,
      linkEvidenceVerified,
      beneficiariesVerified;
  final ApprovalKind kind;
  final Set<String> beneficiaries;
  final ResourceContext? resource;
  final Set<String> requiredPermissions;
}

class ApprovalDecision {
  const ApprovalDecision(
    this.outcome,
    this.reason, {
    this.policyVersion,
    this.aggregate,
  });
  final ApprovalOutcome outcome;
  final String reason;
  final int? policyVersion;
  final String? aggregate;
  bool get allowed => outcome == ApprovalOutcome.allowed;
}

abstract final class ApprovalRules {
  static const policyManage = 'approval.policy.manage',
      limitManage = 'approval.limits.manage',
      policyActivate = 'approval.policy.activate',
      auditView = 'approval.audit.view';
  static String selfPermission(ApprovalKind kind) =>
      'approval.self.${kind.name}';
  static ApprovalDecision evaluate(
    ApprovalContext c,
    DocumentApprovalPolicy? p,
    AuthorizationSubject actor,
  ) {
    final self = actor.userId == c.creator;
    ApprovalDecision deny(
      String reason, {
      bool independent = false,
      String? aggregate,
    }) => ApprovalDecision(
      self && independent
          ? ApprovalOutcome.independentRequired
          : ApprovalOutcome.denied,
      reason,
      policyVersion: p?.version,
      aggregate: aggregate,
    );
    if ((c.resource != null && c.resource!.farmId != c.farm) ||
        c.farm != actor.farmId ||
        !actor.active ||
        (actor.validUntil != null &&
            !DateTime.now().isBefore(actor.validUntil!))) {
      return deny('inactiveOrWrongScope');
    }
    if (c.state != 'pending') return deny('notPending');
    if (!c.periodOpen) return deny('periodClosed');
    if (!c.metadataComplete ||
        c.sourceId.isEmpty ||
        c.creator.isEmpty ||
        c.revision < 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(c.digest) ||
        DateTime.tryParse(c.createdAt) == null) {
      return deny('incompleteSource');
    }
    if (!{'VND', 'LAK'}.contains(c.currency)) return deny('unknownCurrency');
    if (p == null ||
        !p.active ||
        (p.authorityReference ?? '').trim().isEmpty ||
        DateTime.tryParse(p.activatedAt ?? '') == null ||
        (p.activatedBy ?? '').isEmpty ||
        p.activatedBy == p.changedBy) {
      return deny('noActivePolicy', independent: true);
    }
    try {
      p.validate();
    } catch (_) {
      return deny('invalidPolicy');
    }
    if (p.farm != c.farm || p.kind != c.kind || p.currency != c.currency) {
      return deny('policyScopeMismatch');
    }
    if (p.version != c.policyVersion) return deny('policyChanged');
    final auth = const AuthorizationService();
    bool can(String permission) => auth.can(
      subject: actor,
      permission: permission,
      resource: c.resource ?? ResourceContext(farmId: c.farm),
    );
    if (!can(p.approvePermission)) return deny('approvalPermissionMissing');
    if (!can(nativeApprovePermission(c.kind))) {
      return deny('nativeApprovalPermissionMissing');
    }
    if (!c.requiredPermissions.every(can)) {
      return deny('nativeApprovalPermissionMissing');
    }
    if (c.beneficiaries.contains(actor.userId)) {
      return deny('conflictOfInterest');
    }
    ExactDecimal amount, aggregate;
    try {
      amount = ExactDecimal.parse(
        c.total.startsWith('-') ? c.total.substring(1) : c.total,
      );
      aggregate = ExactDecimal.parse(c.relatedTotal ?? amount.toString());
      if (aggregate.isNegative || aggregate.compareTo(amount) < 0) {
        return deny('invalidRelatedExposure');
      }
    } catch (_) {
      return deny('invalidExactAmount');
    }
    if (self) {
      if (p.independentOnly || !p.selfEnabled) {
        return deny('independentApprovalRequired', independent: true);
      }
      if (!can(p.createPermission) ||
          !can(nativeCreatePermission(c.kind)) ||
          !can(selfPermission(c.kind))) {
        return deny('selfPermissionMissing', independent: true);
      }
      if (!c.beneficiariesVerified ||
          !c.linkEvidenceVerified ||
          c.relatedKey == null) {
        return deny('insufficientConflictOrLinkEvidence', independent: true);
      }
      final activated = DateTime.tryParse(p.activatedAt!);
      if (activated == null ||
          !DateTime.parse(c.createdAt).isAfter(activated)) {
        return deny('policyCannotUpgradePendingSelf', independent: true);
      }
      if (c.relatedDocuments > 1) {
        return deny(
          'relatedDocumentsRequireIndependentReview',
          independent: true,
          aggregate: aggregate.toString(),
        );
      }
      if (p.selfLimit == null ||
          aggregate.compareTo(ExactDecimal.parse(p.selfLimit!)) > 0) {
        return deny(
          'selfLimitExceeded',
          independent: true,
          aggregate: aggregate.toString(),
        );
      }
    } else {
      if (p.independentLimit == null) {
        return deny('independentLimitNotConfigured');
      }
      if (aggregate.compareTo(ExactDecimal.parse(p.independentLimit!)) > 0) {
        return deny(
          'independentLimitExceeded',
          aggregate: aggregate.toString(),
        );
      }
    }
    return ApprovalDecision(
      ApprovalOutcome.allowed,
      self ? 'explicitSelfApproval' : 'independentApproval',
      policyVersion: p.version,
      aggregate: aggregate.toString(),
    );
  }

  /// Policy may add a constraint, never replace the native permission floor.
  static String nativeApprovePermission(ApprovalKind kind) => switch (kind) {
    ApprovalKind.machineRun => PermissionCodes.machineVerify,
    ApprovalKind.fieldWork => PermissionCodes.attendanceVerify,
    ApprovalKind.payroll ||
    ApprovalKind.payrollExtra ||
    ApprovalKind.payrollAdjustment => PermissionCodes.payrollApprove,
    ApprovalKind.purchase => PermissionCodes.purchaseApprove,
    _ => PermissionCodes.financeApprove,
  };
  static String nativeCreatePermission(ApprovalKind kind) => switch (kind) {
    ApprovalKind.materialIssue => PermissionCodes.inventoryManage,
    ApprovalKind.machineRun => PermissionCodes.machineLog,
    ApprovalKind.fieldWork => PermissionCodes.attendanceRecord,
    _ => PermissionCodes.financeCreate,
  };
}
