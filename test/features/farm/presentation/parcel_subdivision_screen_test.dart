import 'package:agrico_deepseek/core/geography/domain/administrative_catalog_repository.dart';
import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_spatial_sync_workflow.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_subdivision_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/parcel_subdivision_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('independent sketches allow touching and overlapping edges',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final parcel = LandParcel.create(
      id: 'source', farmId: 'farm', parcelCode: 'SOURCE', name: 'Nguồn',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16, longitude: 106),
        Wgs84Vertex(latitude: 16, longitude: 106.002),
        Wgs84Vertex(latitude: 16.002, longitude: 106.002),
        Wgs84Vertex(latitude: 16.002, longitude: 106),
      ]),
      boundarySource: BoundarySource.googleEarth,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member', occurredAt: DateTime.utc(2026, 9, 28),
    );
    const subject = AuthorizationSubject(
      userId: 'user', membershipId: 'member', farmId: 'farm',
      permissionCodes: {PermissionCodes.fieldView},
      dataScopes: {DataScope.allFarm},
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: ParcelSubdivisionScreen(
        subject: subject, sourceParcelId: 'source',
        service: ParcelSubdivisionService(
          parcels: _ParcelRepository(parcel), workflow: _UnusedWorkflow()),
        administrativeCatalog: _EmptyCatalog(),
      ),
    ));
    await tester.pumpAndSettle();
    final map = find.byKey(const Key('subdivision-map'));
    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    final size = tester.getSize(map);
    final origin = tester.getTopLeft(map);
    final scale = (size.height - 40) / 0.002;
    for (final (lat, lon) in [
      (16.0006, 106.00005), (16.0006, 106.0014),
      (16.0014, 106.0014), (16.0014, 106.0006),
    ]) {
      await tester.tapAt(origin + Offset((lon - 106.001) * scale +
        size.width / 2, (16.001 - lat) * scale + size.height / 2));
      await tester.pumpAndSettle();
    }
    final done = find.byKey(const Key('subdivision-close-outline'));
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subdivision-name-0')), findsOneWidget);
    expect(find.textContaining('Đường cắt phải nằm bên trong'), findsNothing);

    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    final nextOrigin = tester.getTopLeft(map);
    for (final (lat, lon) in [
      (16.0006, 106.0014), (16.0006, 106.0018),
      (16.0014, 106.0018), (16.0014, 106.0014),
    ]) {
      await tester.tapAt(nextOrigin + Offset((lon - 106.001) * scale +
        size.width / 2, (16.001 - lat) * scale + size.height / 2));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subdivision-name-1')), findsOneWidget);
    expect(find.textContaining('hai vùng đất không chồng lấn'), findsNothing);

    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    final thirdOrigin = tester.getTopLeft(map);
    for (final (lat, lon) in [
      (16.0007, 105.99998), (16.0007, 106.0008),
      (16.0012, 106.0008), (16.0012, 105.99998),
    ]) {
      await tester.tapAt(thirdOrigin + Offset((lon - 106.001) * scale +
        size.width / 2, (16.001 - lat) * scale + size.height / 2));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('subdivision-name-2')),
      180);
    expect(find.byKey(const Key('subdivision-name-2')), findsOneWidget);
    expect(find.textContaining(' m² · '), findsWidgets);
  });

  testWidgets('drawing the photographed outline previews two closed parcels',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final parcel = LandParcel.create(
      id: 'source', farmId: 'farm', parcelCode: 'SOURCE', name: 'Nguồn',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16, longitude: 106),
        Wgs84Vertex(latitude: 16, longitude: 106.002),
        Wgs84Vertex(latitude: 16.002, longitude: 106.002),
        Wgs84Vertex(latitude: 16.002, longitude: 106),
      ]),
      boundarySource: BoundarySource.gps,
      verificationStatus: BoundaryVerificationStatus.measured,
      actorMembershipId: 'member', occurredAt: DateTime.utc(2026, 9, 28),
    );
    const subject = AuthorizationSubject(
      userId: 'user', membershipId: 'member', farmId: 'farm',
      permissionCodes: {PermissionCodes.fieldView},
      dataScopes: {DataScope.allFarm},
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: ParcelSubdivisionScreen(
        subject: subject, sourceParcelId: 'source',
        service: ParcelSubdivisionService(
          parcels: _ParcelRepository(parcel), workflow: _UnusedWorkflow()),
        administrativeCatalog: _EmptyCatalog(),
      ),
    ));
    await tester.pumpAndSettle();
    final map = find.byKey(const Key('subdivision-map'));
    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    final size = tester.getSize(map);
    final origin = tester.getTopLeft(map);
    final scale = (size.width - 40) / 0.002 < (size.height - 40) / 0.002
        ? (size.width - 40) / 0.002 : (size.height - 40) / 0.002;
    Future<void> tap(double lat, double lon) async {
      final x = (lon - 106.001) * scale + size.width / 2;
      final y = (16.001 - lat) * scale + size.height / 2;
      await tester.tapAt(origin + Offset(x, y));
      await tester.pumpAndSettle();
    }

    await tap(16.002, 106);           // First boundary point.
    await tap(16.002, 106.001);       // Trace the top boundary.
    await tap(16.002, 106.002);
    await tap(16.0015, 106.002);      // Right boundary anchor.
    await tap(16.00135, 106.0016);   // Interior bends.
    await tap(16.0013, 106.001);
    await tap(16.0014, 106.0003);
    await tap(16.0017, 106);         // Second boundary anchor.
    final done = find.byKey(const Key('subdivision-close-outline'));
    await tester.ensureVisible(done);
    await tester.tap(done);          // Explicit Google Earth style Done step.
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('subdivision-name-0')), findsOneWidget);
    expect(find.textContaining('Đường cắt phải nằm bên trong'), findsNothing);
  });
}

class _ParcelRepository implements LandParcelRepository {
  _ParcelRepository(this.parcel);
  final LandParcel parcel;

  @override
  Future<LandParcel?> getById({required String farmId, required String id})
      async => farmId == parcel.farmId && id == parcel.id ? parcel : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyCatalog implements AdministrativeCatalogRepository {
  @override
  Future<List<AdministrativeUnit>> all() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedWorkflow implements LandParcelSpatialSyncWorkflow {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
