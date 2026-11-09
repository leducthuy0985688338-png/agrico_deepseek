import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import '../sqlite_company_catalog.dart';
import 'catalog_sync_journal.dart';
import 'catalog_sync_sender.dart';

/// Validated, immutable server envelope. Receiving never acknowledges a send.
class CatalogRemoteRecord {
  CatalogRemoteRecord({
    required this.farmId,
    required this.entity,
    required this.targetId,
    required this.version,
    required this.operationId,
    required Map<String, Object?> payload,
  }) : payloadJson = jsonEncode(payload) {
    validate();
  }
  final String farmId, entity, targetId, operationId, payloadJson;
  final int version;
  Map<String, Object?> get payload =>
      (jsonDecode(payloadJson) as Map).cast<String, Object?>();
  static bool validId(Object? v) =>
      v is String &&
      v.isNotEmpty &&
      utf8.encode(v).length <= 500 &&
      !v.contains('/') &&
      v != '.' &&
      v != '..';
  static int compareIds(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    for (var i = 0; i < x.length && i < y.length; i++) {
      if (x[i] != y[i]) {
        return x[i].compareTo(y[i]);
      }
    }
    return x.length.compareTo(y.length);
  }

  Never _invalid() => throw const CatalogFailure('catalog.syncInvalid');
  void validate() {
    final p = payload;
    if (!validId(farmId) ||
        !validId(targetId) ||
        !validId(operationId) ||
        version < 1 ||
        !{'entry', 'request'}.contains(entity) ||
        p['id'] != targetId ||
        p['farm_id'] != farmId) {
      _invalid();
    }
    if (entity == 'entry') {
      const keys = {
        'id',
        'farm_id',
        'kind',
        'code',
        'name',
        'name_key',
        'unit_id',
        'active',
        'revision',
      };
      if (p.length != keys.length ||
          !p.keys.toSet().containsAll(keys) ||
          p['kind'] is! String ||
          p['code'] is! String ||
          p['name'] is! String ||
          p['revision'] is! int ||
          (p['revision'] as int) < 1 ||
          p['active'] is! int ||
          !{0, 1}.contains(p['active']) ||
          (p['unit_id'] != null && !validId(p['unit_id'])) ||
          p['name_key'] != SqliteCompanyCatalog.nameKey(p['name'] as String)) {
        _invalid();
      }
      if (!CatalogKind.values.any((k) => k.name == p['kind'])) {
        _invalid();
      }
      CatalogEntry(
        id: targetId,
        farmId: farmId,
        kind: CatalogKind.values.byName(p['kind'] as String),
        code: p['code'] as String,
        name: p['name'] as String,
        unitId: p['unit_id'] as String?,
        active: p['active'] == 1,
        revision: p['revision'] as int,
      ).validate();
    } else {
      const required = {
        'id',
        'farm_id',
        'actor_uid',
        'kind',
        'code',
        'name',
        'reason',
        'created_at',
        'status',
      };
      const optional = {'entry_id', 'resolved_by', 'resolved_at', 'resolution'};
      bool text(Object? v, int max) =>
          v is String && v.trim().isNotEmpty && v.length <= max;
      bool date(Object? v) =>
          v is String &&
          RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,6}Z$',
          ).hasMatch(v) &&
          DateTime.tryParse(v)?.toUtc().toIso8601String() == v;
      if (!p.keys.toSet().containsAll(required) ||
          p.keys.any((k) => !required.contains(k) && !optional.contains(k)) ||
          !validId(p['actor_uid']) ||
          !CatalogKind.values.any((k) => k.name == p['kind']) ||
          p['code'] is! String ||
          !RegExp(
            r'^[A-Z0-9][A-Z0-9_-]{0,39}$',
          ).hasMatch(p['code'] as String) ||
          !text(p['name'], 100) ||
          p['name'] != (p['name'] as String).trim() ||
          !text(p['reason'], 500) ||
          !date(p['created_at']) ||
          !{'pending', 'approved', 'rejected'}.contains(p['status'])) {
        _invalid();
      }
      if (p['status'] == 'pending') {
        if (optional.any((k) => p[k] != null)) {
          _invalid();
        }
      } else if (!validId(p['resolved_by']) ||
          !date(p['resolved_at']) ||
          !text(p['resolution'], 500) ||
          (p['status'] == 'approved'
              ? (!validId(p['entry_id']) || p['actor_uid'] == p['resolved_by'])
              : p['entry_id'] != null)) {
        _invalid();
      }
    }
  }
}

