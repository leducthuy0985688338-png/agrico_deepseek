import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import '../permissions/authorization.dart';
import 'approval_policy.dart';
import 'approval_policy_catalog.dart';
import 'sqlite_approval_policy_store.dart';

/// Online callable protocol using existing HTTP/Auth dependencies. No persisted
/// authority cache, technical-admin fallback, or Receipt endpoint changes.
class FirebaseApprovalAuthority
    implements
        ApprovalAuthority,
        ApprovalRelationsAuthority,
        ApprovalDraftAuthority,
        ApprovalPolicyCatalogAuthority {
  FirebaseApprovalAuthority({
    this.client,
    this.endpoint,
    this.idToken,
    this.userId,
    this.sessionEpoch,
  });
  final http.Client? client;
  final Uri Function(String name)? endpoint;
  final Future<String?> Function()? idToken;
  final String? Function()? userId;
  final Object? Function()? sessionEpoch;
  String? get uid =>
      userId != null ? userId!() : FirebaseAuth.instance.currentUser?.uid;
  @override
  Future<void> publishDraft(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
  ) async {
    final result = await call('companyApprovalAuthority', {
      'operation': 'propose',
      'policy': policy.toJson(),
      'digest': digest,
    }, expectedUid: actor.userId);
    if (result['proposed'] != true) {
      throw StateError('Policy proposal not acknowledged.');
    }
  }

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, Object?> input, {
    String? expectedUid,
  }) async {
    final opened = uid;
    if (opened == null || (expectedUid != null && expectedUid != opened)) {
      throw StateError('Approval authority session missing.');
    }
    final epoch = sessionEpoch?.call();
    var invalidated = false;
    StreamSubscription<User?>? watch;
    final transport = client ?? http.Client();
    try {
      // Subscribe per request, not per service lifetime. Auth state changes
      // invalidate even logout/login of the same UID; token refresh is separate.
      if (userId == null) {
        final ready = Completer<void>();
        var initial = true;
        watch = FirebaseAuth.instance.authStateChanges().listen(
          (user) {
            if (initial) {
              initial = false;
              invalidated = user?.uid != opened;
              ready.complete();
            } else {
              invalidated = true;
            }
          },
          onError: (Object e) {
            invalidated = true;
            if (!ready.isCompleted) ready.completeError(e);
          },
        );
        await ready.future.timeout(const Duration(seconds: 5));
      }
      bool current() =>
          !invalidated && uid == opened && sessionEpoch?.call() == epoch;
      final token =
          await (idToken?.call() ??
              FirebaseAuth.instance.currentUser?.getIdToken(true) ??
              Future<String?>.value());
      if (token == null || !current()) {
        throw StateError('Approval authority session changed.');
      }
      final uri =
          endpoint?.call(name) ??
          Uri.https(
            'asia-southeast1-${Firebase.app().options.projectId}.cloudfunctions.net',
            '/$name',
          );
      final response = await transport
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'data': input}),
          )
          .timeout(const Duration(seconds: 15));
      if (!current()) throw StateError('Approval authority session changed.');
      final data = jsonDecode(response.body) as Map;
      if (response.statusCode != 200 ||
          data['error'] != null ||
          data['result'] is! Map) {
        throw StateError('Approval authority unavailable or denied.');
      }
      return Map<String, dynamic>.from(data['result'] as Map);
    } finally {
      await watch?.cancel();
      if (client == null) transport.close();
    }
  }

  @override
  Future<ApprovalPolicyCatalog> catalog(
    AuthorizationSubject actor,
    ApprovalKind kind,
    String currency,
  ) async => ApprovalPolicyCatalog(
    await call('companyApprovalAuthority', {
      'operation': 'listDrafts',
      'farm': actor.farmId,
      'kind': kind.name,
      'currency': currency,
    }, expectedUid: actor.userId),
    actor.farmId,
    kind,
    currency,
  );

  @override
  Future<String?> activateCatalog(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
    int expectedLocalActive,
  ) async {
    final snapshot = await catalog(actor, policy.kind, policy.currency);
    return _activateSnapshot(
      actor,
      policy,
      digest,
      expectedLocalActive,
      snapshot,
    );
  }

  Future<String?> _activateSnapshot(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
    int expectedLocalActive,
    ApprovalPolicyCatalog snapshot,
  ) async {
    if (snapshot.head?['digest'] != digest) {
      throw StateError('Draft head changed; synchronize and review again.');
    }
    if (snapshot.active?.digest == digest) {
      if (snapshot.active!.policy.activatedBy != actor.userId) {
        throw StateError('Policy activated by another reviewer.');
      }
      // Recover an unknown network outcome without repeating a mutation.
      return snapshot.active!.policy.authorityReference;
    }
    if ((snapshot.active?.policy.version ?? 0) != expectedLocalActive ||
        snapshot.head?['digest'] != digest ||
        !(snapshot.drafts.any((d) => d.digest == digest) ||
            snapshot.active?.digest == digest)) {
      throw StateError('Server policy changed; synchronize and review again.');
    }
    final response = await call('companyApprovalAuthority', {
      'operation': 'activate',
      'policy': policy.toJson(),
      'digest': digest,
      'expectedActive': snapshot.expectedActive,
      'expectedDraftHead': snapshot.head,
      'expectedAuthorityRevision': snapshot.authorityRevision,
    }, expectedUid: actor.userId);
    return response['reference'] as String?;
  }

  @override
  Future<String?> activationReference(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
  ) async {
    final snapshot = await catalog(actor, policy.kind, policy.currency);
    return _activateSnapshot(
      actor,
      policy,
      digest,
      snapshot.active?.policy.version ?? 0,
      snapshot,
    );
  }

  @override
  Future<bool> isActivationCurrent(
    DocumentApprovalPolicy policy,
    String digest,
  ) async {
    try {
      final response = await call('companyApprovalAuthority', {
        'operation': 'verify',
        'policy': policy.toJson(),
        'digest': digest,
        'reference': policy.authorityReference,
        'activatedBy': policy.activatedBy,
        'activatedAt': policy.activatedAt,
      });
      return response['current'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Set<String>?> beneficiaryUsers(String farm, String partyId) async {
    try {
      final response = await call('companyApprovalRelations', {
        'farm': farm,
        'partyId': partyId,
      });
      return response['verified'] == true
          ? Set<String>.from(response['users'] as List)
          : null;
    } catch (_) {
      return null;
    }
  }
}
