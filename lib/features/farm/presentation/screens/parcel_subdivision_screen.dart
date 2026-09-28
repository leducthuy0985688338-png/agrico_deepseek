import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/geography/domain/administrative_catalog_repository.dart';
import '../../../../core/geography/domain/entities/administrative_unit.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_subdivision_service.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../../domain/geometry/parcel_subdivision_plan.dart';

class ParcelSubdivisionScreen extends StatefulWidget {
  const ParcelSubdivisionScreen({super.key, required this.subject,
    required this.sourceParcelId, required this.service,
    required this.administrativeCatalog, this.useSchematicMap = false});

  final AuthorizationSubject subject;
  final String sourceParcelId;
  final ParcelSubdivisionService service;
  final AdministrativeCatalogRepository administrativeCatalog;
  /// The schematic canvas is used by widget tests without a platform map.
  final bool useSchematicMap;

  @override
  State<ParcelSubdivisionScreen> createState() => _ParcelSubdivisionScreenState();
}

class _ParcelSubdivisionScreenState extends State<ParcelSubdivisionScreen> {
  late final Future<(LandParcel, String?)> source = _load();
  final names = <TextEditingController>[];
  final retiredNames = <TextEditingController>[];
  final cuts = <ParcelSubdivisionCut>[];
  Wgs84Vertex? start;
  final waypoints = <Wgs84Vertex>[];
  ParcelSubdivisionPreview? preview;
  String? previewError;
  bool saving = false;
  int cutRevision = 0;
  bool showLandBlock = true;
  bool showFieldPlots = true;

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
      retiredNames.addAll(names);
      names.clear();
    });
  }

  Future<void> _choose(LandParcel parcel, Offset point, Size size) async {
    final projection = _Projection(parcel.boundary, size);
    await _chooseVertex(parcel, projection.coordinate(point),
      closeToStart: start != null && waypoints.length >= 2 &&
        (point - projection.position(start!)).distance <= 24);
  }

  Future<void> _chooseVertex(LandParcel parcel, Wgs84Vertex vertex,
      {bool closeToStart = false}) async {
    if (start == null) {
      setState(() {
        start = vertex;
        waypoints.clear();
        previewError = null;
      });
      return;
    }
    if (closeToStart) {
      await _finish(parcel);
      return;
    }
    setState(() {
      waypoints.add(vertex);
      previewError = null;
    });
  }

  Future<void> _finish(LandParcel parcel) async {
    if (start == null) return;
    final revision = ++cutRevision;
    try {
      final traced = [start!, ...waypoints];
      final operation = ParcelSubdivisionCut.enclosed(fragmentIndex: 0,
        polygon: Wgs84Polygon.fromVertices(traced));
      final next = [...cuts, operation];
      final result = await widget.service.previewPlan(
        subject: widget.subject, sourceParcelId: parcel.id, cuts: next,
        independentSketches: true);
      if (mounted && revision == cutRevision) {
        setState(() {
          cuts.add(next.last);
          preview = result;
          names.add(TextEditingController());
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
        names.any((name) => name.text.trim().isEmpty)) {
      return;
    }
    setState(() => saving = true);
    try {
      await widget.service.savePlan(
        subject: widget.subject, sourceParcelId: source.id,
        villageId: villageId, expectedBoundaryVersion: source.boundaryVersion,
        cuts: List.of(cuts), names: names.map((name) => name.text).toList(),
        independentSketches: true);
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

  Widget _satelliteMap(LandParcel parcel, List<Wgs84Polygon> sketches) {
    LatLng point(Wgs84Vertex vertex) =>
      LatLng(vertex.latitude, vertex.longitude);
    final vertices = parcel.boundary.vertices;
    final south = vertices.map((v) => v.latitude).reduce(math.min);
    final north = vertices.map((v) => v.latitude).reduce(math.max);
    final west = vertices.map((v) => v.longitude).reduce(math.min);
    final east = vertices.map((v) => v.longitude).reduce(math.max);
    final draft = [?start, ...waypoints];
    final boundaries = <Polygon>{
      if (showLandBlock) Polygon(polygonId: const PolygonId('source-area'),
        points: vertices.map(point).toList(),
        holes: parcel.boundary.holes.map((ring) =>
          ring.map(point).toList()).toList(),
        strokeColor: Colors.green.shade800, strokeWidth: 3,
        fillColor: Colors.green.withValues(alpha: 0.08)),
      for (var i = 0; showFieldPlots && i < sketches.length; i++)
        Polygon(polygonId: PolygonId('field-plot-$i'),
          points: sketches[i].vertices.map(point).toList(),
          strokeColor: Colors.orange.shade900, strokeWidth: 3,
          fillColor: Colors.orange.withValues(alpha: 0.22)),
    };
    if (draft.length >= 3) {
      boundaries.add(Polygon(polygonId: const PolygonId('draft'),
        points: draft.map(point).toList(),
        strokeColor: Colors.deepOrange, strokeWidth: 3,
        fillColor: Colors.deepOrange.withValues(alpha: 0.25)));
    }
    return GoogleMap(
      key: const Key('subdivision-satellite-map'),
      mapType: MapType.satellite,
      initialCameraPosition: CameraPosition(
        target: point(parcel.centroid), zoom: 16),
      onMapCreated: (controller) {
        if (south < north && west < east) {
          controller.animateCamera(CameraUpdate.newLatLngBounds(
            LatLngBounds(southwest: LatLng(south, west),
              northeast: LatLng(north, east)), 48));
        }
      },
      onTap: (location) => _chooseVertex(parcel,
        Wgs84Vertex(latitude: location.latitude,
          longitude: location.longitude),
        closeToStart: start != null && waypoints.length >= 2 &&
          (location.latitude - start!.latitude).abs() < 0.000015 &&
          (location.longitude - start!.longitude).abs() < 0.000015),
      polygons: boundaries,
      markers: {
        for (var i = 0; i < draft.length; i++)
          Marker(markerId: MarkerId('draft-$i'), position: point(draft[i])),
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
    );
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
          final fragments = preview?.boundaries ?? <Wgs84Polygon>[];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${parcel.parcelCode} · ${parcel.areaM2.toStringAsFixed(1)} m²'),
            const SizedBox(height: 8),
            Text(l10n.text('subdivision.instruction')),
            Text(l10n.text('subdivision.editSelected')),
            if (!widget.useSchematicMap) Wrap(spacing: 8, children: [
              FilterChip(label: Text(l10n.text('parcel.layer.landBlock')),
                selected: showLandBlock,
                onSelected: (value) => setState(() => showLandBlock = value)),
              FilterChip(label: Text(l10n.text('parcel.layer.fieldPlot')),
                selected: showFieldPlots,
                onSelected: (value) => setState(() => showFieldPlots = value)),
            ]),
            if (!widget.useSchematicMap)
              SizedBox(height: 480, child: _satelliteMap(parcel, fragments))
            else SizedBox(height: 420, child: LayoutBuilder(builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                key: const Key('subdivision-map'),
                onTapDown: (details) => _choose(parcel, details.localPosition, size),
                child: CustomPaint(size: size,
                  painter: _CutPainter(parcel.boundary,
                    [?start, ...waypoints], fragments, -1)),
              );
            })),
            if (widget.useSchematicMap && preview != null) ...[
              Text(l10n.text('subdivision.overview')),
              SizedBox(height: 180, child: LayoutBuilder(builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                return GestureDetector(
                  key: const Key('subdivision-overview'),
                  child: CustomPaint(size: size,
                    painter: _CutPainter(parcel.boundary, const [],
                      fragments, -1)),
                );
              })),
            ],
            if (start != null) Text(l10n.text('subdivision.autoFinish')),
            if (start != null && waypoints.length >= 2)
              TextButton.icon(
                key: const Key('subdivision-close-outline'),
              onPressed: () => _finish(parcel),
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
              for (var i = 0; i < fragments.length; i++)
                Text('${l10n.text('subdivision.fragment')} ${i + 1}: '
                  '${preview!.areasM2[i].toStringAsFixed(1)} m² · '
                  '${preview!.perimetersM[i].toStringAsFixed(1)} m'),
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
      canvas.drawPath(draft, Paint()..color = const Color(0x55ff7a32));
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
