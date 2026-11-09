import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../company_catalog.dart';
import 'catalog_sync_receiver.dart';
import 'catalog_sync_sender.dart';

class FirebaseCatalogReceiveTransport implements CatalogReceiveTransport {
  FirebaseCatalogReceiveTransport({
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
  Future<CatalogRemotePage> fetch({
    required String farmId,
    required String actorUid,
    required String entity,
    required bool allRequests,
    required int limit,
    String? cursor,
  }) async {
    _identity(actorUid);
    if (!CatalogRemoteRecord.validId(farmId) ||
        !{'entry', 'request'}.contains(entity) ||
        limit < 1 ||
        limit > 200 ||
        (cursor != null && !CatalogRemoteRecord.validId(cursor))) {
      throw const CatalogFailure('catalog.syncInvalid');
    }
    Query<Map<String, dynamic>> query = firestore
        .collection('agrico_catalog')
        .doc(farmId)
        .collection(entity == 'entry' ? 'entries' : 'requests');
    if (entity == 'request' && !allRequests) {
      query = query.where('payload.actor_uid', isEqualTo: actorUid);
    }
    query = query.orderBy(FieldPath.documentId).limit(limit);
    if (cursor != null) {
      query = query.startAfter([cursor]);
    }
    try {
      final result = await query
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw const CatalogSyncUnavailable(),
          );
      _identity(actorUid);
      if (result.metadata.isFromCache || result.metadata.hasPendingWrites) {
        throw const CatalogSyncUnavailable();
      }
      final records = <CatalogRemoteRecord>[];
      for (final doc in result.docs) {
        final d = doc.data();
        if (d.length != 3 ||
            d['version'] is! int ||
            d['operationId'] is! String ||
            d['payload'] is! Map) {
          throw const CatalogFailure('catalog.syncInvalid');
        }
        records.add(
          CatalogRemoteRecord(
            farmId: farmId,
            entity: entity,
            targetId: doc.id,
            version: d['version'] as int,
            operationId: d['operationId'] as String,
            payload: (d['payload'] as Map).cast<String, Object?>(),
          ),
        );
      }
      return CatalogRemotePage(
        records: records,
        nextCursor: records.length == limit ? records.last.targetId : null,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const CatalogFailure('catalog.denied');
      }
      throw const CatalogSyncUnavailable();
    }
  }
}
