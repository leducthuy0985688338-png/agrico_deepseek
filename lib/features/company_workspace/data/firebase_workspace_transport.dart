import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:crypto/crypto.dart';

import '../domain/workspace.dart';

class FirebaseWorkspaceTransport implements WorkspaceTransport {
  void session(String uid) {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw const WorkspaceFailure('session');
    }
  }

  @override
  Future<Json> send(String f, String u, String op, Json command) async {
    session(u);
    final firestore = FirebaseFirestore.instance;
    final ref = firestore.doc('agrico_workspace/$f/users/$u/commands/$op');
    await firestore.runTransaction((tx) async {
      final old = await tx.get(ref);
      if (!old.exists) {
        tx.set(ref, {
          ...command,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
          'schemaVersion': 1,
        });
      } else {
        for (final k in ['action', 'entityId', 'expectedRevision', 'payload']) {
          if (canonical(old.data()![k]) != canonical(command[k])) {
            throw const WorkspaceFailure('conflict');
          }
        }
      }
    });
    for (var i = 0; i < (command['action'] == 'ai.ask' ? 50 : 12); i++) {
      session(u);
      final result = (await ref.get(
        const GetOptions(source: Source.server),
      )).data()!;
      if (result['status'] == 'accepted') return result;
      if (result['status'] == 'rejected') {
        throw WorkspaceRejected(result['error'] as String? ?? 'rejected');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw const WorkspaceFailure('pending');
  }

  @override
  Future<Json> upload(
    String f,
    String u,
    List<int> bytes,
    String name, {
    bool snapshot = false,
  }) async {
    session(u);
    if (bytes.isEmpty || bytes.length > (snapshot ? 25 : 5) * 1024 * 1024) {
      throw const WorkspaceFailure('tooLarge');
    }
    final digest = sha256.convert(bytes).toString();
    final path =
        'company-workspace/$f/${snapshot ? 'snapshots' : 'files'}/$u/$digest';
    final ref = FirebaseStorage.instance.ref(path);
    try {
      final metadata = await ref.getMetadata();
      if (metadata.customMetadata?['sha256'] != digest ||
          metadata.size != bytes.length) {
        throw const WorkspaceFailure('invalidAttachment');
      }
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(
          contentType: 'application/octet-stream',
          customMetadata: {'sha256': digest},
        ),
      );
    }
    session(u);
    return {
      'path': path,
      'sha256': digest,
      'size': bytes.length,
      'name': name.substring(0, name.length.clamp(0, 160)),
    };
  }

  @override
  Future<List<int>> download(String path) async {
    final bytes = await FirebaseStorage.instance
        .ref(path)
        .getData(25 * 1024 * 1024);
    if (bytes == null ||
        sha256.convert(bytes).toString() != path.split('/').last) {
      throw const WorkspaceFailure('invalidAttachment');
    }
    return bytes;
  }
}
