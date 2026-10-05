import 'dart:async';
import 'dart:convert';

import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_journal.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'catalog_sync_workspace_test.dart' show WorkspaceRemote;

import 'package:agrico_deepseek/core/catalog/sync/catalog_conflict_decisions.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_initial_publication.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_restore_reconciliation.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_screen.dart';
import 'package:agrico_deepseek/core/catalog/sync/catalog_sync_workspace.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> unit() => {
  'id': 'kg',
  'farm_id': 'farm',
  'kind': 'unit',
  'code': 'KG',
  'name': 'Kilogram',
  'name_key': 'KILOGRAM',
  'unit_id': null,
  'active': 1,
  'revision': 1,
};

class ScreenActions implements CatalogSyncActions {
  bool manager = true, blocked = false, disposed = false;
  int sends = 0, prepares = 0, decisions = 0;
  String? reason;
  CatalogConflictChoice? choice;
  CatalogRestoreReview? restore;
  Set<String>? retained;
  int releases = 0;
  Completer<bool>? wait;
  List<CatalogConflictReview> conflicts = [];
  @override
  Future<CatalogSyncStatus> load() async => CatalogSyncStatus(
    counts: const {'pending': 1},
    restoreBlocked: blocked,
    canManage: manager,
    farmUnresolved: 0,
    conflicts: conflicts,
    unpublished: manager && !blocked
        ? [CatalogPublicationReview.fromRow(unit())]
        : [],
    labels: const {'entry/kg': 'KG · Kilogram'},
  );
  @override
  Future<bool> synchronize() async {
    sends++;
    return wait == null ? false : await wait!.future;
  }

  @override
  Future<void> prepare(CatalogPublicationReview r, String why) async {
    prepares++;
    reason = why;
  }

  @override
  Future<void> decide(
    CatalogConflictReview r,
    CatalogConflictChoice c,
    String why,
  ) async {
    decisions++;
    choice = c;
    reason = why;
  }

  @override
  Future<CatalogRestoreReview> reviewRestore() async => restore!;
  @override
  Future<void> releaseRestore(
    CatalogRestoreReview r,
    String why,
    Set<String> keep,
  ) async {
    releases++;
    retained = Set.of(keep);
    reason = why;
    blocked = false;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  Future<void> open(WidgetTester tester, ScreenActions a) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: CatalogSyncScreen(actions: a),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder target, {
    double delta = 150,
  }) async {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // Lazy child layout can change scroll extent after the first jump.
    for (var attempt = 0; attempt < 3; attempt++) {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
      await tester.pumpAndSettle();
      if (target.hitTestable().evaluate().isNotEmpty) {
        break;
      }
    }
    expect(target.hitTestable(), findsOneWidget);
  }

