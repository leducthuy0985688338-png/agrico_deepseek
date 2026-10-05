import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../company_catalog.dart';
import 'catalog_restore_reconciliation.dart';
import 'catalog_sync_receiver.dart';
import 'catalog_sync_sender.dart';
import 'firebase_catalog_receive_transport.dart';

/// Reuses server-only bounded queries; adds fresh exact-target reads for release.
class FirebaseCatalogRestoreTransport extends FirebaseCatalogReceiveTransport
    implements CatalogRestoreTransport {
  FirebaseCatalogRestoreTransport({super.auth, super.firestore});
  @override
  String? get authenticatedUid => auth.currentUser?.uid;
  void _check(String uid) {
    if (authenticatedUid != uid ||
        auth.app.options.projectId != firestore.app.options.projectId) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  @override
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  }) async {
    _check(actorUid);
    if (!CatalogRemoteRecord.validId(farmId) ||
        !CatalogRemoteRecord.validId(targetId) ||
        !{'entry', 'request'}.contains(entity)) {
      throw const CatalogFailure('catalog.syncInvalid');
    }
    try {
      final doc = await firestore
          .collection('agrico_catalog')
          .doc(farmId)
          .collection(entity == 'entry' ? 'entries' : 'requests')
          .doc(targetId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      _check(actorUid);
      if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites) {
        throw const CatalogSyncUnavailable();
      }
      final d = doc.data();
      if (d == null) {
        return null;
      }
      if (d.length != 3 ||
          d['version'] is! int ||
          d['operationId'] is! String ||
          d['payload'] is! Map) {
        throw const CatalogFailure('catalog.syncInvalid');
      }
      return CatalogRemoteRecord(
        farmId: farmId,
        entity: entity,
        targetId: targetId,
        version: d['version'] as int,
        operationId: d['operationId'] as String,
        payload: (d['payload'] as Map).cast<String, Object?>(),
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CatalogFailure('catalog.denied');
      }
      throw const CatalogSyncUnavailable();
    } on TimeoutException {
      throw const CatalogSyncUnavailable();
    }
  }
}