class CatalogRemotePage {
  CatalogRemotePage({
    required List<CatalogRemoteRecord> records,
    this.nextCursor,
  }) : records = List.unmodifiable(records);
  final List<CatalogRemoteRecord> records;
  final String? nextCursor;
}

abstract interface class CatalogReceiveTransport {
  Future<String?> currentUserId();

  /// Server-only reads. Cursor is a document ID, never a cache checkpoint.
  Future<CatalogRemotePage> fetch({
    required String farmId,
    required String actorUid,
    required String entity,
    required bool allRequests,
    required int limit,
    String? cursor,
  });
}

/// Device-only staging. No business overwrite, cloud baseline advance, or lease
/// renewal is implied by receiving a page. Projection/reconciliation is separate.
class CatalogSyncInbox {
  const CatalogSyncInbox(this.database);
  final Database database;
  static const table = CatalogSyncJournal.inbox;
  static Future<void> createSchema(DatabaseExecutor tx) =>
      CatalogSyncJournal.createSchema(tx);
  static Object? canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) {
      return v.map(canonical).toList();
    }
    return v;
  }

  Future<void> stage(
    List<CatalogRemoteRecord> records, {
    required String farmId,
    required String readerUid,
    required bool allRequests,
    required void Function() authorize,
  }) => database.transaction((tx) async {
    authorize();
    if (records.length > 200 ||
        !CatalogRemoteRecord.validId(farmId) ||
        !CatalogRemoteRecord.validId(readerUid)) {
      throw const CatalogFailure('catalog.syncInvalid');
    }
    await createSchema(tx);
    for (final r in records) {
      r.validate();
      if (r.farmId != farmId ||
          (r.entity == 'request' &&
              !allRequests &&
              r.payload['actor_uid'] != readerUid)) {
        throw const CatalogFailure('catalog.denied');
      }
      final args = [farmId, readerUid, r.entity, r.targetId];
      final old = await tx.query(
        table,
        where: 'farm_id=? AND reader_uid=? AND entity=? AND target_id=?',
        whereArgs: args,
      );
      if (old.isNotEmpty) {
        final prior = old.single;
        final v = prior['cloud_version'] as int;
        if (v > r.version) {
          continue;
        }
        if (v == r.version) {
          if (prior['operation_id'] != r.operationId ||
              jsonEncode(
                    canonical(jsonDecode(prior['payload_json'] as String)),
                  ) !=
                  jsonEncode(canonical(r.payload))) {
            throw const CatalogFailure('catalog.changed');
          }
          continue;
        }
      }
      await tx.insert(table, {
        'farm_id': farmId,
        'reader_uid': readerUid,
        'entity': r.entity,
        'target_id': r.targetId,
        'cloud_version': r.version,
        'operation_id': r.operationId,
        'payload_json': r.payloadJson,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    authorize();
  });

  /// Recompute dirty barriers at read time, including another actor's edits.
  Future<List<Map<String, Object?>>> staged(
    String farmId,
    String readerUid,
  ) async => database.rawQuery(
    '''SELECT i.*, EXISTS(SELECT 1 FROM ${CatalogSyncJournal.outbox} q
        WHERE q.farm_id=i.farm_id AND q.entity=i.entity AND q.target_id=i.target_id
        AND q.state<>'acked') AS locally_dirty FROM $table i
        WHERE i.farm_id=? AND i.reader_uid=? ORDER BY i.entity,i.target_id''',
    [farmId, readerUid],
  );
}

class CatalogReceiveResult {
  const CatalogReceiveResult(
    this.pages,
    this.records, {
    required this.complete,
  });
  final int pages, records;
  final bool complete;
}

class CatalogSyncReceiver {
  CatalogSyncReceiver({
    required this.inbox,
    required this.transport,
    required this.currentSubject,
    this.clock,
  });
  final CatalogSyncInbox inbox;
  final CatalogReceiveTransport transport;
  final AuthorizationSubject? Function() currentSubject;
  final DateTime Function()? clock;
  bool _disposed = false;
  Future<CatalogReceiveResult>? _running;
  void dispose() {
    _disposed = true;
  }

  bool _can(AuthorizationSubject s, String permission, {bool own = false}) =>
      AuthorizationService(clock: clock).can(
        subject: s,
        permission: permission,
        resource: ResourceContext(
          farmId: s.farmId,
          ownerUserId: own ? s.userId : null,
        ),
      );
  void _check(
    AuthorizationSubject original, {
    required String entity,
    required bool allRequests,
  }) {
    final s = currentSubject();
    if (_disposed ||
        s == null ||
        s.userId != original.userId ||
        s.farmId != original.farmId ||
        !_can(s, PermissionCodes.cloudSync, own: true) ||
        (entity == 'entry'
            ? !_can(s, PermissionCodes.catalogView)
            : allRequests
            ? !_can(s, PermissionCodes.catalogManage)
            : !_can(s, PermissionCodes.catalogRequest, own: true))) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  Future<CatalogReceiveResult> receive({
    int pageSize = 100,
    int maxPages = 20,
  }) {
    if (pageSize < 1 || pageSize > 200 || maxPages < 1 || maxPages > 1000) {
      throw ArgumentError('Invalid receive budget');
    }
    return _running ??= _run(pageSize, maxPages).whenComplete(() {
      _running = null;
    });
  }

  Future<CatalogReceiveResult> _run(int size, int budget) async {
    final s = currentSubject();
    if (s == null) {
      throw const CatalogFailure('catalog.denied');
    }
    var pages = 0, records = 0;
    for (final entity in ['entry', 'request']) {
      final all = entity == 'request' && _can(s, PermissionCodes.catalogManage);
      if (entity == 'request' &&
          !all &&
          !_can(s, PermissionCodes.catalogRequest, own: true)) {
        continue;
      }
      String? cursor;
      while (true) {
        if (pages >= budget) {
          return CatalogReceiveResult(pages, records, complete: false);
        }
        _check(s, entity: entity, allRequests: all);
        if (await transport.currentUserId() != s.userId) {
          throw const CatalogSyncUnavailable();
        }
        final page = await transport.fetch(
          farmId: s.farmId,
          actorUid: s.userId,
          entity: entity,
          allRequests: all,
          limit: size,
          cursor: cursor,
        );
        _check(s, entity: entity, allRequests: all);
        if (await transport.currentUserId() != s.userId) {
          throw const CatalogSyncUnavailable();
        }
        if (page.records.length > size ||
            (page.nextCursor != null &&
                (page.records.isEmpty ||
                    page.nextCursor != page.records.last.targetId))) {
          throw const CatalogFailure('catalog.syncInvalid');
        }
        var last = cursor;
        for (final r in page.records) {
          if (r.entity != entity ||
              (last != null &&
                  CatalogRemoteRecord.compareIds(r.targetId, last) <= 0)) {
            throw const CatalogFailure('catalog.syncInvalid');
          }
          last = r.targetId;
        }
        await inbox.stage(
          page.records,
          farmId: s.farmId,
          readerUid: s.userId,
          allRequests: all,
          authorize: () => _check(s, entity: entity, allRequests: all),
        );
        pages++;
        records += page.records.length;
        if (page.nextCursor == null) {
          break;
        }
        cursor = page.nextCursor;
      }
    }
    return CatalogReceiveResult(pages, records, complete: true);
  }
}
