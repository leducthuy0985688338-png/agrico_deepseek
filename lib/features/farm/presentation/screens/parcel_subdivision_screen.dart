import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/geography/domain/administrative_catalog_repository.dart';
import '../../../../core/geography/domain/entities/administrative_unit.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_subdivision_service.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../../domain/geometry/parcel_subdivision_plan.dart';
import '../../domain/geometry/parcel_closed_outline.dart';

enum _OutlineMode { enclosed, outerEdge }

class ParcelSubdivisionScreen extends StatefulWidget {
  const ParcelSubdivisionScreen({super.key, required this.subject,
    required this.sourceParcelId, required this.service,
    required this.administrativeCatalog});

  final AuthorizationSubject subject;
  final String sourceParcelId;
  final ParcelSubdivisionService service;
  final AdministrativeCatalogRepository administrativeCatalog;

  @override
  State<ParcelSubdivisionScreen> createState() => _ParcelSubdivisionScreenState();
}

class _ParcelSubdivisionScreenState extends State<ParcelSubdivisionScreen> {
  late final Future<(LandParcel, String?)> source = _load();
  final names = <TextEditingController>[TextEditingController()];
  final retiredNames = <TextEditingController>[];
  final cuts = <ParcelSubdivisionCut>[];
  Wgs84Vertex? start;
  final waypoints = <Wgs84Vertex>[];
  ParcelSubdivisionPreview? preview;
  String? previewError;
  bool saving = false;
  int selectedFragment = 0;
  int cutRevision = 0;
  _OutlineMode outlineMode = _OutlineMode.enclosed;

  Future<(LandParcel, String?)> _load() async {
    final parcel = await widget.service.parcels.getById(
      farmId: widget.subject.farmId, id: widget.sourceParcelId);
    if (parcel == null) {
      throw StateError('Source parcel is missing.');
    }
    final units = await widget.administrativeCatalog.all();
    final byId = {for (final unit in units) unit.id: unit};
    final matches = units.where((v) {
      if (!v.active || v.level != AdministrativeLevel.village ||
          v.code != parcel.villageCode) {
        return false;
      }
      final d = byId[v.parentId];
      final p = byId[d?.parentId];
      final c = byId[p?.parentId];
      return d?.active == true && p?.active == true && c?.active == true &&
          d?.code == parcel.districtCode &&
          p?.code == parcel.provinceCode && c?.code == parcel.countryCode;
    }).toList();
    return (parcel, matches.length == 1 ? matches.single.id : null);
  }

  @override
  void dispose() {
    for (final name in names) { name.dispose(); }
    for (final name in retiredNames) { name.dispose(); }
    super.dispose();
  }

  void _resetDraft() => setState(() {
    cutRevision++;
    start = null;
    waypoints.clear();
    previewError = null;
  });

  void _resetAll() {
    setState(() {
      cutRevision++;
      start = null;
      waypoints.clear();
      cuts.clear();
      preview = null;
      previewError = null;
      selectedFragment = 0;
      retiredNames.addAll(names.skip(1));
      names.removeRange(1, names.length);
    });
  }

  void _selectFragment(int index) => setState(() {
    cutRevision++;
    selectedFragment = index;
    start = null;
    waypoints.clear();
    previewError = null;
  });

  void _selectMode(_OutlineMode mode) => setState(() {
    cutRevision++;
    outlineMode = mode;
    start = null;
    waypoints.clear();
    previewError = null;
  });

  Future<void> _choose(LandParcel parcel, Offset point, Size size) async {
    final fragment = preview?.boundaries[selectedFragment] ?? parcel.boundary;
    final projection = _Projection(fragment, size);
    final candidate = outlineMode == _OutlineMode.outerEdge
        ? projection.nearestOuterBoundary(point, tolerance: 14)
        : projection.nearestHoleBoundary(point, tolerance: 14);
    if (start == null) {
      if (outlineMode == _OutlineMode.outerEdge && candidate == null) return;
      if (candidate == null && !projection.contains(point)) return;
      setState(() {
        start = candidate ?? projection.coordinate(point);
        waypoints.clear();
        previewError = null;
      });
      return;
    }
    final hasInterior = outlineMode == _OutlineMode.enclosed ||
        _hasInterior(projection);
    final closeToStart = hasInterior && waypoints.length >= 2 &&
        (point - projection.position(start!)).distance <= 24;
    if (closeToStart) {
      await _finish(parcel, fragment);
      return;
    }
    if (candidate == null && !projection.contains(point)) return;
    setState(() {
      waypoints.add(candidate ?? projection.coordinate(point));
      previewError = null;
    });
  }

