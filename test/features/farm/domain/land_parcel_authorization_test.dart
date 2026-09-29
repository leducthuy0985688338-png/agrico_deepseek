import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/domain/authorization/land_parcel_authorization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = LandParcelAuthorization();
  const resource = LandParcelAccessContext(
    farmId: 'farm-1',
    parcelId: 'parcel-1',
    teamId: 'team-1',
  );

  AuthorizationSubject subject(Set<String> permissions) => AuthorizationSubject(
    userId: 'user-1',
    membershipId: 'member-1',
    farmId: 'farm-1',
    permissionCodes: permissions,
    dataScopes: const {DataScope.assignedFields},
    assignedFieldIds: const {'parcel-1'},
  );

  test('maps every sensitive boundary action to its permission code', () {
    expect(
      service.canMeasure(subject(PermissionCodes.values), resource),
      isTrue,
    );
    expect(
      service.canEditBoundary(subject(PermissionCodes.values), resource),
      isTrue,
    );
    expect(
      service.canVerifyBoundary(subject(PermissionCodes.values), resource),
      isTrue,
    );
    expect(
      service.canImportGoogleEarth(subject(PermissionCodes.values), resource),
      isTrue,
    );
    expect(
      service.canExportGoogleEarth(subject(PermissionCodes.values), resource),
      isTrue,
    );
  });

  test('denies a boundary action when permission is absent', () {
    expect(
      service.canVerifyBoundary(
        subject(const {PermissionCodes.fieldBoundaryEdit}),
        resource,
      ),
      isFalse,
    );
  });
}