  testWidgets(
    'opening screen is local; one manual action while busy and disposal is owned',
    (tester) async {
      final a = ScreenActions()..wait = Completer<bool>();
      await open(tester, a);
      expect(a.sends, 0);
      await tester.tap(find.byKey(const Key('catalog-sync-run')));
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('catalog-sync-run')))
            .onPressed,
        isNull,
      );
      expect(a.sends, 1);
      a.wait!.complete(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('còn dữ liệu cần kiểm tra'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(a.disposed, isTrue);
    },
  );
  testWidgets('staff sees no publication or conflict decision controls', (
    tester,
  ) async {
    final a = ScreenActions()..manager = false;
    await open(tester, a);
    expect(find.text('Chuẩn bị gửi'), findsNothing);
    expect(find.text('Dùng bản máy chủ'), findsNothing);
    expect(find.byKey(const Key('catalog-sync-run')), findsOneWidget);
  });
  testWidgets('publication requires nonempty reason; cancel does nothing', (
    tester,
  ) async {
    final a = ScreenActions();
    await open(tester, a);
    await reveal(tester, find.text('Chuẩn bị gửi'));
    await tester.tap(find.text('Chuẩn bị gửi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-sync-confirm')));
    await tester.pumpAndSettle();
    expect(a.prepares, 0);
    expect(find.text('Nhập lý do từ 1 đến 500 ký tự.'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(a.prepares, 0);
    await reveal(tester, find.text('Chuẩn bị gửi'));
    await tester.tap(find.text('Chuẩn bị gửi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('catalog-sync-reason')),
      'Dùng chung đơn vị',
    );
    await tester.tap(find.byKey(const Key('catalog-sync-confirm')));
    await tester.pumpAndSettle();
    expect(a.prepares, 1);
    expect(a.reason, 'Dùng chung đơn vị');
  });
  testWidgets(
    'restore release requires selecting every local-only record and a reason',
    (tester) async {
      final review = await tester.runAsync(() async {
        sqfliteFfiInit();
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        try {
          await SqliteCompanyCatalog.createSchema(db);
          await db.insert(SqliteCompanyCatalog.entriesTable, unit());
          await db.insert(CatalogSyncJournal.device, {
            'farm_id': 'farm',
            'restore_blocked': 1,
          });
          final now = DateTime.utc(2026, 10, 5);
          final reviewer = CatalogRestoreReconciliation(
            database: db,
            transport: WorkspaceRemote(),
            clock: () => now,
            subject: () => AuthorizationSubject(
              userId: 'admin',
              membershipId: 'admin',
              farmId: 'farm',
              active: true,
              validUntil: now.add(const Duration(days: 7)),
              permissionCodes: {
                PermissionCodes.catalogView,
                PermissionCodes.catalogManage,
                PermissionCodes.cloudSync,
              },
              dataScopes: {DataScope.allFarm},
            ),
          );
          try {
            return await reviewer.review();
          } finally {
            reviewer.dispose();
          }
        } finally {
          await db.close();
        }
      });
      expect(review, isNotNull);
      final a = ScreenActions()
        ..blocked = true
        ..restore = review;
      await open(tester, a);
      await reveal(
        tester,
        find.byKey(const Key('catalog-sync-review-restore')),
      );
      await tester.tap(find.byKey(const Key('catalog-sync-review-restore')));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const Key('catalog-sync-release-restore')),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('catalog-sync-release-restore')),
            )
            .onPressed,
        isNull,
      );
      await reveal(tester, find.byType(CheckboxListTile), delta: -150);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const Key('catalog-sync-release-restore')),
      );
      await tester.tap(find.byKey(const Key('catalog-sync-release-restore')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('catalog-sync-reason')),
        'Giữ danh mục trên thiết bị',
      );
      await tester.tap(find.byKey(const Key('catalog-sync-confirm')));
      await tester.pumpAndSettle();
      expect(a.releases, 1);
      expect(a.retained, {'entry/kg'});
      expect(a.sends, 0);
    },
  );
  testWidgets(
    'narrow restored screen offers server choice only and has no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = ScreenActions()
        ..blocked = true
        ..conflicts = [
          CatalogConflictReview.fromRow({
            'farm_id': 'farm',
            'reader_uid': 'admin',
            'entity': 'entry',
            'target_id': 'kg',
            'cloud_version': 1,
            'operation_id': 'remote',
            'remote_json': jsonEncode(unit()),
            'local_json': jsonEncode(unit()),
          }),
        ];
      await open(tester, a);
      expect(tester.takeException(), isNull);
      expect(find.text('Giữ bản thiết bị để gửi'), findsNothing);
      await reveal(tester, find.text('Dùng bản máy chủ'));
      await tester.tap(find.text('Dùng bản máy chủ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('catalog-sync-reason')),
        'Theo dữ liệu máy chủ',
      );
      await tester.tap(find.byKey(const Key('catalog-sync-confirm')));
      await tester.pumpAndSettle();
      expect(a.choice, CatalogConflictChoice.acceptRemote);
      expect(a.decisions, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
