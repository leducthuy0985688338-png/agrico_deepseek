import '../../../core/permissions/authorization.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/geometry/field_plot_placement.dart';
import '../domain/repositories/land_parcel_repository.dart';

class ParcelParentException implements Exception {
  const ParcelParentException(this.code);
  final String code;
}

/// Changes only the parent relation; numbering and spatial data are not written.
class LandParcelParentService {
  const LandParcelParentService(this.parcels);
  final LandParcelRepository parcels;

  void _authorize(
    AuthorizationSubject subject,
    LandParcel plot,
    String permission,
  ) {
    if (subject.membershipId.trim().isEmpty ||
        !subject.dataScopes.contains(DataScope.allFarm) ||
        !const AuthorizationService().can(
          subject: subject,
          permission: permission,
          resource: ResourceContext(farmId: plot.farmId, fieldId: plot.id),
        )) {
      throw const ParcelParentException('permissionDenied');
    }
  }

  Future<List<LandParcel>> listBlocks({
    required AuthorizationSubject subject,
    required LandParcel plot,
  }) async {
    _authorize(subject, plot, PermissionCodes.fieldView);
    if (!plot.active || plot.kind != ParcelLayer.fieldPlot) {
      throw const ParcelParentException('invalidPlot');
    }
    if (plot.projectId == null) {
      return const [];
    }
    final rows = await parcels.listByFarm(subject.farmId);
    final blocks = rows
        .where(
          (p) =>
              p.active &&
              p.kind == ParcelLayer.landBlock &&
              p.parentBlockId == null &&
              p.projectId == plot.projectId &&
              p.id != plot.id,
        )
        .toList();
    blocks.sort((a, b) => a.parcelCode.compareTo(b.parcelCode));
    return List.unmodifiable(blocks);
  }

  /// Both snapshots come from the editor. Current rows are loaded and checked
  /// within one transaction so an old screen cannot overwrite a changed relation.
  /// A null target explicitly means detach, never "leave unchanged".
  Future<LandParcel> changeParent({
    required AuthorizationSubject subject,
    required LandParcel expectedPlot,
    required LandParcel? expectedParent,
  }) async {
    _authorize(subject, expectedPlot, PermissionCodes.fieldView);
    _authorize(subject, expectedPlot, PermissionCodes.fieldEdit);
    return parcels.transaction((repo) async {
      final plot = await repo.getById(
        farmId: subject.farmId,
        id: expectedPlot.id,
      );
      if (plot == null || !plot.active || plot.kind != ParcelLayer.fieldPlot) {
        throw const ParcelParentException('invalidPlot');
      }
      if (plot.boundaryVersion != expectedPlot.boundaryVersion ||
          plot.updatedAt != expectedPlot.updatedAt ||
          plot.parentBlockId != expectedPlot.parentBlockId ||
          plot.projectId != expectedPlot.projectId) {
        throw const ParcelParentException('changed');
      }
      final targetId = expectedParent?.id;
      if (targetId == plot.id) {
        throw const ParcelParentException('invalidParent');
      }
      if (expectedParent != null) {
        _authorize(subject, expectedParent, PermissionCodes.fieldEdit);
        final parent = await repo.getById(
          farmId: subject.farmId,
          id: targetId!,
        );
        if (parent == null ||
            !parent.active ||
            parent.kind != ParcelLayer.landBlock ||
            parent.parentBlockId != null) {
          throw const ParcelParentException('invalidParent');
        }
        if (parent.updatedAt != expectedParent.updatedAt ||
            parent.boundaryVersion != expectedParent.boundaryVersion) {
          throw const ParcelParentException('changed');
        }
        if (plot.projectId == null || parent.projectId != plot.projectId) {
          throw const ParcelParentException('projectMismatch');
        }
        final siblings = await repo.listByFarm(subject.farmId);
        try {
          const FieldPlotPlacement().validate(
            block: parent.boundary,
            plot: plot.boundary,
            existingPlots: siblings
                .where(
                  (p) =>
                      p.id != plot.id &&
                      p.active &&
                      p.kind == ParcelLayer.fieldPlot &&
                      p.parentBlockId == parent.id,
                )
                .map((p) => p.boundary),
          );
        } on FormatException catch (error) {
          throw ParcelParentException(
            error.message == 'Field plot overlaps an existing field plot.'
                ? 'overlap'
                : 'outsideBlock',
          );
        }
      }
      if (targetId == plot.parentBlockId) {
        return plot;
      }
      final updated = plot.updateKind(
        kind: ParcelLayer.fieldPlot,
        parentBlockId: targetId,
        actorMembershipId: subject.membershipId,
        occurredAt: DateTime.now().toUtc(),
      );
      await repo.update(updated);
      return updated;
    });
  }
}
