import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import '../permissions/authorization.dart';
import 'approval_policy.dart';
import 'sqlite_approval_policy_store.dart';

/// Online callable protocol using existing HTTP/Auth dependencies. No persisted
/// authority cache, technical-admin fallback, or Receipt endpoint changes.
class FirebaseApprovalAuthority
    implements
        ApprovalAuthority,
        ApprovalRelationsAuthority,
        ApprovalDraftAuthority {
  FirebaseApprovalAuthority({
    this.client,
    this.endpoint,
    this.idToken,
    this.userId,
  });
  final http.Client? client;
  final Uri Function(String name)? endpoint;
  final Future<String?> Function()? idToken;
  final String? Function()? userId;
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
    if (result['proposed'] != true)
      throw StateError('Policy proposal not acknowledged.');
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
    final token =
        await (idToken?.call() ??
            FirebaseAuth.instance.currentUser?.getIdToken(true) ??
            Future<String?>.value());
    if (token == null || uid != opened) {
      throw StateError('Approval authority session changed.');
    }
    final uri =
        endpoint?.call(name) ??
        Uri.https(
          'asia-southeast1-${Firebase.app().options.projectId}.cloudfunctions.net',
          '/$name',
        );
    final transport = client ?? http.Client();
    try {
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
      if (uid != opened) {
        throw StateError('Approval authority session changed.');
      }
      final data = jsonDecode(response.body) as Map;
      if (response.statusCode != 200 ||
          data['error'] != null ||
          data['result'] is! Map) {
        throw StateError('Approval authority unavailable or denied.');
      }
      return Map<String, dynamic>.from(data['result'] as Map);
    } finally {
      if (client == null) transport.close();
    }
  }

  @override
  Future<String?> activationReference(
    AuthorizationSubject actor,
    DocumentApprovalPolicy policy,
    String digest,
  ) async {
    final response = await call('companyApprovalAuthority', {
      'operation': 'activate',
      'policy': policy.toJson(),
      'digest': digest,
    }, expectedUid: actor.userId);
    return response['reference'] as String?;
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
