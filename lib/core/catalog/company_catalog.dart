import '../permissions/authorization.dart';

enum CatalogKind {
  unit,
  crop,
  machine,
  worker,
  material,
  taskType,
  supplier,
  incomeCategory,
  expenseCategory,
}

class CatalogFailure implements Exception {
  const CatalogFailure(this.code);
  final String code;
}

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.farmId,
    required this.kind,
    required this.code,
    required this.name,
    this.unitId,
    this.active = true,
    this.revision = 0,
  });
  final String id, farmId, code, name;
  final CatalogKind kind;
  final String? unitId;
  final bool active;
  final int revision;
  void validate() {
    if (id.trim().isEmpty ||
        farmId.trim().isEmpty ||
        !RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,39}$').hasMatch(code) ||
        name.trim().isEmpty ||
        name != name.trim() ||
        name.length > 100 ||
        revision < 0 ||
        (kind == CatalogKind.unit && unitId != null) ||
        ((kind == CatalogKind.crop || kind == CatalogKind.material) &&
            unitId == null)) {
      throw const CatalogFailure('catalog.invalid');
    }
  }
}

class CatalogRequest {
  const CatalogRequest({
    required this.id,
    required this.farmId,
    required this.actorUid,
    required this.kind,
    required this.code,
    required this.name,
    required this.reason,
    required this.createdAt,
    this.status = 'pending',
    this.entryId,
    this.resolution,
  });
  final String id, farmId, actorUid, code, name, reason, status;
  final CatalogKind kind;
  final DateTime createdAt;
  final String? entryId, resolution;
}

abstract interface class CompanyCatalogRepository {
  Future<List<CatalogEntry>> entries(String farmId);
  Future<void> save(
    CatalogEntry entry, {
    required int? expectedRevision,
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    required void Function() authorize,
  });
  Future<void> request(
    CatalogRequest request, {
    required void Function() authorize,
  });
  Future<List<CatalogRequest>> requests(String farmId, {String? actorUid});
  Future<void> resolve({
    required String farmId,
    required String requestId,
    required String actorUid,
    required String reason,
    required DateTime occurredAt,
    String? entryId,
    CatalogEntry? createEntry,
    required void Function() authorize,
  });
}

class CompanyCatalogService {
  const CompanyCatalogService({
    required this.repository,
    required this.subject,
    this.clock,
  });
  final CompanyCatalogRepository repository;
  final AuthorizationSubject subject;
  final DateTime Function()? clock;
  bool can(String permission, {bool own = false}) =>
      AuthorizationService(clock: clock).can(
        subject: subject,
        permission: permission,
        resource: ResourceContext(
          farmId: subject.farmId,
          ownerUserId: own ? subject.userId : null,
        ),
      );
  bool get canManage => can(PermissionCodes.catalogManage);
  bool get canRequest => can(PermissionCodes.catalogRequest, own: true);
  void require(String permission, {bool own = false}) {
    if (!can(permission, own: own)) {
      throw const CatalogFailure('catalog.denied');
    }
  }

  String _reason(String reason) {
    final value = reason.trim();
    if (value.isEmpty || value.length > 500) {
      throw const CatalogFailure('catalog.reasonRequired');
    }
    return value;
  }

  Future<List<CatalogEntry>> entries() {
    require(PermissionCodes.catalogView);
    return repository.entries(subject.farmId);
  }

  Future<void> save(
    CatalogEntry entry, {
    required int? expectedRevision,
    required String reason,
  }) {
    require(PermissionCodes.catalogManage);
    if (entry.farmId != subject.farmId) {
      throw const CatalogFailure('catalog.denied');
    }
    entry.validate();
    return repository.save(
      entry,
      expectedRevision: expectedRevision,
      actorUid: subject.userId,
      reason: _reason(reason),
      occurredAt: (clock ?? DateTime.now)().toUtc(),
      authorize: () => require(PermissionCodes.catalogManage),
    );
  }

  Future<void> request({
    required String id,
    required CatalogKind kind,
    required String code,
    required String name,
    required String reason,
  }) {
    require(PermissionCodes.catalogRequest, own: true);
    if (id.trim().isEmpty ||
        !RegExp(
          r'^[A-Z0-9][A-Z0-9_-]{0,39}$',
        ).hasMatch(code.trim().toUpperCase()) ||
        name.trim().isEmpty ||
        name.trim().length > 100) {
      throw const CatalogFailure('catalog.invalid');
    }
    return repository.request(
      CatalogRequest(
        id: id,
        farmId: subject.farmId,
        actorUid: subject.userId,
        kind: kind,
        code: code.trim().toUpperCase(),
        name: name.trim(),
        reason: _reason(reason),
        createdAt: (clock ?? DateTime.now)().toUtc(),
      ),
      authorize: () => require(PermissionCodes.catalogRequest, own: true),
    );
  }

  Future<List<CatalogRequest>> requests() {
    if (canManage) return repository.requests(subject.farmId);
    require(PermissionCodes.catalogRequest, own: true);
    return repository.requests(subject.farmId, actorUid: subject.userId);
  }

  Future<void> resolve(
    String requestId, {
    String? entryId,
    CatalogEntry? createEntry,
    required String reason,
  }) {
    require(PermissionCodes.catalogManage);
    return repository.resolve(
      farmId: subject.farmId,
      requestId: requestId,
      actorUid: subject.userId,
      reason: _reason(reason),
      occurredAt: (clock ?? DateTime.now)().toUtc(),
      entryId: entryId,
      createEntry: createEntry,
      authorize: () => require(PermissionCodes.catalogManage),
    );
  }
}