  bool _hasInterior(_Projection projection) => waypoints.any((vertex) =>
    projection.nearestBoundary(projection.position(vertex),
      tolerance: 1) == null);

  Future<void> _finish(LandParcel parcel, Wgs84Polygon fragment) async {
    if (start == null) return;
    final revision = ++cutRevision;
    try {
      final traced = [start!, ...waypoints];
      final operation = outlineMode == _OutlineMode.outerEdge
          ? ParcelSubdivisionCut(fragmentIndex: selectedFragment,
              path: const ParcelClosedOutline().interiorCut(fragment, traced))
          : ParcelSubdivisionCut.enclosed(fragmentIndex: selectedFragment,
              polygon: Wgs84Polygon.fromVertices(traced));
      final next = [...cuts, operation];
      final result = await widget.service.previewPlan(
        subject: widget.subject, sourceParcelId: parcel.id, cuts: next);
      if (mounted && revision == cutRevision) {
        setState(() {
          cuts.add(next.last);
          preview = result;
          names.insert(selectedFragment + 1, TextEditingController());
          start = null;
          waypoints.clear();
          previewError = null;
        });
      }
    } catch (error) {
      if (mounted && revision == cutRevision) {
        setState(() {
          final summary = AppLocalizations.of(context)
              .text('subdivision.invalidCut');
          previewError = error is FormatException || error is StateError
              ? '$summary\n$error' : summary;
        });
      }
    }
  }

