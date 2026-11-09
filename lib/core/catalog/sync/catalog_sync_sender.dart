import 'dart:async';
import 'dart:convert';

import '../../permissions/authorization.dart';
import '../company_catalog.dart';
import 'catalog_sync_journal.dart';

/// Immutable command. Retries must preserve its identity and complete content.
class CatalogSyncCommand {
  CatalogSyncCommand.fromRow(Map<String, Object?> row)
    : operationId = row['operation_id'] as String,
      farmId = row['farm_id'] as String,
      actorUid = row['actor_uid'] as String,
      entity = row['entity'] as String,
      targetId = row['target_id'] as String,
      baseVersion = row['base_version'] as int,
      newVersion = row['new_version'] as int,
      payloadJson = row['payload_json'] as String,
      reason = row['reason'] as String,
      occurredAt = row['occurred_at'] as String;

  final String operationId, farmId, actorUid, entity, targetId;
  final String payloadJson, reason, occurredAt;
  final int baseVersion, newVersion;

  /// A fresh copy prevents a transport from mutating the stored command.
  Map<String, Object?> get payload =>
      (jsonDecode(payloadJson) as Map).cast<String, Object?>();
}

class CatalogSyncReceipt {
  const CatalogSyncReceipt({
    required this.operationId,
    required this.farmId,
    required this.actorUid,
    required this.entity,
    required this.targetId,
    required this.cloudVersion,
    required this.payload,
  });
  final String operationId, farmId, actorUid, entity, targetId;
  final int cloudVersion;
  final Map<String, Object?> payload;
}

/// Only explicit, definitive rejections may change durable queue state.
class CatalogSyncRejected implements Exception {
  const CatalogSyncRejected(this.code, {required this.conflict});
  final String code;
  final bool conflict;
}

/// A transport reports this for retryable network errors. It must not substitute
/// cached snapshots for authoritative server receipts.
class CatalogSyncUnavailable implements Exception {
  const CatalogSyncUnavailable();
}

abstract interface class CatalogSyncTransport {
  Future<String?> currentUserId();

  /// Atomically compare baseVersion, apply the payload and create an immutable
  /// receipt. If operationId already exists, verify the entire command and
  /// return that receipt, even if the entity has since advanced.
  ///
  /// Implementations must enforce current server authorization, uniqueness,
  /// unit references and audit rules. They must not queue unaudited writes in
  /// a platform SDK offline cache.
  Future<CatalogSyncReceipt> send(CatalogSyncCommand command);
}

class CatalogSyncSendResult {
  const CatalogSyncSendResult({
    this.acknowledged = 0,
    this.conflicts = 0,
    this.blocked = 0,
    this.unavailable = false,
    this.sessionChanged = false,
  });
  final int acknowledged, conflicts, blocked;
  final bool unavailable, sessionChanged;
}

/// One coordinator per open database/session. It serializes overlapping calls,
/// checks the current actor before each send and preserves pending commands on
/// uncertain outcomes. This class is not yet wired into application routes.
class CatalogSyncSender {
  CatalogSyncSender({
    required this.journal,
    required this.transport,
    required this.subject,
    this.clock,
    this.maxOperations = 100,
  }) {
    if (maxOperations < 1 || maxOperations > 1000) {
      throw ArgumentError.value(maxOperations, 'maxOperations');
    }
  }

  final CatalogSyncJournal journal;
  final CatalogSyncTransport transport;
  final AuthorizationSubject Function() subject;
  final DateTime Function()? clock;
  final int maxOperations;
  Future<CatalogSyncSendResult>? _running;
  bool _disposed = false;

  /// Prevent new sends after logout/disposal. An already committed command
  /// remains pending if disposal occurs while its receipt is in flight.
  void dispose() {
    _disposed = true;
  }

  Future<CatalogSyncSendResult> synchronize() {
    if (_disposed) {
      return Future.error(const CatalogFailure('catalog.syncDisposed'));
    }
    final active = _running;
    if (active != null) {
      return active;
    }
    final completer = Completer<CatalogSyncSendResult>();
    _running = completer.future;
    unawaited(_complete(completer));
    return completer.future;
  }

  Future<void> _complete(Completer<CatalogSyncSendResult> completer) async {
    try {
      completer.complete(await _send());
    } catch (error, stack) {
      completer.completeError(error, stack);
    } finally {
      _running = null;
    }
  }

  bool _sameSession(
    AuthorizationSubject current,
    AuthorizationSubject initial,
  ) =>
      !_disposed &&
      current.userId == initial.userId &&
      current.membershipId == initial.membershipId &&
      current.farmId == initial.farmId;

  Future<CatalogSyncSendResult> _send() async {
    final initial = subject();
    var acknowledged = 0;
    var conflicts = 0;
    var blocked = 0;
    var unavailable = false;
    var sessionChanged = false;
    for (var attempt = 0; attempt < maxOperations; attempt++) {
      final current = subject();
      if (!_sameSession(current, initial)) {
        sessionChanged = true;
        break;
      }
      // Re-evaluate lease and permission changes, including explicit denials.
      final rows = await journal.pending(current, clock: clock);
      if (rows.isEmpty) {
        break;
      }
      final command = CatalogSyncCommand.fromRow(rows.first);
      try {
        if (await transport.currentUserId() != initial.userId ||
            !_sameSession(subject(), initial)) {
          sessionChanged = true;
          break;
        }
        final receipt = await transport.send(command);
        if (await transport.currentUserId() != initial.userId ||
            !_sameSession(subject(), initial)) {
          sessionChanged = true;
          break;
        }
        if (receipt.operationId != command.operationId ||
            receipt.farmId != command.farmId ||
            receipt.actorUid != command.actorUid ||
            receipt.entity != command.entity ||
            receipt.targetId != command.targetId) {
          throw const CatalogFailure('catalog.syncInvalid');
        }
        // Journal verifies payload, version and expected shadow atomically.
        await journal.acknowledge(
          command.operationId,
          receipt.cloudVersion,
          receipt.payload,
        );
        acknowledged++;
      } on CatalogSyncRejected catch (error) {
        // A server rejection must never be attributed to a different session.
        if (!_sameSession(subject(), initial) ||
            await transport.currentUserId() != initial.userId) {
          sessionChanged = true;
          break;
        }
        await journal.fail(
          command.operationId,
          conflict: error.conflict,
          code: error.code,
        );
        if (error.conflict) {
          conflicts++;
        } else {
          blocked++;
        }
      } on CatalogSyncUnavailable {
        unavailable = true;
        break;
      }
    }
    return CatalogSyncSendResult(
      acknowledged: acknowledged,
      conflicts: conflicts,
      blocked: blocked,
      unavailable: unavailable,
      sessionChanged: sessionChanged,
    );
  }
}
