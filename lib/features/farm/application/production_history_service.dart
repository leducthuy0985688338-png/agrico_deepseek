import '../../../core/permissions/authorization.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/entities/parcel_work.dart';
import '../domain/repositories/land_parcel_repository.dart';
import '../domain/repositories/parcel_work_repository.dart';
import 'parcel_work_service.dart';

/// Read-only entry point over existing parcel execution records.
class ProductionHistoryService extends ParcelWorkService {
  const ProductionHistoryService({
    required ParcelWorkRepository work,
    required this.parcels,
    required this.subject,
    required this.currentSubject,
  }) : super(work);

  final LandParcelRepository parcels;
  final AuthorizationSubject subject;
  final AuthorizationSubject? Function() currentSubject;

  bool get canView {
    final live = currentSubject();
    return live != null &&
        live.validUntil != null &&
        live.userId == subject.userId &&
        live.membershipId == subject.membershipId &&
        live.farmId == subject.farmId &&
        live.dataScopes.contains(DataScope.allFarm) &&
        [PermissionCodes.fieldView, PermissionCodes.catalogView].every(
          (permission) => const AuthorizationService().can(
            subject: live,
            permission: permission,
            resource: ResourceContext(farmId: subject.farmId),
          ),
        );
  }

  AuthorizationSubject _live() {
    if (!canView) {
      throw StateError('Production history access denied.');
    }
    return currentSubject()!;
  }

  Future<List<LandParcel>> listParcels() async {
    final live = _live();
    final result = await parcels.listByFarm(live.farmId);
    _live();
    if (result.any((parcel) => parcel.farmId != subject.farmId)) {
      throw StateError('Parcel is outside the current farm.');
    }
    return result.where((parcel) => parcel.active).toList();
  }

  @override
  Future<List<WorkResource>> resources(AuthorizationSubject subject) async {
    final result = await super.resources(_live());
    _live();
    if (result.any((resource) => resource.farmId != this.subject.farmId)) {
      throw StateError('Resource is outside the current farm.');
    }
    return result;
  }

  @override
  Future<List<ParcelWorkEvent>> events(
    AuthorizationSubject subject,
    String parcelId,
  ) async {
    final live = _live();
    final parcel = await parcels.getById(farmId: live.farmId, id: parcelId);
    _live();
    if (parcel == null ||
        parcel.id != parcelId ||
        !parcel.active ||
        parcel.farmId != this.subject.farmId) {
      throw StateError('Unknown parcel in production history.');
    }
    final result = await super.events(_live(), parcelId);
    _live();
    if (result.any(
      (event) =>
          event.farmId != this.subject.farmId || event.parcelId != parcelId,
    )) {
      throw StateError('Work event is outside the selected parcel.');
    }
    return result;
  }

  @override
  Future<void> record(
    AuthorizationSubject subject,
    ParcelWorkEvent event,
  ) async {
    throw StateError('Production history is read-only.');
  }

  @override
  Future<void> register(
    AuthorizationSubject subject,
    WorkResource resource,
  ) async {
    throw StateError('Production history is read-only.');
  }

  @override
  Future<void> registerBatch(
    AuthorizationSubject subject,
    List<WorkResource> resources,
  ) async {
    throw StateError('Production history is read-only.');
  }
}
