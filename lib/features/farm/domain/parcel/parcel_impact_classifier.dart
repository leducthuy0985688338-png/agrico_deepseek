import '../geometry/wgs84_geometry.dart';
import '../geometry/wgs84_multi_geometry_service.dart';
import '../geometry/wgs84_multi_polygon.dart';
import '../geometry/wgs84_topology.dart';

/// Quan hệ không gian thuần giữa một Thửa và một Lô (hợp vùng).
enum ParcelSpatialRelation {
  disjoint,
  boundaryOnly,
  partiallyCovered,
  fullyCovered,
}

/// Tác động nghiệp vụ khi Lô thay đổi.
enum ParcelImpactKind {
  unaffected,
  newlyCovered,
  partiallyCovered,
  boundaryOnlyChange,
  coverageImproved,
  coverageReduced,
  coverageLost,
  retainedCoverage,
  linkedBoundaryOnly,
  linkedPartialCoverage,
  linkedNowOutside,
  conflictWithOtherParent,
}

/// Kết quả phân loại tác động của một thay đổi Lô lên một Thửa.
class ParcelImpact {
  const ParcelImpact({
    required this.relationBefore,
    required this.relationAfter,
    required this.kind,
    required this.requiresReview,
    required this.linkSuggestion,
    required this.reasonKey,
  });

  final ParcelSpatialRelation relationBefore;
  final ParcelSpatialRelation relationAfter;
  final ParcelImpactKind kind;
  final bool requiresReview;
  final bool linkSuggestion;
  final String reasonKey;
}

/// Bộ phân loại tác động của THAY ĐỔI LÔ lên một Thửa.
///
/// Domain thuần. Không ghi database, không tạo issue/revision, không đụng UI.
/// P03 dùng kết quả để lưu revision và vấn đề đối soát atomically.
class ParcelImpactClassifier {
  const ParcelImpactClassifier();

  static const Wgs84MultiGeometryService _geometry =
      Wgs84MultiGeometryService();

  ParcelImpact classify({
    required String changedBlockId,
    required Wgs84MultiPolygon? blockBefore,
    required Wgs84MultiPolygon blockAfter,
    required String plotId,
    required Wgs84Polygon plotGeometry,
    required String? confirmedParentBlockId,
  }) {
    final relationBefore = blockBefore == null
        ? ParcelSpatialRelation.disjoint
        : _relation(blockBefore, plotGeometry);
    final relationAfter = _relation(blockAfter, plotGeometry);

    final wasLinked = confirmedParentBlockId == changedBlockId;
    final otherParent = confirmedParentBlockId != null && !wasLinked;

    if (wasLinked) return _classifyLinked(relationBefore, relationAfter);
    if (otherParent) {
      return _classifyOtherParent(relationBefore, relationAfter);
    }
    return _classifyIndependent(relationBefore, relationAfter);
  }

  ParcelImpact _classifyLinked(
    ParcelSpatialRelation before,
    ParcelSpatialRelation after,
  ) {
    switch (after) {
      case ParcelSpatialRelation.disjoint:
        return _impact(
          before,
          after,
          ParcelImpactKind.linkedNowOutside,
          review: true,
          link: false,
          key: 'parcelImpact.linkedNowOutside',
        );
      case ParcelSpatialRelation.boundaryOnly:
        return _impact(
          before,
          after,
          ParcelImpactKind.linkedBoundaryOnly,
          review: true,
          link: false,
          key: 'parcelImpact.linkedBoundaryOnly',
        );
      case ParcelSpatialRelation.partiallyCovered:
        return _impact(
          before,
          after,
          ParcelImpactKind.linkedPartialCoverage,
          review: true,
          link: false,
          key: 'parcelImpact.linkedPartialCoverage',
        );
      case ParcelSpatialRelation.fullyCovered:
        return _impact(
          before,
          after,
          ParcelImpactKind.retainedCoverage,
          review: false,
          link: false,
          key: 'parcelImpact.retainedCoverage',
        );
    }
  }

  ParcelImpact _classifyOtherParent(
    ParcelSpatialRelation before,
    ParcelSpatialRelation after,
  ) {
    final conflict =
        after == ParcelSpatialRelation.fullyCovered ||
        after == ParcelSpatialRelation.partiallyCovered;
    if (conflict) {
      return _impact(
        before,
        after,
        ParcelImpactKind.conflictWithOtherParent,
        review: true,
        link: false,
        key: 'parcelImpact.conflictWithOtherParent',
      );
    }
    return _impact(
      before,
      after,
      ParcelImpactKind.unaffected,
      review: false,
      link: false,
      key: 'parcelImpact.unaffected',
    );
  }