  Future<void> _save(LandParcel source, String villageId) async {
    final l10n = AppLocalizations.of(context);
    if (cuts.isEmpty || preview == null || saving || start != null ||
        names.any((name) => name.text.trim().isEmpty)) return;
    setState(() => saving = true);
    try {
      await widget.service.savePlan(
        subject: widget.subject, sourceParcelId: source.id,
        villageId: villageId, expectedBoundaryVersion: source.boundaryVersion,
        cuts: List.of(cuts), names: names.map((name) => name.text).toList());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.text('subdivision.saveFailed'))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('subdivision.title'))),
      body: FutureBuilder<(LandParcel, String?)>(future: source,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('subdivision.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (parcel, villageId) = snapshot.data!;
          final fragments = preview?.boundaries ?? [parcel.boundary];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${parcel.parcelCode} · ${parcel.areaM2.toStringAsFixed(1)} m²'),
            const SizedBox(height: 8),
            Text(l10n.text('subdivision.instruction')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ChoiceChip(key: const Key('subdivision-mode-enclosed'),
                label: Text(l10n.text('subdivision.enclosedMode')),
                selected: outlineMode == _OutlineMode.enclosed,
                onSelected: (_) => _selectMode(_OutlineMode.enclosed)),
              ChoiceChip(key: const Key('subdivision-mode-outer-edge'),
                label: Text(l10n.text('subdivision.edgeMode')),
                selected: outlineMode == _OutlineMode.outerEdge,
                onSelected: (_) => _selectMode(_OutlineMode.outerEdge)),
            ]),
            if (cuts.isNotEmpty) Wrap(spacing: 8, children: [
              for (var i = 0; i < fragments.length; i++)
                ChoiceChip(key: Key('subdivision-fragment-$i'),
                  label: Text('${l10n.text('subdivision.fragment')} ${i + 1}'),
                  selected: i == selectedFragment,
                  onSelected: (_) => _selectFragment(i)),
            ]),
            Text(l10n.text('subdivision.editSelected')),
            SizedBox(height: 420, child: LayoutBuilder(builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                key: const Key('subdivision-map'),
                onTapDown: (details) => _choose(parcel, details.localPosition, size),
                child: CustomPaint(size: size,
                  painter: _CutPainter(fragments[selectedFragment],
                    [?start, ...waypoints], null, 0)),
              );
            })),
            if (preview != null) ...[
              Text(l10n.text('subdivision.overview')),
              SizedBox(height: 180, child: LayoutBuilder(builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                return GestureDetector(
                  key: const Key('subdivision-overview'),
                  onTapDown: (details) {
                    final projection = _Projection(parcel.boundary, size);
                    for (var i = 0; i < fragments.length; i++) {
                      if (projection.containsPolygon(
                          fragments[i], details.localPosition)) {
                        _selectFragment(i);
                        return;
                      }
                    }
                  },
                  child: CustomPaint(size: size,
                    painter: _CutPainter(parcel.boundary, const [],
                      fragments, selectedFragment)),
                );
              })),
            ],
            if (start != null) Text(l10n.text('subdivision.autoFinish')),
            if (start != null && waypoints.length >= 2)
              TextButton.icon(
                key: const Key('subdivision-close-outline'),
                onPressed: () => _finish(parcel, fragments[selectedFragment]),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(l10n.text('subdivision.closeOutline')),
              ),
            if (waypoints.isNotEmpty) TextButton.icon(
              key: const Key('subdivision-undo-point'),
              onPressed: () => setState(() => waypoints.removeLast()),
              icon: const Icon(Icons.undo),
              label: Text(l10n.text('subdivision.undoPoint')),
            ),
            if (start != null) TextButton.icon(
              key: const Key('subdivision-reset-cut'),
              onPressed: _resetDraft,
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.text('subdivision.reset')),
            ),
            if (cuts.isNotEmpty) TextButton.icon(
              key: const Key('subdivision-reset-all'),
              onPressed: _resetAll,
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.text('subdivision.resetAll')),
            ),
            if (previewError != null) Text(previewError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (preview != null) ...[
              Text('${l10n.text('subdivision.preview')}: ${fragments.length}'),
              Text(l10n.text('subdivision.closedBoundary')),
              for (var i = 0; i < fragments.length; i++)
                Text('${l10n.text('subdivision.fragment')} ${i + 1}: '
                  '${preview!.areasM2[i].toStringAsFixed(1)} m²'),
            ],
            if (villageId == null) Text(l10n.text('subdivision.locationRequired')),
            const SizedBox(height: 12),
            if (cuts.isNotEmpty)
              for (var i = 0; i < names.length; i++)
                TextField(key: Key('subdivision-name-$i'),
                  controller: names[i],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText:
                    '${l10n.text('subdivision.fragment')} ${i + 1}')),
            const SizedBox(height: 12),
            FilledButton(key: const Key('subdivision-save'),
              onPressed: preview == null || villageId == null || saving ||
                  start != null || names.any((n) => n.text.trim().isEmpty)
                  ? null : () => _save(parcel, villageId),
              child: Text(l10n.text('subdivision.save'))),
          ]);
        }),
    );
  }
}

class _Projection {
  _Projection(this.polygon, this.size) : vertices = polygon.vertices {
    final lons = vertices.map((v) => v.longitude);
    final lats = vertices.map((v) => v.latitude);
    left = lons.reduce(math.min);
    right = lons.reduce(math.max);
    bottom = lats.reduce(math.min);
    top = lats.reduce(math.max);
    scale = math.min((size.width - 40) / math.max(right - left, 1e-12),
      (size.height - 40) / math.max(top - bottom, 1e-12));
  }

  final Size size;
  final Wgs84Polygon polygon;
  final List<Wgs84Vertex> vertices;
  late final double left, right, bottom, top, scale;

  Offset position(Wgs84Vertex vertex) => Offset(
    (vertex.longitude - (left + right) / 2) * scale + size.width / 2,
    ((top + bottom) / 2 - vertex.latitude) * scale + size.height / 2,
  );

  Wgs84Vertex coordinate(Offset point) => Wgs84Vertex(
    longitude: (point.dx - size.width / 2) / scale + (left + right) / 2,
    latitude: (size.height / 2 - point.dy) / scale + (top + bottom) / 2,
  );

  bool contains(Offset point) => containsPolygon(polygon, point);

