import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../domain/workspace.dart';

abstract interface class WorkspaceCommandChannel {
  Future<void> submit(String farm, String uid, String op, Json command);
  Future<Json> result(String farm, String uid, String op, Json command);
}

class FirebaseWorkspaceCommandChannel implements WorkspaceCommandChannel {
  FirebaseWorkspaceCommandChannel({WorkspaceResultClient? results})
    : results = results ?? WorkspaceResultClient();
  final WorkspaceResultClient results;

  @override
  Future<void> submit(String farm, String uid, String op, Json command) async {
    final ref = FirebaseFirestore.instance.doc(
      'agrico_workspace/$farm/users/$uid/commands/$op',
    );
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final old = await tx.get(ref);
        if (!old.exists) {
          tx.set(ref, {
            ...command,
            'createdAt': FieldValue.serverTimestamp(),
            'status': 'pending',
            'schemaVersion': 1,
          });
        } else {
          for (final k in [
            'action',
            'entityId',
            'expectedRevision',
            'payload',
          ]) {
            if (canonical(old.data()![k]) != canonical(command[k])) {
              throw const WorkspaceFailure('conflict');
            }
          }
        }
      });
    } on FirebaseException catch (e) {
      // An already accepted command is server-only. The authenticated result
      // endpoint verifies the identical command before acknowledging replay.
      // A genuine authorization failure is also checked there, never bypassed.
      if (e.code != 'permission-denied') rethrow;
    }
  }

  @override
  Future<Json> result(String farm, String uid, String op, Json command) =>
      results.read(farm, op, command);
}

class WorkspaceResultClient {
  WorkspaceResultClient({this.client, this.endpoint, this.idToken});
  final http.Client? client;
  final Uri? endpoint;
  final Future<String?> Function()? idToken;

  Future<Json> read(String farm, String operation, Json command) async {
    final token =
        await (idToken?.call() ??
            FirebaseAuth.instance.currentUser?.getIdToken() ??
            Future<String?>.value());
    if (token == null) throw const WorkspaceFailure('session');
    final endpoint =
        this.endpoint ??
        Uri.https(
          'asia-southeast1-${Firebase.app().options.projectId}.cloudfunctions.net',
          '/companyWorkspaceResult',
        );
    final client = this.client ?? http.Client();
    try {
      final response = await client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'data': {
                'farm': farm,
                'operation': operation,
                'command': command,
              },
            }),
          )
          .timeout(const Duration(seconds: 60));
      final body = jsonMap(jsonDecode(response.body));
      if (response.statusCode != 200 || body['error'] != null) {
        final error = body['error'] is Map
            ? jsonMap(body['error'])
            : <String, dynamic>{};
        final status = error['status'];
        if (status == 'PERMISSION_DENIED' || status == 'UNAUTHENTICATED') {
          throw const WorkspaceFailure('denied');
        }
        if (status == 'INVALID_ARGUMENT') {
          throw const WorkspaceFailure('conflict');
        }
        throw const WorkspaceFailure('pending');
      }
      return jsonMap(body['result']);
    } finally {
      if (this.client == null) client.close();
    }
  }
}
