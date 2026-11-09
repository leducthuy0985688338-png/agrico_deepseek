import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/farm/application/production_history_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/parcel_work_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/production_history_screen.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/parcel_work_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

AuthorizationSubject actor({
  Set<String> permissions = const {
    PermissionCodes.fieldView,
    PermissionCodes.catalogView,
    PermissionCodes.fieldEdit,
    PermissionCodes.catalogManage,
  },
  String farm = 'farm',
  String user = 'user',
  bool expired = false,
  Set<DataScope> scopes = const {DataScope.allFarm},
  Map<String, Set<DataScope>> overrides = const {},
}) => AuthorizationSubject(
  userId: user,
  membershipId: 'member',
  farmId: farm,
  permissionCodes: permissions,
  dataScopes: scopes,
  permissionScopes: overrides,
  validUntil: DateTime.now().add(Duration(hours: expired ? -1 : 1)),
);

LandParcel parcel(String id, {String farm = 'farm', bool active = true}) =>
    LandParcel.create(
      id: id,
      farmId: farm,
      parcelCode: 'P-$id',
      name: 'Lô $id',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16, longitude: 106),
        Wgs84Vertex(latitude: 16, longitude: 106.001),
        Wgs84Vertex(latitude: 16.001, longitude: 106.001),
        Wgs84Vertex(latitude: 16.001, longitude: 106),
      ]),
      boundarySource: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.draft,
      actorMembershipId: 'member',
      occurredAt: DateTime(2026),
      active: active,
    );
ParcelWorkEvent event({String farm = 'farm', String parcelId = 'one'}) =>
    ParcelWorkEvent(
      id: 'event',
      farmId: farm,
      parcelId: parcelId,
      phase: ParcelWorkPhase.clearing,
      description: 'Khai hoang',
      occurredAt: DateTime(2026),
      actorMembershipId: 'member',
      machineIds: const [],
      workerIds: const [],
    );

Widget app(Widget home) => MaterialApp(
  locale: const Locale('vi'),
  supportedLocales: const [Locale('vi')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void main() {
  late _Parcels parcels;
  late _Work work;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late ProductionHistoryService service;
  setUp(() {
    parcels = _Parcels()..items = [parcel('one')];
    work = _Work();
    initial = actor();
    live = initial;
    service = ProductionHistoryService(
      work: work,
      parcels: parcels,
      subject: initial,
      currentSubject: () => live,
    );
  });
  test(
    'lists active parcels and reuses execution records without writes',
    () async {
      parcels.items.add(parcel('inactive', active: false));
      work.items = [event()];
      expect((await service.listParcels()).map((p) => p.id), ['one']);
      expect((await service.events(initial, 'one')).single.id, 'event');
      expect(work.writes, 0);
    },
  );
  test(
    'missing grants, narrow scopes and permission overrides deny reads',
    () async {
      for (final subject in [
        actor(permissions: {PermissionCodes.fieldView}),
        actor(permissions: {PermissionCodes.catalogView}),
        actor(scopes: {DataScope.own}),
        actor(overrides: {PermissionCodes.fieldView: {}}),
      ]) {
        live = subject;
        await expectLater(service.listParcels(), throwsStateError);
      }
      expect(parcels.reads, 0);
    },
  );
  test(
    'logout, expiration and changed identity deny saved entry points',
    () async {
      for (final subject in <AuthorizationSubject?>[
        null,
        actor(expired: true),
        actor(farm: 'other'),
        actor(user: 'other'),
      ]) {
        live = subject;
        await expectLater(service.listParcels(), throwsStateError);
        await expectLater(service.events(initial, 'one'), throwsStateError);
      }
      expect(parcels.reads, 0);
    },
  );
  test('revoked grant during parcel read does not return data', () async {
    parcels.onRead = () {
      live = actor(permissions: {});
    };
    await expectLater(service.listParcels(), throwsStateError);
  });
  test('foreign parcel and event results are rejected', () async {
    parcels.items = [parcel('foreign', farm: 'other')];
    await expectLater(service.listParcels(), throwsStateError);
    parcels.items = [parcel('one')];
    work.items = [event(parcelId: 'other')];
    await expectLater(service.events(initial, 'one'), throwsStateError);
    await expectLater(service.events(initial, 'missing'), throwsStateError);
  });
  test(
    'history service cannot record or register even for an editor',
    () async {
      await expectLater(service.record(initial, event()), throwsStateError);
      await expectLater(service.registerBatch(initial, []), throwsStateError);
      expect(work.writes, 0);
    },
  );
  testWidgets('parcel picker opens selected parcel and refreshes its list', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      app(
        ProductionHistoryScreen(
          service: service,
          openParcel: (value) {
            opened = value.id;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('production-history-one')));
    expect(opened, 'one');
    parcels.items = [];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('production-history-one')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('history hides write actions even with edit grants', (
    tester,
  ) async {
    work.items = [event()];
    await tester.pumpWidget(
      app(
        ParcelWorkScreen(
          parcelId: 'one',
          subject: initial,
          service: service,
          readOnly: true,
          canView: () => service.canView,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-event-event')), findsOneWidget);
    expect(find.text('Ghi công việc'), findsNothing);
    expect(find.text('Thêm máy hoặc nhân công'), findsNothing);
    expect(work.writes, 0);
    expect(tester.takeException(), isNull);
  });
}

class _Parcels implements LandParcelRepository {
  List<LandParcel> items = [];
  int reads = 0;
  void Function()? onRead;
  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) async {
    reads++;
    onRead?.call();
    return List.of(items);
  }

  @override
  Future<LandParcel?> getById({
    required String farmId,
    required String id,
  }) async {
    reads++;
    onRead?.call();
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Work implements ParcelWorkRepository {
  List<ParcelWorkEvent> items = [];
  int writes = 0;
  @override
  Future<List<ParcelWorkEvent>> events(String farmId, String parcelId) async =>
      List.of(items);
  @override
  Future<List<WorkResource>> resources(String farmId) async => [];
  @override
  Future<void> record(ParcelWorkEvent event) async {
    writes++;
  }

  @override
  Future<void> register(WorkResource resource) async {
    writes++;
  }

  @override
  Future<void> registerBatch(List<WorkResource> resources) async {
    writes++;
  }
}
