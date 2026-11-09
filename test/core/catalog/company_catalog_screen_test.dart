import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/company_catalog_screen.dart';
import 'package:agrico_deepseek/core/catalog/catalog_value_picker.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements CompanyCatalogRepository {
  final values = <CatalogEntry>[];
  final suggestions = <CatalogRequest>[];
  @override
  Future<List<CatalogEntry>> entries(String farmId) async =>
      values.where((e) => e.farmId == farmId).toList();
  @override
  Future<void> save(
    CatalogEntry entry, {
    required int? expectedRevision,
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    required void Function() authorize,
  }) async {
    authorize();
    final next =
        values
            .where(
              (value) =>
                  value.farmId == entry.farmId && value.kind == entry.kind,
            )
            .length +
        1;
    final prefix = switch (entry.kind) {
      CatalogKind.unit => 'DVT',
      CatalogKind.crop => 'CT',
      CatalogKind.machine => 'MAY',
      CatalogKind.worker => 'NS',
      CatalogKind.material => 'VT',
      CatalogKind.taskType => 'CV',
      CatalogKind.supplier => 'NCC',
      CatalogKind.incomeCategory => 'DMTHU',
      CatalogKind.expenseCategory => 'DMCHI',
      CatalogKind.product => 'TP',
      CatalogKind.customer => 'KH',
    };
    values.add(
      entry.code.isEmpty
          ? CatalogEntry(
              id: entry.id,
              farmId: entry.farmId,
              kind: entry.kind,
              code: '$prefix-${next.toString().padLeft(6, '0')}',
              name: entry.name,
              unitId: entry.unitId,
              active: entry.active,
              revision: entry.revision,
            )
          : entry,
    );
  }

  @override
  Future<void> request(
    CatalogRequest request, {
    required void Function() authorize,
  }) async {
    authorize();
    suggestions.add(request);
  }

  @override
  Future<List<CatalogRequest>> requests(
    String farmId, {
    String? actorUid,
  }) async => suggestions
      .where(
        (r) =>
            r.farmId == farmId && (actorUid == null || r.actorUid == actorUid),
      )
      .toList();
  @override
  Future<void> resolve({
    required String farmId,
    required String requestId,
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    String? entryId,
    CatalogEntry? createEntry,
    required void Function() authorize,
  }) async {
    authorize();
  }
}

