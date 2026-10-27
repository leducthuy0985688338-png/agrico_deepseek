import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:agrico_deepseek/features/company_workspace/data/sqlite_workspace_store.dart';
import 'package:agrico_deepseek/features/company_workspace/application/workspace_service.dart';
import 'package:agrico_deepseek/features/company_workspace/application/workspace_document_export.dart';
import 'package:agrico_deepseek/features/company_workspace/domain/administrative_templates.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';

class Transport implements WorkspaceTransport {
  final calls = <Json>[];
  bool timeout = false;
  void Function()? onSend;
  @override
  Future<Json> send(String f, String u, String op, Json c) async {
    calls.add({'op': op, ...c});
    onSend?.call();
    if (timeout) throw const WorkspaceFailure('pending');
    return {
      'result': c['action'] == 'inbox.list'
          ? {'records': <Json>[], 'generation': 10}
          : <String, dynamic>{},
      'inboxGeneration': 10,
    };
  }

  @override
  Future<Json> upload(
    String f,
    String u,
    List<int> b,
    String n, {
    bool snapshot = false,
  }) async => {};
  @override
  Future<List<int>> download(String p) async => [];
}

void main() {
  late Database db;
  late SqliteWorkspaceStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteWorkspaceStore.createSchema(db);
    store = SqliteWorkspaceStore(db);
  });
  tearDown(() async => db.close());
  Json command(
    String id, {
    String entity = 'task',
    String action = 'task.accept',
  }) => {
    'id': id,
    'action': action,
    'entityId': entity,
    'expectedRevision': 1,
    'payload': <String, dynamic>{},
  };
  Json record(String id, int revision) => {
    'id': id,
    'kind': 'task',
    'revision': revision,
    'content': <String, dynamic>{},
  };
  test(
    'exact command replay is stable and modified replay is rejected',
    () async {
      final c = command('one');
      await store.enqueue('f', 'u', c);
      await store.enqueue('f', 'u', c);
      expect(await store.pending('f', 'u'), hasLength(1));
      await expectLater(
        store.enqueue('f', 'u', {...c, 'expectedRevision': 2}),
        throwsA(isA<WorkspaceFailure>()),
      );
    },
  );
  test(
    'one uncertain operation per entity and cannot discard pending',
    () async {
      await store.enqueue('f', 'u', command('one'));
      await expectLater(
        store.enqueue('f', 'u', command('two')),
        throwsA(isA<WorkspaceFailure>()),
      );
      await store.discard('f', 'u', 'one');
      expect(await store.pending('f', 'u'), hasLength(1));
    },
  );
  test('farm and uid partitions cannot cross', () async {
    await store.enqueue('f', 'u', command('one'));
    expect(await store.pending('else', 'u'), isEmpty);
    expect(await store.pending('f', 'other'), isEmpty);
  });
  test(
    'rejected operations retain original content for review and can be discarded',
    () async {
      await store.enqueue('f', 'u', command('one'));
      await store.reject('f', 'u', 'one', 'denied');
      expect((await store.pending('f', 'u')).single['error'], 'denied');
      await store.discard('f', 'u', 'one');
      expect(await store.pending('f', 'u'), isEmpty);
    },
  );
  test('ack updates cache and removes outbox atomically', () async {
    await store.enqueue('f', 'u', command('one'));
    await store.accept('f', 'u', 'one', {
      'result': {'record': record('task', 2)},
      'inboxGeneration': 5,
    });
    expect(await store.pending('f', 'u'), isEmpty);
    expect((await store.records('f', 'u')).single['revision'], 2);
  });
  test('late full inbox cannot overwrite a newer acknowledgement', () async {
    await store.accept('f', 'u', 'one', {
      'result': {'record': record('task', 2)},
      'inboxGeneration': 5,
    });
    await store.replace('f', 'u', [], 4);
    expect(await store.records('f', 'u'), hasLength(1));
    await store.replace('f', 'u', [], 6);
    expect(await store.records('f', 'u'), isEmpty);
  });
  test('private cache purge preserves uncertain outbox', () async {
    await store.enqueue('f', 'u', command('one'));
    await store.putValue('f', 'u', 'directory', {'name': 'Private'});
    await store.putValue('f', 'u', 'snapshot_baseline', {'revision': 3});
    await store.replace('f', 'u', [record('task', 1)], 1);
    await store.clearCache('f', 'u');
    expect(await store.records('f', 'u'), isEmpty);
    expect(await store.value('f', 'u', 'directory'), isNull);
    expect((await store.value('f', 'u', 'snapshot_baseline'))?['revision'], 3);
    expect(await store.pending('f', 'u'), hasLength(1));
  });
  test('device cache and send authority excluded from backup', () async {
    await store.enqueue('f', 'u', command('one'));
    final snapshot = jsonMap(
      jsonDecode(utf8.decode(await LocalDatabaseSnapshot.create(db))),
    );
    expect(
      snapshot['payload'].toString(),
      isNot(contains('company_workspace_')),
    );
  });
  test('22 built-in templates preserve three languages and typed fields', () {
    expect(administrativeTemplates, hasLength(22));
    for (final t in administrativeTemplates) {
      expect(t['names'], hasLength(3));
      for (final f in t['fields'] as List) {
        expect(f['label'], hasLength(3));
      }
    }
  });
  test('Word is valid OOXML and escapes Unicode content without injection', () {
    final t = administrativeTemplates.first;
    final bytes = WorkspaceDocumentExport.create({
      'code': 'TU-202610-001',
      'creatorName': 'Nguyễn & ລາວ',
      'createdAt': '2026-10-27',
      'state': 'draft',
      'content': {
        'template': t,
        'fields': {
          'amount': '100',
          'currency': 'LAK',
          'reason': '<script> & nội dung',
        },
      },
    }, 0);
    final files = ZipDecoder().decodeBytes(bytes);
    final doc = files.files.firstWhere((f) => f.name == 'word/document.xml');
    final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
    expect(xml.innerText, contains('Nguyễn & ລາວ'));
    expect(xml.findAllElements('script'), isEmpty);
    expect(xml.innerText, contains('<script> & nội dung'));
  });
  test(
    'settlement computes exact proposed return or additional amounts per currency',
    () {
      final returned = AdvanceSettlementBalance('1000.1', '600.03', 'LAK');
      expect(returned.amount, '400.07');
      expect(returned.returnRequired, isTrue);
      final extra = AdvanceSettlementBalance('0.1', '0.3', 'VND');
      expect(extra.amount, '0.2');
      expect(extra.additionalRequired, isTrue);
      expect(
        () => AdvanceSettlementBalance('1', '0', 'USD'),
        throwsA(isA<WorkspaceFailure>()),
      );
    },
  );
  AuthorizationSubject subject(String uid) => AuthorizationSubject(
    userId: uid,
    membershipId: uid,
    farmId: 'f',
    active: true,
    permissionCodes: const {
      PermissionCodes.chatView,
      PermissionCodes.cloudSync,
      PermissionCodes.chatSend,
    },
    dataScopes: const {DataScope.allFarm},
  );
  test('network timeout keeps same operation id for reconnect', () async {
    final t = Transport()..timeout = true;
    final u = subject('u');
    final service = WorkspaceService(
      subject: u,
      currentSubject: () => u,
      local: store,
      transport: t,
    );
    await service.queue('task.accept', entity: 'task', revision: 1);
    await expectLater(service.sync(), throwsA(isA<WorkspaceFailure>()));
    final id = (await store.pending('f', 'u')).single['id'];
    t.timeout = false;
    await service.sync();
    expect(
      t.calls
          .where((c) => c['action'] == 'task.accept')
          .map((c) => c['op'])
          .toSet(),
      {id},
    );
    expect(await store.pending('f', 'u'), isEmpty);
  });
  test(
    'logout during send cannot acknowledge or transfer pending operation',
    () async {
      final t = Transport();
      final u = subject('u');
      AuthorizationSubject? live = u;
      final service = WorkspaceService(
        subject: u,
        currentSubject: () => live,
        local: store,
        transport: t,
      );
      await service.queue('task.accept', entity: 'task', revision: 1);
      t.onSend = () => live = null;
      await expectLater(service.sync(), throwsA(anything));
      expect(await store.pending('f', 'u'), hasLength(1));
      expect(await store.pending('f', 'other'), isEmpty);
    },
  );
}
