import '../../../core/permissions/authorization.dart';
import '../../../core/catalog/company_catalog.dart';
import '../domain/entities/parcel_work.dart';
import '../domain/repositories/parcel_work_repository.dart';

class ParcelWorkService {
  const ParcelWorkService(this.repository, {this.catalog});
  final CompanyCatalogService? catalog;

  final ParcelWorkRepository repository;

  void _authorize(
    AuthorizationSubject subject,
    String permission, {
    String? parcelId,
  }) {
    if (!const AuthorizationService().can(
          subject: subject,
          permission: permission,
          resource: ResourceContext(farmId: subject.farmId, fieldId: parcelId),
        ) ||
        !subject.dataScopes.contains(DataScope.allFarm)) {
      throw StateError('Parcel work requires farm-wide access.');
    }
  }

  Future<void> register(AuthorizationSubject subject, WorkResource resource) {
    _authorize(subject, PermissionCodes.catalogManage);
    if (resource.farmId != subject.farmId) {
      throw StateError('Resource is outside the current farm.');
    }
    if (catalog != null) {
      if (catalog!.subject.userId != subject.userId ||
          catalog!.subject.farmId != subject.farmId) {
        throw StateError('Catalog subject mismatch.');
      }
      return catalog!.create(
        CatalogEntry(
          id: resource.id,
          farmId: resource.farmId,
          kind: CatalogKind.values.byName(resource.kind.name),
          code: '',
          name: resource.name.trim(),
          active: resource.active,
        ),
        reason: 'Register work resource',
      );
    }
    return repository.register(resource);
  }

  Future<List<WorkResource>> resources(AuthorizationSubject subject) {
    if (!const AuthorizationService().can(
      subject: subject,
      permission: PermissionCodes.catalogView,
      resource: ResourceContext(farmId: subject.farmId),
    )) {
      throw StateError('Catalog access denied.');
    }
    return repository.resources(subject.farmId);
  }

  Future<void> registerBatch(
    AuthorizationSubject subject,
    List<WorkResource> resources,
  ) {
    _authorize(subject, PermissionCodes.catalogManage);
    if (resources.any((resource) => resource.farmId != subject.farmId)) {
      throw StateError('Resource is outside the current farm.');
    }
    if (catalog != null) {
      throw StateError('Use the company catalog to adopt resources.');
    }
    return repository.registerBatch(resources);
  }

  Future<void> record(AuthorizationSubject subject, ParcelWorkEvent event) {
    _authorize(subject, PermissionCodes.fieldEdit, parcelId: event.parcelId);
    if (event.farmId != subject.farmId ||
        event.actorMembershipId != subject.membershipId) {
      throw StateError('Work actor or farm does not match.');
    }
    return repository.record(event);
  }

  Future<List<ParcelWorkEvent>> events(
    AuthorizationSubject subject,
    String parcelId,
  ) {
    _authorize(subject, PermissionCodes.fieldView, parcelId: parcelId);
    return repository.events(subject.farmId, parcelId);
  }
}
