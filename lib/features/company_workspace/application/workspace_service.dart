import 'dart:math';

import '../../../core/permissions/authorization.dart';
import '../../../core/permissions/live_authorization.dart';
import '../domain/workspace.dart';
export '../domain/workspace.dart';

class WorkspaceService {
  WorkspaceService({
    required this.subject,
    required this.currentSubject,
    required this.local,
    required this.transport,
  });
  final AuthorizationSubject subject;
  final AuthorizationSubject? Function() currentSubject;
  final WorkspaceStore local;
  final WorkspaceTransport transport;
  Future<void>? _sync;
  bool get syncing => _sync != null;
  bool lastSyncChanged = true;

  Future<String> _session() async {
    try {
      return stamp();
    } catch (_) {
      await local.clearCache(farm, uid);
      rethrow;
    }
  }

  Future<void> _purgeIfChanged(String expected) async {
    try {
      check(expected);
    } catch (_) {
      await local.clearCache(farm, uid);
      rethrow;
    }
  }

  String newId() =>
      'w_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
  LiveAuthorization get live => LiveAuthorization(currentSubject);
  bool can(String p) {
    final m = currentSubject();
    if (m == null) return false;
    return [
      ResourceContext(farmId: m.farmId, ownerUserId: m.userId),
      for (final d in m.departmentIds)
        ResourceContext(farmId: m.farmId, departmentId: d),
      for (final t in m.teamIds) ResourceContext(farmId: m.farmId, teamId: t),
      for (final d in m.projectIds)
        ResourceContext(farmId: m.farmId, projectId: d),
    ].any((r) => live.can(subject, p, resource: r));
  }

  bool get canOpen =>
      can(PermissionCodes.chatView) && can(PermissionCodes.cloudSync);
  String stamp() {
    if (!canOpen) throw const WorkspaceFailure('denied');
    final m = currentSubject()!;
    return canonical({
      'base': live.stamp(subject),
      'team': (m.teamIds.toList()..sort()),
      'project': (m.projectIds.toList()..sort()),
      'fields': (m.assignedFieldIds.toList()..sort()),
      'tasks': (m.assignedTaskIds.toList()..sort()),
    });
  }

  void check(String expected) {
    if (stamp() != expected) throw const WorkspaceFailure('session');
    if (!canOpen) throw const WorkspaceFailure('denied');
  }

  String get farm => subject.farmId;
  String get uid => subject.userId;
  Future<Json> request(
    String action, {
    String? entity,
    int revision = 0,
    Json payload = const {},
    String? operation,
  }) async {
    final s = await _session();
    Json result;
    try {
      result = await transport.send(farm, uid, operation ?? newId(), {
        'action': action,
        'entityId': entity ?? newId(),
        'expectedRevision': revision,
        'payload': payload,
      });
      await _purgeIfChanged(s);
    } on WorkspaceFailure catch (e) {
      if (e.code == 'denied' || e.code == 'session') {
        await local.clearCache(farm, uid);
      }
      rethrow;
    } catch (_) {
      await _purgeIfChanged(s);
      rethrow;
    }
    return jsonMap(result['result']);
  }

  Future<void> queue(
    String action, {
    required String entity,
    int revision = 0,
    Json payload = const {},
  }) async {
    final s = stamp();
    await local.enqueue(farm, uid, {
      'id': newId(),
      'action': action,
      'entityId': entity,
      'expectedRevision': revision,
      'payload': payload,
    });
    check(s);
  }

  Future<void> sync() => _sync ??= _runSync().whenComplete(() => _sync = null);

  Future<void> _runSync() async {
    final s = await _session();
    try {
      final previous = await local.value(farm, uid, 'session');
      if (previous?['stamp'] != s) {
        await local.clearCache(farm, uid);
        await local.putValue(farm, uid, 'session', {'stamp': s});
      }
      for (final c in await local.pending(farm, uid)) {
        if (c['error'] != null) continue;
        check(s);
        try {
          final response = await transport.send(farm, uid, c['id'] as String, {
            for (final k in [
              'action',
              'entityId',
              'expectedRevision',
              'payload',
            ])
              k: c[k],
          });
          check(s);
          await local.accept(farm, uid, c['id'] as String, response);
        } on WorkspaceRejected catch (e) {
          check(s);
          await local.reject(farm, uid, c['id'] as String, e.code);
        }
      }
      // Only a full inbox response establishes this token; acknowledgements
      // may advance generation without containing all other users' changes.
      final snapshot = await local.value(farm, uid, 'inbox_snapshot');
      final result = await request(
        'inbox.list',
        payload: {if (snapshot?['token'] != null) 'token': snapshot!['token']},
      );
      check(s);
      lastSyncChanged = result['unchanged'] != true;
      if (!lastSyncChanged) return;
      await local.replace(
        farm,
        uid,
        (result['records'] as List).map(jsonMap).toList(),
        result['generation'] as int,
      );
      await local.putValue(farm, uid, 'inbox_snapshot', {
        if (result['token'] != null) 'token': result['token'],
      });
      await _purgeIfChanged(s);
    } catch (e) {
      if (e is WorkspaceFailure &&
          (e.code == 'denied' || e.code == 'session')) {
        await local.clearCache(farm, uid);
      }
      await _purgeIfChanged(s);
      rethrow;
    }
  }

