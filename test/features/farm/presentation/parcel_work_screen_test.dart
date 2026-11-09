import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/parcel_work_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phase filter switches, survives refresh and preserves records', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WorkRepository();
    for (final phase in ParcelWorkPhase.values) {
      repository.savedEvents.add(
        ParcelWorkEvent(
          id: phase.name,
          farmId: 'farm-1',
          parcelId: 'parcel-1',
          phase: phase,
          description: 'Thực hiện ${phase.name}',
          occurredAt: DateTime(2026, 10, 7),
          actorMembershipId: 'actor',
          machineIds: const ['m1'],
          workerIds: const [],
        ),
      );
    }
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'actor',
      farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView, PermissionCodes.catalogView},
      dataScopes: {DataScope.allFarm},
    );
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
        home: ParcelWorkScreen(
          parcelId: 'parcel-1',
          subject: subject,
          service: ParcelWorkService(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-event-clearing')), findsOneWidget);
    expect(find.byKey(const Key('work-event-cultivation')), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-phase-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khai hoang').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-event-clearing')), findsOneWidget);
    expect(find.byKey(const Key('work-event-cultivation')), findsNothing);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-event-cultivation')), findsNothing);
    await tester.tap(find.byKey(const Key('work-phase-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canh tác').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-event-clearing')), findsNothing);
    expect(find.byKey(const Key('work-event-cultivation')), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-event-cultivation')));
    await tester.pumpAndSettle();
    expect(
      find.text('Nội dung công việc: Thực hiện cultivation'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('work-close-event-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-phase-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tất cả').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-event-clearing')), findsOneWidget);
    expect(find.byKey(const Key('work-event-cultivation')), findsOneWidget);
    expect(repository.savedEvents, hasLength(2));
  });

  testWidgets('unmatched phase shows filter message without removing history', (
    tester,
  ) async {
    final repository = _WorkRepository();
    repository.savedEvents.add(
      ParcelWorkEvent(
        id: 'clearing',
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.clearing,
        description: 'Dọn thực bì',
        occurredAt: DateTime(2026, 10, 7),
        actorMembershipId: 'actor',
        machineIds: const ['m1'],
        workerIds: const [],
      ),
    );
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'actor',
      farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView, PermissionCodes.catalogView},
      dataScopes: {DataScope.allFarm},
    );
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
        home: ParcelWorkScreen(
          parcelId: 'parcel-1',
          subject: subject,
          service: ParcelWorkService(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-phase-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canh tác').last);
    await tester.pumpAndSettle();
    expect(find.text('Không có lần thực hiện phù hợp bộ lọc.'), findsOneWidget);
    expect(find.byKey(const Key('work-event-clearing')), findsNothing);
    expect(repository.savedEvents, hasLength(1));
  });

  testWidgets('read-only event details show resources, notes and no writes', (
    tester,
  ) async {
    final repository = _WorkRepository();
    repository.savedResources.add(
      const WorkResource(
        id: 'm1',
        farmId: 'farm-1',
        kind: WorkResourceKind.machine,
        code: 'M001',
        name: 'Máy khai hoang',
        active: false,
      ),
    );
    repository.savedEvents.add(
      ParcelWorkEvent(
        id: 'e1',
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.clearing,
        description: 'Dọn thực bì',
        occurredAt: DateTime(2026, 10, 7, 10, 30),
        actorMembershipId: 'actor',
        machineIds: const ['m1'],
        workerIds: const ['missing-worker'],
        areaM2: 500,
        notes: 'Ghi chú tiếng Việt · ລາວ',
      ),
    );
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'actor',
      farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView, PermissionCodes.catalogView},
      dataScopes: {DataScope.allFarm},
    );
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
        home: ParcelWorkScreen(
          parcelId: 'parcel-1',
          subject: subject,
          service: ParcelWorkService(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-add-event')), findsNothing);
    await tester.tap(find.byKey(const Key('work-event-e1')));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const Key('work-event-details'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('M001 · Máy khai hoang'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('missing-worker'),
      ),
      findsOneWidget,
    );
    expect(find.text('Diện tích thực hiện (m²): 500.0'), findsOneWidget);
    expect(find.text('Ghi chú: Ghi chú tiếng Việt · ລາວ'), findsOneWidget);
    expect(find.text('Thời gian thực hiện: 2026-10-07 10:30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-close-event-details')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(repository.savedEvents, hasLength(1));
    expect(repository.savedResources, hasLength(1));
  });

  testWidgets('event details show empty optional values', (tester) async {
    final repository = _WorkRepository();
    repository.savedEvents.add(
      ParcelWorkEvent(
        id: 'e2',
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.cultivation,
        description: 'Canh tác',
        occurredAt: DateTime(2026, 10, 7),
        actorMembershipId: 'actor',
        machineIds: const [],
        workerIds: const ['worker-id'],
      ),
    );
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'actor',
      farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView, PermissionCodes.catalogView},
      dataScopes: {DataScope.allFarm},
    );
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
        home: ParcelWorkScreen(
          parcelId: 'parcel-1',
          subject: subject,
          service: ParcelWorkService(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-event-e2')));
    await tester.pumpAndSettle();
    expect(find.text('Máy móc: —'), findsOneWidget);
    expect(find.text('Diện tích thực hiện (m²): —'), findsOneWidget);
    expect(find.text('Ghi chú: —'), findsOneWidget);
    expect(find.text('Nhân công: worker-id'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(repository.savedEvents, hasLength(1));
  });

  testWidgets('records clearing with a machine and shows persisted event', (
    tester,
  ) async {
    final repository = _WorkRepository();
    repository.savedResources.add(
      const WorkResource(
        id: 'm1',
        farmId: 'farm-1',
        kind: WorkResourceKind.machine,
        code: 'M001',
        name: 'Máy khai hoang',
      ),
    );
    const subject = AuthorizationSubject(
      userId: 'user',
      membershipId: 'actor',
      farmId: 'farm-1',
      permissionCodes: {
        PermissionCodes.fieldView,
        PermissionCodes.fieldEdit,
        PermissionCodes.catalogView,
        PermissionCodes.catalogManage,
      },
      dataScopes: {DataScope.allFarm},
    );
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
        home: ParcelWorkScreen(
          parcelId: 'parcel-1',
          subject: subject,
          service: ParcelWorkService(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-add-event')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Dọn thực bì');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final machine = find.byType(CheckboxListTile);
    await tester.ensureVisible(machine);
    await tester.tap(machine);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('work-save-event')));
    await tester.pumpAndSettle();
    expect(repository.savedEvents, hasLength(1));
    expect(repository.savedEvents.single.phase, ParcelWorkPhase.clearing);
    expect(repository.savedEvents.single.machineIds, ['m1']);
    expect(repository.savedEvents.single.description, 'Dọn thực bì');
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dọn thực bì'), findsOneWidget);
  });
}

class _WorkRepository implements ParcelWorkRepository {
  final savedResources = <WorkResource>[];
  final savedEvents = <ParcelWorkEvent>[];
  @override
  Future<void> register(WorkResource resource) async {
    savedResources.add(resource);
  }

  @override
  Future<void> registerBatch(List<WorkResource> resources) async {
    savedResources.addAll(resources);
  }

  @override
  Future<List<WorkResource>> resources(String farmId) async =>
      savedResources.where((r) => r.farmId == farmId).toList();
  @override
  Future<void> record(ParcelWorkEvent event) async {
    savedEvents.add(event);
  }

  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId) async =>
      savedEvents
          .where((e) => e.farmId == farmId && e.parcelId == parcelId)
          .toList();
}
