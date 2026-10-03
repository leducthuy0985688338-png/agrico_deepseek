import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'company_membership.dart';
import 'company_session.dart';

class FirebaseCompanyIdentityGateway implements CompanyIdentityGateway {
  FirebaseCompanyIdentityGateway({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  static const timeout = Duration(seconds: 15);
  @override
  String get projectId => auth.app.options.projectId;
  @override
  Future<String?> currentUserId() async {
    try {
      return (await auth.authStateChanges().first.timeout(timeout))?.uid;
    } on TimeoutException {
      throw const AccessUnavailable();
    }
  }

  @override
  Future<String> signIn(String email, String password) async {
    try {
      final credential = await auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(timeout);
      final uid = credential.user?.uid;
      if (uid == null) {
        throw const AccessFailure('invalidCredentials');
      }
      return uid;
    } on FirebaseAuthException catch (e) {
      _authFailure(e);
    } on TimeoutException {
      throw const AccessUnavailable();
    }
  }

  @override
  Future<CompanyMembership> fetchMembership(String userId) async {
    try {
      final user = auth.currentUser;
      if (user == null || user.uid != userId) {
        throw const AccessFailure('identityChanged');
      }
      // Force server validation: disabled/revoked accounts must not renew rights.
      await user.getIdToken(true).timeout(timeout);
      final snapshot = await firestore
          .collection('agrico_memberships')
          .doc(userId)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      final data = snapshot.data();
      if (data == null || snapshot.metadata.isFromCache) {
        throw const AccessFailure('membershipDenied');
      }
      final deadline = data['offlineUntil'];
      if (deadline is! Timestamp) {
        throw const AccessFailure('membershipInvalid');
      }
      final normalized = Map<String, dynamic>.from(data)
        ..['offlineUntil'] = deadline.toDate().toUtc().toIso8601String();
      return CompanyMembership.fromJson(normalized);
    } on FirebaseAuthException catch (e) {
      _authFailure(e);
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw const AccessUnavailable();
      }
      throw const AccessFailure('membershipDenied');
    } on TimeoutException {
      throw const AccessUnavailable();
    } on FormatException {
      throw const AccessFailure('membershipInvalid');
    }
  }

  @override
  Future<void> signOut() => auth.signOut();
  @override
  Future<void> resetPassword(String email) async {
    if (email.trim().isEmpty) {
      throw const AccessFailure('credentialsRequired');
    }
    try {
      await auth.sendPasswordResetEmail(email: email.trim()).timeout(timeout);
    } on FirebaseAuthException catch (e) {
      // Keep the same success UI for unknown accounts to avoid enumeration.
      if (e.code != 'user-not-found') {
        _authFailure(e);
      }
    } on TimeoutException {
      throw const AccessUnavailable();
    }
  }

  Never _authFailure(FirebaseAuthException error) {
    if (error.code == 'network-request-failed') {
      throw const AccessUnavailable();
    }
    if (error.code == 'operation-not-allowed' ||
        error.code == 'configuration-not-found') {
      throw const AccessFailure('setupRequired');
    }
    if (error.code == 'too-many-requests') {
      throw const AccessFailure('tryLater');
    }
    throw const AccessFailure('invalidCredentials');
  }
}