  bool canReadRecord(Json r) {
    final m = currentSubject();
    if (m == null ||
        !canOpen ||
        r['farmId'] != farm ||
        !(r['participants'] as List).contains(uid)) {
      return false;
    }
    final content = jsonMap(r['content']);
    bool scoped(String permission, {bool own = false}) {
      if (!m.permissionCodes.contains(permission)) return false;
      final scopes = m.permissionScopes[permission] ?? m.dataScopes;
      if (scopes.contains(DataScope.allFarm)) return true;
      if (own &&
          (scopes.contains(DataScope.own) ||
              scopes.contains(DataScope.assignedTasks))) {
        return true;
      }
      final access = jsonMap(r['access'] ?? {});
      return scopes.contains(DataScope.department) &&
              (access['departmentIds'] as List? ?? []).any(
                m.departmentIds.contains,
              ) ||
          scopes.contains(DataScope.team) &&
              (access['teamIds'] as List? ?? []).any(m.teamIds.contains) ||
          scopes.contains(DataScope.project) &&
              (access['projectIds'] as List? ?? []).any(m.projectIds.contains);
    }

    if (r['kind'] == 'task') {
      return scoped(
        PermissionCodes.taskView,
        own: r['creator'] == uid || content['assignee'] == uid,
      );
    }
    if (r['kind'] == 'form' && r['creator'] != uid) {
      return scoped(jsonMap(content['template'])['permission'] as String);
    }
    if (r['kind'] == 'room' && content['source'] is Map) {
      return canReadRecord(jsonMap(content['source']));
    }
    return true;
  }

  Future<List<Json>> records() async {
    final s = await _session();
    final fingerprint = await local.value(farm, uid, 'session');
    if (fingerprint?['stamp'] != s) {
      await local.clearCache(farm, uid);
      await local.putValue(farm, uid, 'session', {'stamp': s});
    }
    final rows = await local.records(farm, uid);
    await _purgeIfChanged(s);
    return rows.where(canReadRecord).toList();
  }

  final _messageReads = <String, Future<Json>>{};
  Future<Json> messages(String roomId) => _messageReads.putIfAbsent(
    roomId,
    () => _readMessages(roomId).whenComplete(() {
      _messageReads.remove(roomId);
    }),
  );

  Future<Json> _readMessages(String roomId) async {
    final s = await _session();
    try {
      await records();
      final key = 'chat_$roomId';
      final old = await local.value(farm, uid, key);
      final result = await request(
        'message.list',
        entity: roomId,
        payload: {if (old?['token'] != null) 'token': old!['token']},
      );
      final next = result['unchanged'] == true && old != null ? old : result;
      if (result['unchanged'] != true) {
        await local.putValue(farm, uid, key, next);
      }
      await _purgeIfChanged(s);
      return next;
    } catch (_) {
      await _purgeIfChanged(s);
      rethrow;
    }
  }

  Future<List<Json>> directory() async {
    final r = await request('directory.list');
    return (r['members'] as List).map(jsonMap).toList();
  }

  Future<Json> upload(List<int> bytes, String name) async {
    final s = stamp();
    if (!can(PermissionCodes.chatSend) && !can(PermissionCodes.officeRequest)) {
      throw const WorkspaceFailure('denied');
    }
    final file = await transport.upload(farm, uid, bytes, name);
    check(s);
    return file;
  }

  Future<List<int>> file(Json record, Json file) async {
    final s = stamp();
    await request(
      'attachment.authorize',
      entity: record['id'] as String,
      payload: {'kind': record['kind'], 'path': file['path']},
    );
    final bytes = await transport.download(file['path'] as String);
    check(s);
    return bytes;
  }
}
