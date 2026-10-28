import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/company_workspace/application/workspace_service.dart';
import 'package:agrico_deepseek/features/company_workspace/presentation/workspace_chat_screen.dart';

class MemoryStore implements WorkspaceStore {
  List<Json> rows = [];
  final values = <String, Json>{};
  @override
  Future<List<Json>> records(String f, String u) async => rows;
  @override
  Future<List<Json>> pending(String f, String u) async => [];
  @override
  Future<Json?> value(String f, String u, String key) async => values[key];
  @override
  Future<void> putValue(String f, String u, String key, Json value) async {
    values[key] = value;
  }

  @override
  Future<void> replace(
    String f,
    String u,
    List<Json> records,
    int generation,
  ) async {
    rows = records;
  }

  @override
  Future<void> clearCache(String f, String u) async {
    rows = [];
    values.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReadTransport implements WorkspaceTransport {
  bool denied = false;
  static final room = <String, dynamic>{
    'id': 'room',
    'kind': 'room',
    'farmId': 'farm',
    'revision': 1,
    'participants': ['worker'],
    'content': {'title': 'PRIVATE ROOM TITLE'},
  };
  @override
  Future<Json> send(String f, String u, String op, Json command) async {
    if (denied) throw const WorkspaceRejected('denied');
    return {
      'result': command['action'] == 'inbox.list'
          ? {
              'records': [room],
              'generation': 1,
              'token': 'inbox1',
            }
          : {
              'room': room,
              'token': 'chat1',
              'records': [
                {
                  'creatorName': 'Synthetic',
                  'createdAt': '2026-10-28',
                  'content': {'text': 'PRIVATE MESSAGE', 'files': []},
                },
              ],
            },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('revocation removes private cache and all displayed chat data', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final store = MemoryStore();
    final transport = ReadTransport();
    final subject = AuthorizationSubject(
      userId: 'worker',
      membershipId: 'worker',
      farmId: 'farm',
      active: true,
      permissionCodes: const {
        PermissionCodes.chatView,
        PermissionCodes.cloudSync,
      },
      dataScopes: const {DataScope.allFarm},
    );
    final service = WorkspaceService(
      subject: subject,
      currentSubject: () => subject,
      local: store,
      transport: transport,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceChatScreen(service: service, room: ReadTransport.room),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('PRIVATE MESSAGE'), findsOneWidget);
    expect(find.text('PRIVATE ROOM TITLE'), findsOneWidget);
    expect(store.values['chat_room'], isNotNull);
    transport.denied = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(store.values['chat_room'], isNull);
    expect(find.text('PRIVATE MESSAGE'), findsNothing);
    expect(find.text('PRIVATE ROOM TITLE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
