import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../company_catalog.dart';
import 'catalog_receipt_recovery.dart';
import 'catalog_sync_sender.dart';

class FirebaseCatalogReceiptLookup implements CatalogReceiptLookup {
  FirebaseCatalogReceiptLookup({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  @override
  String? get authenticatedUid => auth.currentUser?.uid;

  void _identity(CatalogSyncCommand command) {
    if (authenticatedUid != command.actorUid ||
        auth.app.options.projectId != firestore.app.options.projectId) {
      throw const CatalogFailure('catalog.denied');
    }
    for (final id in [command.farmId, command.operationId, command.targetId]) {
      if (id.isEmpty ||
          id == '.' ||
          id == '..' ||
          id.contains('/') ||
          utf8.encode(id).length > 500) {
        throw const CatalogFailure('catalog.syncInvalid');
      }
    }
  }

  @override
  Future<Map<String, Object?>?> lookup(CatalogSyncCommand command) async {
    _identity(command);
    try {
      final snapshot = await firestore
          .collection('agrico_catalog')
          .doc(command.farmId)
          .collection('operations')
          .doc(command.operationId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      _identity(command);
      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        throw const CatalogSyncUnavailable();
      }
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data()!;
      if (data['acceptedAt'] is! Timestamp) {
        throw const CatalogFailure('catalog.syncInvalid');
      }
      CatalogReceiptRecovery.verify(command, data);
      return data;
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
