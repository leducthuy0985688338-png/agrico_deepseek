import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/features/company_workspace/presentation/workspace_form_dialog.dart';
import 'package:agrico_deepseek/features/company_workspace/presentation/workspace_assistant_screen.dart';
import 'package:agrico_deepseek/features/company_workspace/presentation/company_workspace_screen.dart';
import 'package:agrico_deepseek/features/company_workspace/domain/administrative_templates.dart';
import 'package:agrico_deepseek/features/company_workspace/application/workspace_service.dart';
import 'package:agrico_deepseek/features/company_workspace/data/sqlite_workspace_store.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Offline implements WorkspaceTransport {
  @override
  Future<Json> send(String f, String u, String op, Json command) async =>
      throw const WorkspaceFailure('pending');
  @override
  Future<Json> upload(
    String f,
    String u,
    List<int> b,
    String n, {
    bool snapshot = false,
  }) async => {};
  @override
  Future<List<int>> download(String path) async => [];
}

void main() {
  late Database db;
  late WorkspaceService service;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteWorkspaceStore.createSchema(db);
    final u = AuthorizationSubject(
      userId: 'u',
      membershipId: 'u',
      farmId: 'f',
      active: true,
      permissionCodes: const {
        PermissionCodes.chatView,
        PermissionCodes.cloudSync,
      },
      dataScopes: const {DataScope.allFarm},
    );
    service = WorkspaceService(
      subject: u,
      currentSubject: () => u,
      local: SqliteWorkspaceStore(db),
      transport: Offline(),
    );
  });
  tearDown(() async => db.close());
  testWidgets('read-only workspace does not offer create actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CompanyWorkspaceScreen(service: service)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Create'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('required form validation blocks empty submission', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceFormDialog(
            service: service,
            template: administrativeTemplates.first,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save draft'));
    await tester.pump();
    expect(find.text('Required'), findsWidgets);
    expect(find.textContaining('Approval does not post'), findsOneWidget);
  });
  testWidgets('assistant states read-only and has no approve pay controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceAssistantScreen(service: service)),
    );
    await tester.pump();
    expect(
      find.textContaining('Cannot send, approve or modify'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
  });
}
