import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/household_detail_query.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/household_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28);
  Household household(String farm) => Household(
    id: 'household-1', farmId: farm, householdCode: 'H00001',
    headOfHouseholdName: 'ນາງ ສົມພອນ',
    administrativeLocation: const AdministrativeLocation(
      countryName: 'Lào', provinceName: 'Savannakhet',
      districtName: 'Nong', villageName: 'Ta Ko'),
    active: true, createdAt: now, createdBy: 'member',
    updatedAt: now, updatedBy: 'member',
  );
  LandParcel parcel(String id, String owner, {bool active = true}) =>
      LandParcel.create(
        id: id, farmId: 'farm-1', parcelCode: 'LA-SVK-NONG-TAKO-H00001-$id',
        name: 'Thửa $id', ownerHouseholdId: owner,
        ownerDisplayName: 'ນາງ ສົມພອນ', active: active,
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16.5, longitude: 104.7),
          Wgs84Vertex(latitude: 16.5, longitude: 104.701),
          Wgs84Vertex(latitude: 16.501, longitude: 104.7),
        ]),
        boundarySource: BoundarySource.gps,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member', occurredAt: now,
      );
  const allowed = AuthorizationSubject(
    userId: 'user', membershipId: 'member', farmId: 'farm-1',
    permissionCodes: {PermissionCodes.fieldView},
    dataScopes: {DataScope.allFarm},
  );

  test('links only by household ID, includes inactive parcels and checks farm',
      () async {
    final households = _Households(household('farm-1'));
    final parcels = _Parcels([
      parcel('001', 'household-1'),
      parcel('002', 'household-1', active: false),
      parcel('003', 'another-household'),
    ]);
    final query = HouseholdDetailQuery(households, parcels);
    final result = await query.load(allowed, 'household-1');
    expect(result!.parcels.map((p) => p.id), ['001', '002']);
    expect(parcels.includeInactive, isTrue);
    expect(parcels.requestedFarm, 'farm-1');

    households.value = household('other-farm');
    expect(await query.load(allowed, 'household-1'), isNull);
    expect(parcels.calls, 1);
    await expectLater(query.load(const AuthorizationSubject(
      userId: 'user', membershipId: 'member', farmId: 'farm-1',
      permissionCodes: {PermissionCodes.fieldView},
      dataScopes: {DataScope.assignedFields},
    ), 'household-1'), throwsStateError);
  });

  testWidgets('shows linked parcels and opens the selected parcel',
      (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: HouseholdDetailScreen(
        query: HouseholdDetailQuery(_Households(household('farm-1')),
            _Parcels([parcel('001', 'household-1')])),
        subject: allowed, householdId: 'household-1',
        onOpenParcel: (id) => opened = id,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('H00001'), findsWidgets);
    expect(find.byKey(const Key('household-parcel-001')), findsOneWidget);
    await tester.tap(find.byKey(const Key('household-parcel-001')));
    expect(opened, '001');
  });
}

class _Households implements LandSurveyRepository {
  _Households(this.value);
  Household? value;
  @override
  Future<Household?> getHousehold(String id) async =>
      value?.id == id ? value : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Parcels implements LandParcelRepository {
  _Parcels(this.values);
  final List<LandParcel> values;
  bool? includeInactive;
  String? requestedFarm;
  int calls = 0;
  @override
  Future<List<LandParcel>> listByFarm(String farmId,
      {bool includeInactive = false}) async {
    calls++;
    requestedFarm = farmId;
    this.includeInactive = includeInactive;
    return values.where((parcel) => parcel.farmId == farmId &&
        (includeInactive || parcel.active)).toList();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
