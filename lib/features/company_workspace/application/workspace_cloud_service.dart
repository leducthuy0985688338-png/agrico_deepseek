import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/backup/local_media_snapshot.dart';
import '../../../core/backup/local_restore_activation.dart';
import '../../../core/backup/local_restore_preflight.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/production_cost_database.dart';
import '../data/sqlite_workspace_store.dart';
import 'workspace_service.dart';

class CloudPreview {
  const CloudPreview(this.head, this.bytes, this.localHash, this.counts);
  final Json head;
  final Uint8List bytes;
  final String localHash;
  final Map<String, int> counts;
}

class WorkspaceCloudService {
  WorkspaceCloudService(this.workspace, this.database);
  final WorkspaceService workspace;
  final Database database;
  static const marker = 'agrico-company-workspace-restore-v1';
  static const privatePermissions = [
    'cloud.restore',
    'local_backup.export',
    'employee.sensitive.view',
    'payroll.view',
    'finance.view',
  ];
  bool get canUse {
    final m = workspace.currentSubject();
    return workspace.canOpen &&
        m != null &&
        privatePermissions.every(
          (p) =>
              workspace.can(p) &&
              (m.permissionScopes[p] ?? m.dataScopes).contains(
                DataScope.allFarm,
              ),
        );
  }

  void require() {
    if (!canUse) throw const WorkspaceFailure('denied');
  }

  Future<Uint8List> bytes() async {
    require();
    final result = await LocalMediaSnapshot.create(
      database,
      await ProductionCostDatabase().database,
    );
    require();
    return result;
  }

  Future<Json?> head() async {
    require();
    final r = await workspace.request('snapshot.head');
    return r['head'] == null ? null : jsonMap(r['head']);
  }

  Future<Json> publish({int? resolvedRevision, String? reason}) async {
    final stamp = workspace.stamp();
    require();
    final current = await head();
    final data = await bytes();
    final digest = sha256.convert(data).toString();
    final baseline = await workspace.local.value(
      workspace.farm,
      workspace.uid,
      'snapshot_baseline',
    );
    if (current != null && current['sha256'] == digest) {
      await workspace.local.putValue(
        workspace.farm,
        workspace.uid,
        'snapshot_baseline',
        current,
      );
      return current;
    }
    if (current != null &&
        baseline?['revision'] != current['revision'] &&
        resolvedRevision != current['revision']) {
      throw const WorkspaceFailure('conflict');
    }
    if (resolvedRevision != null &&
        (resolvedRevision != current?['revision'] ||
            (reason ?? '').trim().isEmpty)) {
      throw const WorkspaceFailure('conflict');
    }
    final file = await workspace.transport.upload(
      workspace.farm,
      workspace.uid,
      data,
      'snapshot',
      snapshot: true,
    );
    workspace.check(stamp);
    require();
    final result = await workspace.request(
      'snapshot.publish',
      revision: current?['revision'] as int? ?? 0,
      payload: {...file, 'reason': reason ?? 'Publish current device snapshot'},
    );
    workspace.check(stamp);
    final next = jsonMap(result['head']);
    await workspace.local.putValue(
      workspace.farm,
      workspace.uid,
      'snapshot_baseline',
      next,
    );
    return next;
  }

  Future<CloudPreview> preview() async {
    final stamp = workspace.stamp();
    require();
    final latest = await head();
    if (latest == null) throw const WorkspaceFailure('empty');
    final local = await bytes();
    final data = Uint8List.fromList(
      await workspace.transport.download(latest['path'] as String),
    );
    workspace.check(stamp);
    require();
    if (sha256.convert(data).toString() != latest['sha256']) {
      throw const WorkspaceFailure('invalidSnapshot');
    }
    LocalMediaSnapshot.validate(data);
    final counts = await LocalRestorePreflight.validate(
      bytes: data,
      primary: database,
      costs: await ProductionCostDatabase().database,
      factory: databaseFactory,
      temporaryDirectory: (await getTemporaryDirectory()).path,
    );
    workspace.check(stamp);
    return CloudPreview(latest, data, sha256.convert(local).toString(), counts);
  }

  Future<void> schedule(CloudPreview preview) async {
    final stamp = workspace.stamp();
    require();
    final latest = await head();
    if (latest?['revision'] != preview.head['revision'] ||
        sha256.convert(await bytes()).toString() != preview.localHash) {
      throw const WorkspaceFailure('conflict');
    }
    workspace.check(stamp);
    require();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      marker,
      jsonEncode({
        'uid': workspace.uid,
        'farm': workspace.farm,
        'head': preview.head,
      }),
    );
    try {
      await scheduleLocalRestore(preview.bytes);
    } catch (_) {
      await prefs.remove(marker);
      rethrow;
    }
    workspace.check(stamp);
  }

  static Future<void> recover(Database db, AuthorizationSubject subject) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(marker);
    if (raw == null) return;
    final saved = jsonMap(jsonDecode(raw));
    if (saved['uid'] != subject.userId || saved['farm'] != subject.farmId) {
      return;
    }
    final head = jsonMap(saved['head']);
    final bytes = await LocalMediaSnapshot.create(
      db,
      await ProductionCostDatabase().database,
    );
    if (sha256.convert(bytes).toString() == head['sha256']) {
      await SqliteWorkspaceStore(
        db,
      ).putValue(subject.farmId, subject.userId, 'snapshot_baseline', head);
      await prefs.remove(marker);
    }
  }
}
