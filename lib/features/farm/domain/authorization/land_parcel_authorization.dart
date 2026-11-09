import '../../../../core/permissions/authorization.dart';

class LandParcelAccessContext {
  const LandParcelAccessContext({
    required this.farmId,
    required this.parcelId,
    this.ownerUserId,
    this.teamId,
  });

  final String farmId;
  final String parcelId;
  final String? ownerUserId;
  final String? teamId;

  ResourceContext toResourceContext() => ResourceContext(
    farmId: farmId,
    fieldId: parcelId,
    ownerUserId: ownerUserId,
    teamId: teamId,
  );
}

class LandParcelAuthorization {
  const LandParcelAuthorization({
    this.authorization = const AuthorizationService(),
  });

  final AuthorizationService authorization;

  bool canMeasure(
    AuthorizationSubject subject,
    LandParcelAccessContext parcel,
  ) => _can(subject, parcel, PermissionCodes.fieldMeasure);

  bool canEditBoundary(
    AuthorizationSubject subject,
    LandParcelAccessContext parcel,
  ) => _can(subject, parcel, PermissionCodes.fieldBoundaryEdit);

  bool canVerifyBoundary(
    AuthorizationSubject subject,
    LandParcelAccessContext parcel,
  ) => _can(subject, parcel, PermissionCodes.fieldBoundaryVerify);

  bool canImportGoogleEarth(
    AuthorizationSubject subject,
    LandParcelAccessContext parcel,
  ) => _can(subject, parcel, PermissionCodes.fieldGoogleEarthImport);

  bool canExportGoogleEarth(
    AuthorizationSubject subject,
    LandParcelAccessContext parcel,
  ) => _can(subject, parcel, PermissionCodes.fieldGoogleEarthExport);

  bool _can(
    AuthorizationSubject subject,
    LandParcelAccessContext parcel,
    String permission,
  ) => authorization.can(
    subject: subject,
    permission: permission,
    resource: parcel.toResourceContext(),
  );
}
