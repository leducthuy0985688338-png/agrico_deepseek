import 'dart:convert';

import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_sender.dart';
import 'package:agrico_deepseek/core/catalog/sync/firebase_catalog_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CatalogSyncCommand command() => CatalogSyncCommand.fromRow({
    'operation_id': 'operation',
    'farm_id': 'local-farm',
    'actor_uid': 'admin',
    'entity': 'entry',
    'target_id': 'unit',
    'base_version': 0,
    'new_version': 1,
    'payload_json': jsonEncode({
      'id': 'unit',
      'farm_id': 'local-farm',
      'name': 'Kilogram',
    }),
    'reason': 'Initial publication',
    'occurred_at': '2026-10-03T00:00:00.000Z',
  });

  test('UTF-8 hash keys distinguish slash and percent literals', () {
    expect(
      FirebaseCatalogSyncTransport.keyId('unit', 'name', 'A/B'),
      'unit~name~998D3ED8983ACF3905221679BD780342CE694857C471C46B261A27F62227BF6D',
    );
    expect(
      FirebaseCatalogSyncTransport.keyId('unit', 'name', 'A%2FB'),
      'unit~name~DF4AB3685965E15FD5994047E46E541933E3636F166DF776159F37C6325884C0',
    );
    expect(
      FirebaseCatalogSyncTransport.keyId('unit', 'name', 'LẠC'),
      'unit~name~74858BBD0CFACCC4736E09DEF4B0ED86090296F736E00F37E2417776B265C542',
    );
  });

  test('receipt verifies full immutable command independent of map order', () {
    final c = command();
    final data = Map<String, dynamic>.from(
      FirebaseCatalogSyncTransport.commandData(c),
    );
    data['payload'] = {
      'name': 'Kilogram',
      'farm_id': 'local-farm',
      'id': 'unit',
    };
    final accepted = FirebaseCatalogSyncTransport.receipt(c, data);
    expect(accepted.cloudVersion, 1);
    expect(accepted.operationId, 'operation');
  });

  test('reused operation ID with another audit reason is rejected', () {
    final c = command();
    final data = Map<String, dynamic>.from(
      FirebaseCatalogSyncTransport.commandData(c),
    );
    data['reason'] = 'Different request';
    expect(
      () => FirebaseCatalogSyncTransport.receipt(c, data),
      throwsA(isA<CatalogSyncRejected>()),
    );
  });

  test('reused operation ID with different base or actor is rejected', () {
    final c = command();
    for (final change in [
      {'baseVersion': 8},
      {'actorUid': 'other'},
      {'farmId': 'other-farm'},
    ]) {
      final data = <String, dynamic>{
        ...FirebaseCatalogSyncTransport.commandData(c),
        ...change,
      };
      expect(
        () => FirebaseCatalogSyncTransport.receipt(c, data),
        throwsA(isA<CatalogSyncRejected>()),
      );
    }
  });

  test('receipt cannot substitute payload or target', () {
    final c = command();
    for (final change in [
      {'targetId': 'other'},
      {
        'payload': {'id': 'other'},
      },
    ]) {
      final data = <String, dynamic>{
        ...FirebaseCatalogSyncTransport.commandData(c),
        ...change,
      };
      expect(
        () => FirebaseCatalogSyncTransport.receipt(c, data),
        throwsA(isA<CatalogSyncRejected>()),
      );
    }
  });

  test('transport payload copy cannot mutate later retries', () {
    final c = command();
    final first = FirebaseCatalogSyncTransport.commandData(c);
    (first['payload'] as Map)['name'] = 'Altered';
    expect(
      (FirebaseCatalogSyncTransport.commandData(c)['payload'] as Map)['name'],
      'Kilogram',
    );
  });
}
