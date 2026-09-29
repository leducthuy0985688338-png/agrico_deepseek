import 'dart:math';

import '../../permissions/authorization.dart';
import '../domain/administrative_catalog_repository.dart';
import '../domain/entities/administrative_unit.dart';

class ManageAdministrativeCatalog {
  ManageAdministrativeCatalog(this.repository);

  final AdministrativeCatalogRepository repository;

  Future<List<AdministrativeUnit>> all() => repository.all();

  Future<void> add({
    required AuthorizationSubject subject,
    required AdministrativeLevel level,
    required String parentId,
    required String name,
    required String code,
    String? alternateName,
  }) async {
    if (!const AuthorizationService().can(
      subject: subject,
      permission: PermissionCodes.administrativeCatalogManage,
      resource: ResourceContext(farmId: subject.farmId),
    )) {
      throw StateError('Administrative catalog permission denied.');
    }
    final normalizedCode = code.trim().toUpperCase();
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || !RegExp(r'^[A-Z0-9]+$').hasMatch(normalizedCode)) {
      throw const FormatException('Enter a name and a code using A–Z and 0–9.');
    }
    final now = DateTime.now().toUtc();
    await repository.add(AdministrativeUnit(
      id: 'agrico-admin-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      level: level,
      parentId: parentId,
      name: normalizedName,
      code: normalizedCode,
      alternateName: alternateName?.trim().isEmpty == true
          ? null : alternateName?.trim(),
      createdAt: now,
      createdBy: subject.membershipId,
    ));
  }
}
