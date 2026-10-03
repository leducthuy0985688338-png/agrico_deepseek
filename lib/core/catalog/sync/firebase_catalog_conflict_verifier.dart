import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../company_catalog.dart';
import 'catalog_conflict_decisions.dart';
import 'catalog_sync_receiver.dart';
import 'catalog_sync_sender.dart';

class FirebaseCatalogConflictVerifier implements CatalogConflictVerifier {
  FirebaseCatalogConflictVerifier({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  @override
  Future<String?> currentUserId() async => auth.currentUser?.uid;
  void _identity(String uid) {
    if (auth.currentUser?.uid != uid ||
        auth.app.options.projectId != firestore.app.options.projectId) {
      throw const CatalogSyncUnavailable();
    }
  }

  @override
  Future<CatalogRemoteRecord> verify({
    required String farmId,
    required String actorUid,
    required String entity,
    required String targetId,
  }) async {
    _identity(actorUid);
    if (!CatalogRemoteRecord.validId(farmId) ||
        !CatalogRemoteRecord.validId(targetId) ||
        !{'entry', 'request'}.contains(entity)) {
      throw const CatalogFailure('catalog.syncInvalid');
    }
    try {
      final snapshot = await firestore
          .collection('agrico_catalog')
          .doc(farmId)
          .collection(entity == 'entry' ? 'entries' : 'requests')
          .doc(targetId)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw const CatalogSyncUnavailable(),
          );
      _identity(actorUid);
      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        throw const CatalogSyncUnavailable();
      }
      final d = snapshot.data();
      if (d == null) {
        throw const CatalogFailure('catalog.changed');
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
    }
  }
}