void main() {
  late _Repo repo;
  setUp(() => repo = _Repo());
  CompanyCatalogService service(bool admin) => CompanyCatalogService(
    repository: repo,
    subject: AuthorizationSubject(
      userId: 'user',
      membershipId: 'member',
      farmId: 'farm',
      permissionCodes: {
        PermissionCodes.catalogView,
        PermissionCodes.catalogRequest,
        if (admin) PermissionCodes.catalogManage,
      },
      dataScopes: {DataScope.allFarm},
    ),
  );
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('vi'),
    localizationsDelegates: const [AppLocalizations.delegate],
    home: home,
  );
  testWidgets('admin creates controlled unit and invalid form does not save', (
    tester,
  ) async {
    await tester.pumpWidget(app(CompanyCatalogScreen(service: service(true))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('company-catalog-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('company-catalog-save')));
    await tester.pumpAndSettle();
    expect(repo.values, isEmpty);
    await tester.enterText(find.byKey(const Key('company-catalog-name')), 'kg');
    await tester.enterText(
      find.byKey(const Key('company-catalog-reason')),
      'Standard unit',
    );
    await tester.tap(find.byKey(const Key('company-catalog-save')));
    await tester.pumpAndSettle();
    expect(repo.values.single.code, 'DVT-000001');
    expect(repo.values.single.kind, CatalogKind.unit);
    expect(find.text('DVT-000001 · kg'), findsOneWidget);
  });
  testWidgets(
    'staff cannot edit entries; suggestion remains pending without master write',
    (tester) async {
      repo.values.add(
        const CatalogEntry(
          id: 'u',
          farmId: 'farm',
          kind: CatalogKind.unit,
          code: 'KG',
          name: 'kg',
        ),
      );
      await tester.pumpWidget(
        app(CompanyCatalogScreen(service: service(false))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('company-catalog-add')), findsNothing);
      await tester.tap(find.text('KG · kg'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('company-catalog-save')), findsNothing);
      await tester.tap(find.byKey(const Key('company-catalog-request')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('company-catalog-code')),
        'L',
      );
      await tester.enterText(
        find.byKey(const Key('company-catalog-name')),
        'lít',
      );
      await tester.enterText(
        find.byKey(const Key('company-catalog-reason')),
        'Need for fuel',
      );
      await tester.tap(find.byKey(const Key('company-catalog-save')));
      await tester.pumpAndSettle();
      expect(repo.values, hasLength(1));
      expect(repo.suggestions.single.status, 'pending');
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          AppLocalizations.of(
            tester.element(find.byType(CompanyCatalogScreen)),
          ).text('catalog.status.pending'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('approval of new catalog entry never offers manual code input', (
    tester,
  ) async {
    repo.suggestions.add(
      CatalogRequest(
        id: 'request-1',
        farmId: 'farm',
        actorUid: 'worker',
        kind: CatalogKind.unit,
        code: 'SUGGESTED',
        name: 'New unit',
        reason: 'Required',
        createdAt: DateTime.utc(2026, 10, 18),
      ),
    );
    await tester.pumpWidget(app(CompanyCatalogScreen(service: service(true))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-request-request-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalog-approval-code')), findsNothing);
    expect(find.byKey(const Key('catalog-approval-name')), findsOneWidget);
    expect(
      find.textContaining('Mã danh mục mới sẽ được hệ thống cấp tự động'),
      findsOneWidget,
    );
  });

  testWidgets('long adopted unit fits a phone dialog', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repo.values.addAll([
      const CatalogEntry(
        id: 'long-unit',
        farmId: 'farm',
        kind: CatalogKind.unit,
        code: 'OLD-9E995B21D4E942A4',
        name: 'Cây trồng trong vùng dự án',
      ),
      const CatalogEntry(
        id: 'crop',
        farmId: 'farm',
        kind: CatalogKind.crop,
        code: 'LAC',
        name: 'Lạc',
        unitId: 'long-unit',
        revision: 1,
      ),
    ]);
    await tester.pumpWidget(app(CompanyCatalogScreen(service: service(true))));
    await tester.pumpAndSettle();
    final kindPicker = tester.widget<DropdownButtonFormField<CatalogKind>>(
      find.byType(DropdownButtonFormField<CatalogKind>),
    );
    kindPicker.onChanged!(CatalogKind.crop);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('company-catalog-entry-crop')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final unitFinder = find.byKey(const Key('company-catalog-unit'));
    expect(unitFinder, findsOneWidget);
    await tester.tap(unitFinder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker exposes catalog choices rather than free text', (
    tester,
  ) async {
    repo.values.add(
      const CatalogEntry(
        id: 'u',
        farmId: 'farm',
        kind: CatalogKind.unit,
        code: 'KG',
        name: 'kg',
      ),
    );
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CatalogValuePicker(
            service: service(false),
            kind: CatalogKind.unit,
            controller: controller,
            label: 'Unit',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg (KG)').last);
    await tester.pumpAndSettle();
    expect(controller.text, 'kg');
  });
  testWidgets('session expiring while editor is open blocks save', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 3);
    final svc = CompanyCatalogService(
      repository: repo,
      clock: () => now,
      subject: AuthorizationSubject(
        userId: 'user',
        membershipId: 'member',
        farmId: 'farm',
        permissionCodes: {
          PermissionCodes.catalogView,
          PermissionCodes.catalogManage,
        },
        dataScopes: {DataScope.allFarm},
        validUntil: DateTime.utc(2026, 10, 4),
      ),
    );
    await tester.pumpWidget(app(CompanyCatalogScreen(service: svc)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('company-catalog-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('company-catalog-name')), 'kg');
    await tester.enterText(
      find.byKey(const Key('company-catalog-reason')),
      'Standard',
    );
    now = DateTime.utc(2026, 10, 5);
    await tester.tap(find.byKey(const Key('company-catalog-save')));
    await tester.pumpAndSettle();
    expect(repo.values, isEmpty);
    expect(find.byKey(const Key('company-catalog-error')), findsOneWidget);
  });
}
