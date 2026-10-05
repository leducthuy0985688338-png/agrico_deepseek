import 'dart:async';
import 'dart:convert';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import 'catalog_sync_journal.dart';
import 'catalog_sync_sender.dart';

/// Implementations read an immutable operation from the server, never a cache.
/// Null means absent at the instant of the read, not permission to discard it.
abstract interface class CatalogReceiptLookup {
  String? get authenticatedUid;
  Future<Map<String, Object?>?> lookup(CatalogSyncCommand command);
}

class CatalogReceiptRecoveryResult {
  const CatalogReceiptRecoveryResult({
    this.acknowledged = 0,
    this.absent = 0,
    this.unavailable = false,
  });
  final int acknowledged, absent;
  final bool unavailable;
}

/// Read-only on the server. Never resends, cancels, or changes an actor's command.
class CatalogReceiptRecovery {
  CatalogReceiptRecovery({
    required this.journal,
    required this.lookup,
    required this.subject,
    this.clock,
    this.maxOperations = 100,
  }) {
    if (maxOperations < 1 || maxOperations > 1000) {
      throw ArgumentError.value(maxOperations, 'maxOperations');
    }
  }
  final CatalogSyncJournal journal;
  final CatalogReceiptLookup lookup;
  final AuthorizationSubject Function() subject;
  final DateTime Function()? clock;
  final int maxOperations;
  Future<CatalogReceiptRecoveryResult>? _running;
  bool _disposed = false;
  void dispose() {
    _disposed = true;
  }

  Future<CatalogReceiptRecoveryResult> recover() {
    if (_disposed) {
      return Future.error(const CatalogFailure('catalog.syncDisposed'));
    }
    final active = _running;
    if (active != null) {
      return active;
    }
    final completer = Completer<CatalogReceiptRecoveryResult>();
    _running = completer.future;
    unawaited(_complete(completer));
    return completer.future;
  }

  Future<void> _complete(
    Completer<CatalogReceiptRecoveryResult> completer,
  ) async {
    try {
      completer.complete(await _recover());
    } catch (error, stack) {
      completer.completeError(error, stack);
    } finally {
      _running = null;
    }
  }

  void _guard(AuthorizationSubject initial, CatalogSyncCommand command) {
    final current = subject();
    if (_disposed ||
        current.userId != initial.userId ||
        current.membershipId != initial.membershipId ||
        current.farmId != initial.farmId ||
        lookup.authenticatedUid != initial.userId ||
        command.actorUid != initial.userId ||
        command.farmId != initial.farmId) {
      throw const CatalogFailure('catalog.denied');
    }
    final ownRequest =
        command.entity == 'request' && command.payload['status'] == 'pending';
    final resource = ResourceContext(
      farmId: initial.farmId,
      ownerUserId: command.entity == 'request' ? initial.userId : null,
    );
    final auth = AuthorizationService(clock: clock);
    if (!auth.can(
          subject: current,
          permission: PermissionCodes.cloudSync,
          resource: resource,
        ) ||
        !auth.can(
          subject: current,
          permission: ownRequest
              ? PermissionCodes.catalogRequest
              : PermissionCodes.catalogManage,
          resource: resource,
        )) {
      throw const CatalogFailure('catalog.denied');
    }
  }

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

  /// Verify all command fields, including the audit reason, time and base.
  static void verify(CatalogSyncCommand command, Map<String, Object?> proof) {
    final expected = <String, Object?>{
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
    final actual = {for (final key in expected.keys) key: proof[key]};
    if (jsonEncode(_canonical(expected)) != jsonEncode(_canonical(actual))) {
      throw const CatalogFailure('catalog.syncInvalid');
    }
  }

  Future<CatalogReceiptRecoveryResult> _recover() async {
    final initial = subject();
    final visited = <String>{};
    var acknowledged = 0;
    var absent = 0;
    for (var attempt = 0; attempt < maxOperations; attempt++) {
      final rows = await journal.recoverable(subject(), clock: clock);
      final candidates = rows.where(
        (row) => !visited.contains(row['operation_id']),
      );
      if (candidates.isEmpty) {
        break;
      }
      final command = CatalogSyncCommand.fromRow(candidates.first);
      _guard(initial, command);
      visited.add(command.operationId);
      Map<String, Object?>? proof;
      try {
        proof = await lookup.lookup(command);
      } on CatalogSyncUnavailable {
        _guard(initial, command);
        return CatalogReceiptRecoveryResult(
          acknowledged: acknowledged,
          absent: absent,
          unavailable: true,
        );
      }
      _guard(initial, command);
      if (proof == null) {
        absent++;
        continue;
      }
      verify(command, proof);
      await journal.acknowledgeRecovered(
        command.operationId,
        command.newVersion,
        command.payload,
        guard: () => _guard(initial, command),
      );
      acknowledged++;
    }
    return CatalogReceiptRecoveryResult(
      acknowledged: acknowledged,
      absent: absent,
    );
  }
}
