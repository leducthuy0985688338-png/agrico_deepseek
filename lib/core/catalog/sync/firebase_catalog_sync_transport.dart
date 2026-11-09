import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'catalog_sync_sender.dart';

/// Transactional adapter. App wiring is deferred until receiver/reconciliation
/// is available. Firestore Rules, not this adapter, are the authority.
class FirebaseCatalogSyncTransport implements CatalogSyncTransport {
  FirebaseCatalogSyncTransport({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  @override
  Future<String?> currentUserId() async => auth.currentUser?.uid;

  static String keyId(String kind, String type, String value) =>
      '$kind~$type~${sha256.convert(utf8.encode(value)).toString().toUpperCase()}';

  static Map<String, Object?> commandData(CatalogSyncCommand command) => {
    'operationId': command.operationId,
    'farmId': command.farmId,
    'actorUid': command.actorUid,
    'entity': command.entity,
    'targetId': command.targetId,
    'baseVersion': command.baseVersion,
    'newVersion': command.newVersion,
    'payload': command.payload,
    'reason': command.reason,
    'occurredAt': command.occurredAt,
  };

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) {
      return value.map(_canonical).toList();
    }
    return value;
  }

  static CatalogSyncReceipt receipt(
    CatalogSyncCommand command,
    Map<String, dynamic> data,
  ) {
    final expected = commandData(command);
    final actual = {for (final key in expected.keys) key: data[key]};
    if (jsonEncode(_canonical(expected)) != jsonEncode(_canonical(actual))) {
      throw const CatalogSyncRejected('catalog.syncInvalid', conflict: true);
    }
    return CatalogSyncReceipt(
      operationId: command.operationId,
      farmId: command.farmId,
      actorUid: command.actorUid,
      entity: command.entity,
      targetId: command.targetId,
      cloudVersion: command.newVersion,
      payload: command.payload,
    );
  }

  void _identity(CatalogSyncCommand command) {
    if (auth.app.options.projectId != firestore.app.options.projectId) {
      throw const CatalogSyncRejected('catalog.syncInvalid', conflict: false);
    }
    if (auth.currentUser?.uid != command.actorUid) {
      throw const CatalogSyncUnavailable();
    }
    for (final id in [command.farmId, command.targetId, command.operationId]) {
      if (id.isEmpty ||
          id.contains('/') ||
          id == '.' ||
          id == '..' ||
          utf8.encode(id).length > 500) {
        throw const CatalogSyncRejected('catalog.syncInvalid', conflict: false);
      }
    }
    if (!{'entry', 'request'}.contains(command.entity)) {
      throw const CatalogSyncRejected('catalog.syncInvalid', conflict: false);
    }
  }

  @override
  Future<CatalogSyncReceipt> send(CatalogSyncCommand command) async {
    _identity(command);
    final root = firestore.collection('agrico_catalog').doc(command.farmId);
    final target = root
        .collection(command.entity == 'entry' ? 'entries' : 'requests')
        .doc(command.targetId);
    final operation = root.collection('operations').doc(command.operationId);
    try {
      return await firestore.runTransaction<CatalogSyncReceipt>(
        (tx) async {
          _identity(command);
          final existing = await tx.get(operation);
          if (existing.exists) {
            return receipt(command, existing.data()!);
          }
          final oldDoc = await tx.get(target);
          final oldEnvelope = oldDoc.data();
          if ((oldEnvelope?['version'] ?? 0) != command.baseVersion) {
            throw const CatalogSyncRejected('catalog.changed', conflict: true);
          }
          final old = (oldEnvelope?['payload'] as Map?)
              ?.cast<String, dynamic>();
          final next = command.payload;
          final writes =
              <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};
          if (command.entity == 'entry') {
            final kind = next['kind'] as String;
            final code = next['code'] as String;
            final name = next['name_key'] as String;
            final keys = <String, Map<String, dynamic>>{
              keyId(kind, 'code', code): {
                'targetId': command.targetId,
                'type': 'code',
                'value': code,
              },
              keyId(kind, 'name', name): {
                'targetId': command.targetId,
                'type': 'name',
                'value': name,
              },
              if (old != null && old['name_key'] != name)
                keyId(kind, 'name', old['name_key'] as String): {
                  'targetId': null,
                  'type': 'name',
                  'value': old['name_key'],
                },
            };
            for (final pair in keys.entries) {
              final ref = root.collection('keys').doc(pair.key);
              final prior = (await tx.get(ref)).data();
              if (prior != null &&
                  prior['targetId'] != null &&
                  prior['targetId'] != command.targetId) {
                throw const CatalogSyncRejected(
                  'catalog.duplicate',
                  conflict: true,
                );
              }
              writes[ref] = {...pair.value, 'operationId': command.operationId};
            }
            if (kind == 'unit' && old != null) {
              final usage = (await tx.get(
                root.collection('unit_usage').doc(command.targetId),
              )).data();
              if ((old['name'] != next['name'] &&
                      (usage?['references'] ?? 0) != 0) ||
                  (next['active'] == 0 &&
                      (usage?['activeReferences'] ?? 0) != 0)) {
                throw const CatalogSyncRejected(
                  'catalog.unitInUse',
                  conflict: true,
                );
              }
            }
            final oldUnit = old?['unit_id'] as String?;
            final nextUnit = next['unit_id'] as String?;
            final units = <String>{?oldUnit, ?nextUnit};
            for (final unit in units) {
              final unitDoc = (await tx.get(
                root.collection('entries').doc(unit),
              )).data();
              if (next['unit_id'] == unit &&
                  (unitDoc == null ||
                      (unitDoc['payload'] as Map)['kind'] != 'unit' ||
                      (unitDoc['payload'] as Map)['active'] != 1)) {
                throw const CatalogSyncRejected(
                  'catalog.unitRequired',
                  conflict: true,
                );
              }
              final ref = root.collection('unit_usage').doc(unit);
              final usage = (await tx.get(ref)).data();
              final before = old?['unit_id'] == unit ? 1 : 0;
              final after = next['unit_id'] == unit ? 1 : 0;
              final activeBefore = before == 1 && old?['active'] == 1 ? 1 : 0;
              final activeAfter = after == 1 && next['active'] == 1 ? 1 : 0;
              writes[ref] = {
                'references': (usage?['references'] ?? 0) + after - before,
                'activeReferences':
                    (usage?['activeReferences'] ?? 0) +
                    activeAfter -
                    activeBefore,
                'operationId': command.operationId,
              };
            }
          } else if (next['status'] == 'approved') {
            final entry = (await tx.get(
              root.collection('entries').doc(next['entry_id'] as String),
            )).data();
            if (entry == null ||
                (entry['payload'] as Map)['active'] != 1 ||
                (entry['payload'] as Map)['kind'] != next['kind']) {
              throw const CatalogSyncRejected(
                'catalog.invalid',
                conflict: true,
              );
            }
          }
          _identity(command);
          for (final write in writes.entries) {
            tx.set(write.key, write.value);
          }
          tx.set(target, {
            'version': command.newVersion,
            'operationId': command.operationId,
            'payload': next,
          });
          tx.set(operation, {
            ...commandData(command),
            'before': old,
            'acceptedAt': FieldValue.serverTimestamp(),
          });
          return receipt(command, commandData(command));
        },
        timeout: const Duration(seconds: 20),
        maxAttempts: 3,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const CatalogSyncRejected('catalog.denied', conflict: false);
      }
      // SDK/network failures have uncertain commit outcomes. Preserve the ID.
      throw const CatalogSyncUnavailable();
    }
  }
}
