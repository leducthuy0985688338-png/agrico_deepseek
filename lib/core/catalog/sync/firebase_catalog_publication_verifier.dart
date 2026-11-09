import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../company_catalog.dart';
import 'catalog_initial_publication.dart';
import 'catalog_sync_receiver.dart';
import 'catalog_sync_sender.dart';

class FirebaseCatalogPublicationVerifier implements CatalogPublicationVerifier {
  FirebaseCatalogPublicationVerifier({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  @override
  String? get authenticatedUid => auth.currentUser?.uid;
  void _identity(String uid) {
    if (authenticatedUid != uid ||
        auth.app.options.projectId != firestore.app.options.projectId) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  @override
  Future<CatalogRemoteRecord?> read({
    required String farmId,
    required String actorUid,
    required String targetId,
  }) async {
    _identity(actorUid);
    if (!CatalogRemoteRecord.validId(farmId) ||
        !CatalogRemoteRecord.validId(targetId)) {
      throw const CatalogFailure('catalog.syncInvalid');
    }
    try {
      final snapshot = await firestore
          .collection('agrico_catalog')
          .doc(farmId)
          .collection('entries')
          .doc(targetId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      _identity(actorUid);
      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        throw const CatalogSyncUnavailable();
      }
      final data = snapshot.data();
      if (data == null) {
        return null;
      }
      if (data.length != 3 ||
          data['version'] is! int ||
          data['operationId'] is! String ||
          data['payload'] is! Map) {
        throw const CatalogFailure('catalog.syncInvalid');
      }
      return CatalogRemoteRecord(
        farmId: farmId,
        entity: 'entry',
        targetId: targetId,
        version: data['version'] as int,
        operationId: data['operationId'] as String,
        payload: (data['payload'] as Map).cast<String, Object?>(),
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const CatalogFailure('catalog.denied');
      }
      throw const CatalogSyncUnavailable();
    } on TimeoutException {
      throw const CatalogSyncUnavailable();
    }
  }
}
