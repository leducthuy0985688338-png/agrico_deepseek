import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_multi_polygon.dart';
import 'package:agrico_deepseek/features/farm/domain/parcel/parcel_impact_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

Wgs84Polygon box(double x, double y, double w, double h) =>
    Wgs84Polygon.fromVertices([
      Wgs84Vertex(latitude: y, longitude: x),
      Wgs84Vertex(latitude: y, longitude: x + w),
      Wgs84Vertex(latitude: y + h, longitude: x + w),
      Wgs84Vertex(latitude: y + h, longitude: x),
    ]);

Wgs84MultiPolygon multi(Wgs84Polygon first, [Wgs84Polygon? second]) =>
    Wgs84MultiPolygon.fromPolygons(second == null ? [first] : [first, second]);

void main() {
  const classifier = ParcelImpactClassifier();

  // ---- independent ----

  test('independent disjoint: unaffected', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 5, 5)),
      blockAfter: multi(box(0, 0, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(10, 10, 1, 1),
      confirmedParentBlockId: null,
    );
    expect(impact.kind, ParcelImpactKind.unaffected);
    expect(impact.requiresReview, isFalse);
    expect(impact.linkSuggestion, isFalse);
  });

  test('independent create -> full: newlyCovered with linkSuggestion', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: null,
      blockAfter: multi(box(0, 0, 10, 10)),
      plotId: 'P1',
      plotGeometry: box(1, 1, 1, 1),
      confirmedParentBlockId: null,
    );
    expect(impact.relationBefore, ParcelSpatialRelation.disjoint);
    expect(impact.relationAfter, ParcelSpatialRelation.fullyCovered);
    expect(impact.kind, ParcelImpactKind.newlyCovered);
    expect(impact.requiresReview, isFalse);
    expect(impact.linkSuggestion, isTrue);
  });

  test(
    'independent boundaryOnly -> full: newlyCovered with linkSuggestion',
    () {
      final impact = classifier.classify(
        changedBlockId: 'B1',
        blockBefore: multi(box(0, 0, 5, 5)),
        blockAfter: multi(box(0, 0, 10, 10)),
        plotId: 'P1',
        plotGeometry: box(5, 1, 1, 1),
        confirmedParentBlockId: null,
      );
      expect(impact.relationBefore, ParcelSpatialRelation.boundaryOnly);
      expect(impact.relationAfter, ParcelSpatialRelation.fullyCovered);
      expect(impact.kind, ParcelImpactKind.newlyCovered);
      expect(impact.requiresReview, isFalse);
      expect(impact.linkSuggestion, isTrue);
    },
  );

  test(
    'independent disjoint -> partial: partiallyCovered, review true, no link',
    () {
      final impact = classifier.classify(
        changedBlockId: 'B1',
        blockBefore: null,
        blockAfter: multi(box(0, 0, 5, 5)),
        plotId: 'P1',
        plotGeometry: box(3, 3, 5, 5),
        confirmedParentBlockId: null,
      );
      expect(impact.kind, ParcelImpactKind.partiallyCovered);
      expect(impact.requiresReview, isTrue);
      expect(impact.linkSuggestion, isFalse);
    },
  );

  test('independent full -> partial: coverageReduced requires review', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(0, 0, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(3, 3, 3, 3),
      confirmedParentBlockId: null,
    );
    expect(impact.relationBefore, ParcelSpatialRelation.fullyCovered);
    expect(impact.relationAfter, ParcelSpatialRelation.partiallyCovered);
    expect(impact.kind, ParcelImpactKind.coverageReduced);
    expect(impact.requiresReview, isTrue);
  });

  test('independent full -> disjoint: coverageLost requires review', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(50, 50, 10, 10)),
      plotId: 'P1',
      plotGeometry: box(1, 1, 1, 1),
      confirmedParentBlockId: null,
    );
    expect(impact.kind, ParcelImpactKind.coverageLost);
    expect(impact.requiresReview, isTrue);
  });

  test('independent full -> full: linkSuggestion true', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(0, 0, 10, 10)),
      plotId: 'P1',
      plotGeometry: box(1, 1, 1, 1),
      confirmedParentBlockId: null,
    );
    expect(impact.kind, ParcelImpactKind.unaffected);
    expect(impact.requiresReview, isFalse);
    expect(impact.linkSuggestion, isTrue);
  });

  test('independent partial -> full: linkSuggestion true', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 5, 5)),
      blockAfter: multi(box(0, 0, 10, 10)),
      plotId: 'P1',
      plotGeometry: box(3, 3, 3, 3),
      confirmedParentBlockId: null,
    );
    expect(impact.kind, ParcelImpactKind.coverageImproved);
    expect(impact.linkSuggestion, isTrue);
    expect(impact.requiresReview, isFalse);
  });

  test('independent partial -> partial: requiresReview true, no link', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 5, 5)),
      blockAfter: multi(box(0, 0, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(3, 3, 5, 5),
      confirmedParentBlockId: null,
    );
    expect(impact.kind, ParcelImpactKind.partiallyCovered);
    expect(impact.requiresReview, isTrue);
    expect(impact.linkSuggestion, isFalse);
  });

  test('independent partial -> boundaryOnly: coverageLost requires review', () {
    // Thửa 0..5 rộng hơn Lô trước 0..3 → partial.
    // Lô sau 5..10 chỉ chạm cạnh x=5 của Thửa → boundaryOnly.
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 3, 5)),
      blockAfter: multi(box(5, 0, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(0, 0, 5, 5),
      confirmedParentBlockId: null,
    );
    expect(impact.relationBefore, ParcelSpatialRelation.partiallyCovered);
    expect(impact.relationAfter, ParcelSpatialRelation.boundaryOnly);
    expect(impact.kind, ParcelImpactKind.coverageLost);
    expect(impact.requiresReview, isTrue);
    expect(impact.linkSuggestion, isFalse);
  });

  // ---- linked ----

  test('linked full -> full: retainedCoverage, no review', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(0, 0, 10, 10)),
      plotId: 'P1',
      plotGeometry: box(1, 1, 1, 1),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.kind, ParcelImpactKind.retainedCoverage);
    expect(impact.requiresReview, isFalse);
  });

  test('linked full -> disjoint: linkedNowOutside keeps relationBefore', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(50, 50, 10, 10)),
      plotId: 'P1',
      plotGeometry: box(1, 1, 1, 1),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.relationBefore, ParcelSpatialRelation.fullyCovered);
    expect(impact.relationAfter, ParcelSpatialRelation.disjoint);
    expect(impact.kind, ParcelImpactKind.linkedNowOutside);
    expect(impact.requiresReview, isTrue);
  });

  test('linked partial -> partial: linkedPartialCoverage requires review', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(0, 0, 10, 10)),
      plotId: 'P1',
      plotGeometry: box(8, 8, 5, 5),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.kind, ParcelImpactKind.linkedPartialCoverage);
    expect(impact.requiresReview, isTrue);
  });

  test('linked full -> partial: linkedPartialCoverage requires review', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(0, 0, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(3, 3, 3, 3),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.relationBefore, ParcelSpatialRelation.fullyCovered);
    expect(impact.relationAfter, ParcelSpatialRelation.partiallyCovered);
    expect(impact.kind, ParcelImpactKind.linkedPartialCoverage);
    expect(impact.requiresReview, isTrue);
  });

  test('linked full -> boundaryOnly: linkedBoundaryOnly requires review', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 10, 10)),
      blockAfter: multi(box(5, 0, 5, 10)),
      plotId: 'P1',
      plotGeometry: box(0, 0, 5, 5),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.kind, ParcelImpactKind.linkedBoundaryOnly);
    expect(impact.requiresReview, isTrue);
  });

  test('linked wrong from the start still requires review', () {
    final impact = classifier.classify(
      changedBlockId: 'B1',
      blockBefore: multi(box(0, 0, 5, 5)),
      blockAfter: multi(box(0, 0, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(3, 3, 5, 5),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.kind, ParcelImpactKind.linkedPartialCoverage);
    expect(impact.requiresReview, isTrue);
  });

  // ---- other parent ----

  test('other parent, new block fully covers: conflictWithOtherParent', () {
    final impact = classifier.classify(
      changedBlockId: 'B2',
      blockBefore: multi(box(0, 0, 5, 5)),
      blockAfter: multi(box(0, 0, 20, 20)),
      plotId: 'P1',
      plotGeometry: box(1, 1, 1, 1),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.kind, ParcelImpactKind.conflictWithOtherParent);
    expect(impact.requiresReview, isTrue);
  });

  test('other parent, new block partial: conflictWithOtherParent', () {
    final impact = classifier.classify(
      changedBlockId: 'B2',
      blockBefore: null,
      blockAfter: multi(box(0, 0, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(3, 3, 5, 5),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.kind, ParcelImpactKind.conflictWithOtherParent);
    expect(impact.requiresReview, isTrue);
  });

  test('other parent, new block disjoint: unaffected', () {
    final impact = classifier.classify(
      changedBlockId: 'B2',
      blockBefore: null,
      blockAfter: multi(box(50, 50, 5, 5)),
      plotId: 'P1',
      plotGeometry: box(1, 1, 1, 1),
      confirmedParentBlockId: 'B1',
    );
    expect(impact.kind, ParcelImpactKind.unaffected);
    expect(impact.requiresReview, isFalse);
  });
}
