import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../company_membership.dart';
import 'company_account_admin_service.dart';

class FirebaseCompanyAccountAdminRepository
    implements CompanyAccountAdminRepository {
  FirebaseCompanyAccountAdminRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  static const timeout = Duration(seconds: 15);

  Future<void> _verify() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AccountAdminFailure('denied');
    }
    await user.getIdToken(true).timeout(timeout);
  }

  Future<T> _online<T>(Future<T> Function() action) async {
    try {
      await _verify();
      return await action();
    } on AccountAdminFailure {
      rethrow;
    } on TimeoutException {
      throw const AccountAdminFailure('network');
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        throw const AccountAdminFailure('index');
      }
      throw AccountAdminFailure(
        e.code == 'unavailable' ||
                e.code == 'deadline-exceeded' ||
                e.code == 'network-request-failed'
            ? 'network'
            : 'denied',
      );
    } on FormatException {
      throw const AccountAdminFailure('invalid');
    }
  }

  CompanyAccountRecord _record(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data()!);
    final deadline = data['offlineUntil'];
    if (deadline is! Timestamp ||
        data['userId'] != doc.id ||
        data['membershipId'] != doc.id) {
      throw const FormatException('Invalid account record.');
    }
    data['offlineUntil'] = deadline.toDate().toUtc().toIso8601String();
    return CompanyAccountRecord(
      membership: CompanyMembership.fromJson(data),
      displayName: data['displayName'] as String? ?? doc.id,
      revision: data['adminRevision'] as int? ?? 0,
    );
  }

  @override
  Future<List<CompanyAccountRecord>> list(String farmId) => _online(() async {
    final result = await firestore
        .collection('agrico_memberships')
        .where('farmId', isEqualTo: farmId)
        .limit(200)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    if (result.metadata.isFromCache) {
      throw const AccountAdminFailure('network');
    }
    return result.docs.map(_record).toList();
  });
  @override
  Future<List<AccountAuditRecord>> audit(String farmId) => _online(() async {
    final result = await firestore
        .collection('agrico_access_audit')
        .where('farmId', isEqualTo: farmId)
        .orderBy('occurredAt', descending: true)
        .limit(50)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    return result.docs.map((doc) {
      final d = doc.data();
      return AccountAuditRecord(
        actorUid: d['actorUid'] as String,
        targetUid: d['targetUid'] as String,
        occurredAt: (d['occurredAt'] as Timestamp).toDate(),
        reason: d['reason'] as String,
        revision: d['revision'] as int,
      );
    }).toList();
  });
  @override
  Future<void> save({
    required String actorUid,
    required CompanyAccountRecord record,
    required int? expectedRevision,
    required String reason,
  }) => _online(() async {
    if (auth.currentUser?.uid != actorUid) {
      throw const AccountAdminFailure('denied');
    }
    final ref = firestore.collection('agrico_memberships').doc(record.uid);
    final auditRef = firestore.collection('agrico_access_audit').doc();
    // Firestore transactions require a connection; no queued offline grants.
    await firestore.runTransaction((tx) async {
      final existing = await tx.get(ref);
      final old = existing.data();
      final revision = old?['adminRevision'] as int? ?? 0;
      if ((expectedRevision == null && existing.exists) ||
          (expectedRevision != null &&
              (!existing.exists || expectedRevision != revision))) {
        throw const AccountAdminFailure('stale');
      }
      final data = record.membership.toJson()
        ..['offlineUntil'] = Timestamp.fromDate(record.membership.offlineUntil)
        ..['displayName'] = record.displayName.trim()
        ..['adminRevision'] = revision + 1
        ..['adminAuditId'] = auditRef.id
        ..['updatedBy'] = actorUid
        ..['updatedAt'] = FieldValue.serverTimestamp();
      // Replace the grant snapshot so removed roles/scopes do not accumulate.
      tx.set(ref, data);
      tx.set(auditRef, {
        'farmId': record.membership.profile.farmId,
        'actorUid': actorUid,
        'targetUid': record.uid,
        'revision': revision + 1,
        'reason': reason,
        'occurredAt': FieldValue.serverTimestamp(),
        'before': old,
        'after': data,
      });
    }, timeout: timeout);
  });
}