  ParcelImpact _classifyIndependent(
    ParcelSpatialRelation before,
    ParcelSpatialRelation after,
  ) {
    if (before == ParcelSpatialRelation.disjoint) {
      switch (after) {
        case ParcelSpatialRelation.fullyCovered:
          return _impact(
            before,
            after,
            ParcelImpactKind.newlyCovered,
            review: false,
            link: true,
            key: 'parcelImpact.newlyCovered',
          );
        case ParcelSpatialRelation.partiallyCovered:
          return _impact(
            before,
            after,
            ParcelImpactKind.partiallyCovered,
            review: true,
            link: false,
            key: 'parcelImpact.partiallyCovered',
          );
        case ParcelSpatialRelation.boundaryOnly:
          return _impact(
            before,
            after,
            ParcelImpactKind.boundaryOnlyChange,
            review: false,
            link: false,
            key: 'parcelImpact.boundaryOnlyChange',
          );
        case ParcelSpatialRelation.disjoint:
          return _impact(
            before,
            after,
            ParcelImpactKind.unaffected,
            review: false,
            link: false,
            key: 'parcelImpact.unaffected',
          );
      }
    }

    if (before == ParcelSpatialRelation.boundaryOnly) {
      switch (after) {
        case ParcelSpatialRelation.fullyCovered:
          return _impact(
            before,
            after,
            ParcelImpactKind.newlyCovered,
            review: false,
            link: true,
            key: 'parcelImpact.newlyCovered',
          );
        case ParcelSpatialRelation.partiallyCovered:
          return _impact(
            before,
            after,
            ParcelImpactKind.partiallyCovered,
            review: true,
            link: false,
            key: 'parcelImpact.partiallyCovered',
          );
        case ParcelSpatialRelation.boundaryOnly:
        case ParcelSpatialRelation.disjoint:
          return _impact(
            before,
            after,
            ParcelImpactKind.unaffected,
            review: false,
            link: false,
            key: 'parcelImpact.unaffected',
          );
      }
    }

    if (before == ParcelSpatialRelation.partiallyCovered) {
      switch (after) {
        case ParcelSpatialRelation.fullyCovered:
          return _impact(
            before,
            after,
            ParcelImpactKind.coverageImproved,
            review: false,
            link: true,
            key: 'parcelImpact.coverageImproved',
          );
        case ParcelSpatialRelation.partiallyCovered:
          return _impact(
            before,
            after,
            ParcelImpactKind.partiallyCovered,
            review: true,
            link: false,
            key: 'parcelImpact.partiallyCovered',
          );
        case ParcelSpatialRelation.disjoint:
          return _impact(
            before,
            after,
            ParcelImpactKind.coverageLost,
            review: true,
            link: false,
            key: 'parcelImpact.coverageLost',
          );
        case ParcelSpatialRelation.boundaryOnly:
          return _impact(
            before,
            after,
            ParcelImpactKind.coverageLost,
            review: true,
            link: false,
            key: 'parcelImpact.coverageLost',
          );
      }
    }

    // before == fullyCovered
    switch (after) {
      case ParcelSpatialRelation.fullyCovered:
        return _impact(
          before,
          after,
          ParcelImpactKind.unaffected,
          review: false,
          link: true,
          key: 'parcelImpact.unaffected',
        );
      case ParcelSpatialRelation.partiallyCovered:
        return _impact(
          before,
          after,
          ParcelImpactKind.coverageReduced,
          review: true,
          link: false,
          key: 'parcelImpact.coverageReduced',
        );
      case ParcelSpatialRelation.disjoint:
      case ParcelSpatialRelation.boundaryOnly:
        return _impact(
          before,
          after,
          ParcelImpactKind.coverageLost,
          review: true,
          link: false,
          key: 'parcelImpact.coverageLost',
        );
    }
  }

  ParcelImpact _impact(
    ParcelSpatialRelation before,
    ParcelSpatialRelation after,
    ParcelImpactKind kind, {
    required bool review,
    required bool link,
    required String key,
  }) => ParcelImpact(
    relationBefore: before,
    relationAfter: after,
    kind: kind,
    requiresReview: review,
    linkSuggestion: link,
    reasonKey: key,
  );

  ParcelSpatialRelation _relation(Wgs84MultiPolygon block, Wgs84Polygon plot) {
    final relation = _geometry.relateToMulti(plot, block);
    switch (relation) {
      case Wgs84SpatialRelation.disjoint:
        return ParcelSpatialRelation.disjoint;
      case Wgs84SpatialRelation.boundaryOnly:
        return ParcelSpatialRelation.boundaryOnly;
      case Wgs84SpatialRelation.partiallyOverlap:
      case Wgs84SpatialRelation.contains:
        return ParcelSpatialRelation.partiallyCovered;
      case Wgs84SpatialRelation.containedBy:
      case Wgs84SpatialRelation.equal:
        return ParcelSpatialRelation.fullyCovered;
    }
  }
}
