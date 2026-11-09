import 'package:sqflite/sqflite.dart';

import '../../permissions/authorization.dart';
import 'catalog_sync_workspace.dart';
import 'firebase_catalog_sync_transport.dart';
import 'firebase_catalog_receive_transport.dart';
import 'firebase_catalog_receipt_lookup.dart';
import 'firebase_catalog_conflict_verifier.dart';
import 'firebase_catalog_publication_verifier.dart';
import 'firebase_catalog_restore_transport.dart';

CatalogSyncWorkspace firebaseCatalogSyncWorkspace({
  required Database database,
  required AuthorizationSubject? Function() currentSubject,
}) => CatalogSyncWorkspace(
  database: database,
  currentSubject: currentSubject,
  sendTransport: FirebaseCatalogSyncTransport(),
  receiveTransport: FirebaseCatalogReceiveTransport(),
  receiptLookup: FirebaseCatalogReceiptLookup(),
  conflictVerifier: FirebaseCatalogConflictVerifier(),
  publicationVerifier: FirebaseCatalogPublicationVerifier(),
  restoreTransport: FirebaseCatalogRestoreTransport(),
);