  bool containsPolygon(Wgs84Polygon polygon, Offset point) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in [polygon.vertices, ...polygon.holes]) {
      for (var i = 0; i < ring.length; i++) {
        final vertex = position(ring[i]);
        if (i == 0) { path.moveTo(vertex.dx, vertex.dy); }
        else { path.lineTo(vertex.dx, vertex.dy); }
      }
      path.close();
    }
    return path.contains(point);
  }

  Wgs84Vertex? nearestBoundary(Offset point, {double tolerance = 24}) =>
    _nearestBoundary(point, [vertices, ...polygon.holes], tolerance);

  Wgs84Vertex? nearestOuterBoundary(Offset point,
      {double tolerance = 24}) =>
    _nearestBoundary(point, [vertices], tolerance);

  Wgs84Vertex? nearestHoleBoundary(Offset point,
      {double tolerance = 24}) =>
    _nearestBoundary(point, polygon.holes, tolerance);

  Wgs84Vertex? _nearestBoundary(Offset point,
      List<List<Wgs84Vertex>> rings, double tolerance) {
    var distance = double.infinity;
    Offset? nearest;
    for (final ring in rings) {
      for (var i = 0; i < ring.length - 1; i++) {
        final a = position(ring[i]);
        final b = position(ring[i + 1]);
        final direction = b - a;
        final length2 = direction.dx * direction.dx + direction.dy * direction.dy;
        if (length2 <= 0) continue;
        final t = ((point.dx - a.dx) * direction.dx +
            (point.dy - a.dy) * direction.dy) / length2;
        final candidate = a + direction * t.clamp(0.0, 1.0).toDouble();
        final d = (candidate - point).distance;
        if (d < distance) { distance = d; nearest = candidate; }
      }
    }
    return distance <= tolerance && nearest != null
        ? coordinate(nearest) : null;
  }
}

class _CutPainter extends CustomPainter {
  const _CutPainter(this.source, this.cut, this.children, this.selected);
  final Wgs84Polygon source;
  final List<Wgs84Vertex> cut;
  final List<Wgs84Polygon>? children;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    final projection = _Projection(source, size);
    Path outline(Wgs84Polygon polygon) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in [polygon.vertices, ...polygon.holes]) {
        for (var i = 0; i < ring.length; i++) {
          final point = projection.position(ring[i]);
          if (i == 0) { path.moveTo(point.dx, point.dy); }
          else { path.lineTo(point.dx, point.dy); }
        }
        path.close();
      }
      return path;
    }
    canvas.drawColor(const Color(0xfff1f6ee), BlendMode.src);
    if (children != null) {
      for (var i = 0; i < children!.length; i++) {
        canvas.drawPath(outline(children![i]), Paint()
          ..color = (i == selected
            ? const Color(0xffa9d99d) : const Color(0xffe7dfac)));
        canvas.drawPath(outline(children![i]), Paint()
          ..color = (i == selected
            ? const Color(0xff146b32) : const Color(0xff795d25))
          ..style = PaintingStyle.stroke ..strokeWidth = 3);
      }
    }
    canvas.drawPath(outline(source), Paint()
      ..color = const Color(0xff217a3b)..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    if (cut.length >= 3) {
      final draft = Path()..moveTo(projection.position(cut.first).dx,
        projection.position(cut.first).dy);
      for (final vertex in cut.skip(1)) {
        final position = projection.position(vertex);
        draft.lineTo(position.dx, position.dy);
      }
      draft.close();
      canvas.save();
      canvas.clipPath(outline(source));
      canvas.drawPath(draft, Paint()..color = const Color(0x55ff7a32));
      canvas.restore();
      canvas.drawPath(draft, Paint()..color = const Color(0xffe65d16)
        ..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    for (var i = 0; i < cut.length; i++) {
      final point = projection.position(cut[i]);
      canvas.drawCircle(point, 6, Paint()..color = Colors.deepOrange);
      if (i > 0) {
        canvas.drawLine(projection.position(cut[i - 1]), point,
          Paint()..color = Colors.deepOrange..strokeWidth = 3);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CutPainter old) =>
      old.source != source || old.cut != cut ||
      old.children != children || old.selected != selected;
}
