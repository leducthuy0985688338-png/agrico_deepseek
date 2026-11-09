import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/geography/domain/administrative_catalog_repository.dart';
import '../../../../core/geography/domain/entities/administrative_unit.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_subdivision_service.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../../domain/geometry/parcel_subdivision_plan.dart';
import '../../../../core/catalog/company_catalog.dart';
import '../../../../core/catalog/catalog_value_picker.dart';

class ParcelSubdivisionScreen extends StatefulWidget {
  const ParcelSubdivisionScreen({
    super.key,
    required this.subject,
    required this.sourceParcelId,
    required this.service,
    required this.administrativeCatalog,
    this.useSchematicMap = false,
    this.productionPlots = false,
    this.catalog,
  });

  final CompanyCatalogService? catalog;
  final AuthorizationSubject subject;
  final String sourceParcelId;
  final ParcelSubdivisionService service;
  final AdministrativeCatalogRepository administrativeCatalog;

  /// The schematic canvas is used by widget tests without a platform map.
  final bool useSchematicMap;
  final bool productionPlots;

  @override
  State<ParcelSubdivisionScreen> createState() =>
      _ParcelSubdivisionScreenState();
}

class _ParcelSubdivisionScreenState extends State<ParcelSubdivisionScreen> {
  late final Future<(LandParcel, String?)> source = _load();
  final _drawingTransform = TransformationController();
  bool get _useSchematicMap => widget.useSchematicMap || widget.productionPlots;

  void _zoomDrawing(double factor, Size size) {
    final current = _drawingTransform.value;
    final scale = current.getMaxScaleOnAxis();
    final nextScale = (scale * factor).clamp(1.0, 12.0).toDouble();
    final center = Offset(size.width / 2, size.height / 2);
    final scene = _drawingTransform.toScene(center);
    _drawingTransform.value = Matrix4.identity()
      ..setEntry(0, 0, nextScale)
      ..setEntry(1, 1, nextScale)
      ..setEntry(0, 3, center.dx - scene.dx * nextScale)
      ..setEntry(1, 3, center.dy - scene.dy * nextScale);
  }

  final names = <TextEditingController>[];
  final retiredNames = <TextEditingController>[];
  final details = <_SketchDraft>[];
  final retiredDetails = <_SketchDraft>[];
  final cuts = <ParcelSubdivisionCut>[];
  Wgs84Vertex? start;
  final waypoints = <Wgs84Vertex>[];
  ParcelSubdivisionPreview? preview;
  String? previewError;
  bool saving = false;
  int cutRevision = 0;
  bool showLandBlock = true;
  bool showFieldPlots = true;
  GoogleMapController? mapController;
  List<Offset> draftScreenPoints = const [];
  List<List<Offset>> sourceScreenRings = const [];
  final completedScreenRings = <List<Offset>>[];
  int projectionRevision = 0;
  Offset? lastMapPointer;
  bool previewing = false;

  int _layerOrdinal(int index) {
    final layer = details[index].layer;
    return details
        .take(index + 1)
        .where((entry) => entry.layer == layer)
        .length;
  }

  String _sketchLabel(AppLocalizations l10n, int index) =>
      '${l10n.text('parcel.layer.${details[index].layer.name}')} '
      '${_layerOrdinal(index)}';

  Future<void> _refreshDraftScreenPoints() async {
    final controller = mapController;
    final vertices = [?start, ...waypoints];
    final revision = ++projectionRevision;
    if (controller == null) return;
    try {
      Future<List<ScreenCoordinate>> project(List<Wgs84Vertex> ring) =>
          Future.wait(
            ring.map(
              (vertex) => controller.getScreenCoordinate(
                LatLng(vertex.latitude, vertex.longitude),
              ),
            ),
          );
      final parcel = (await source).$1;
      final sourceCoordinates = await Future.wait(
        [parcel.boundary.vertices, ...parcel.boundary.holes].map(project),
      );
      final coordinates = await project(vertices);
      final completed = await Future.wait(
        cuts.map((cut) => project(cut.enclosedPolygon!.vertices)),
      );
      if (!mounted || revision != projectionRevision) return;
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      Offset position(ScreenCoordinate coordinate) =>
          Offset(coordinate.x / pixelRatio, coordinate.y / pixelRatio);
      setState(() {
        sourceScreenRings = sourceCoordinates
            .map((ring) => ring.map(position).toList())
            .toList();
        draftScreenPoints = coordinates.map(position).toList();
        completedScreenRings
          ..clear()
          ..addAll(completed.map((ring) => ring.map(position).toList()));
      });
    } catch (_) {
      // The map may be rebuilding while the camera moves; retry when idle.
    }
  }

  Future<(LandParcel, String?)> _load() async {
    final parcel = await widget.service.parcels.getById(
      farmId: widget.subject.farmId,
      id: widget.sourceParcelId,
    );
    if (parcel == null) {
      throw StateError('Source parcel is missing.');
    }
    if (widget.productionPlots) {
      return (parcel, null);
    }
    final units = await widget.administrativeCatalog.all();
    final byId = {for (final unit in units) unit.id: unit};
    final matches = units.where((v) {
      if (!v.active ||
          v.level != AdministrativeLevel.village ||
          v.code != parcel.villageCode) {
        return false;
      }
      final d = byId[v.parentId];
      final p = byId[d?.parentId];
      final c = byId[p?.parentId];
      return d?.active == true &&
          p?.active == true &&
          c?.active == true &&
          d?.code == parcel.districtCode &&
          p?.code == parcel.provinceCode &&
          c?.code == parcel.countryCode;
    }).toList();
    return (parcel, matches.length == 1 ? matches.single.id : null);
  }

  @override
  void dispose() {
    _drawingTransform.dispose();
    for (final name in names) {
      name.dispose();
    }
    for (final name in retiredNames) {
      name.dispose();
    }
    for (final entry in details) {
      entry.dispose();
    }
    for (final entry in retiredDetails) {
      entry.dispose();
    }
    super.dispose();
  }

  void _resetDraft() => setState(() {
    cutRevision++;
    start = null;
    waypoints.clear();
    projectionRevision++;
    draftScreenPoints = const [];
    previewError = null;
    previewing = false;
  });

  void _resetAll() {
    setState(() {
      cutRevision++;
      start = null;
      waypoints.clear();
      projectionRevision++;
      draftScreenPoints = const [];
      completedScreenRings.clear();
      cuts.clear();
      preview = null;
      previewError = null;
      previewing = false;
      retiredNames.addAll(names);
      names.clear();
      retiredDetails.addAll(details);
      details.clear();
    });
  }

  Future<void> _choose(LandParcel parcel, Offset point, Size size) async {
    final projection = _Projection(parcel.boundary, size);
    await _chooseVertex(
      parcel,
      projection.coordinate(point),
      closeToStart:
          start != null &&
          waypoints.length >= 2 &&
          (point - projection.position(start!)).distance <= 24,
    );
  }

  Future<void> _chooseVertex(
    LandParcel parcel,
    Wgs84Vertex vertex, {
    bool closeToStart = false,
    Offset? tapPosition,
  }) async {
    if (start == null) {
      setState(() {
        start = vertex;
        waypoints.clear();
        projectionRevision++;
        if (tapPosition != null) draftScreenPoints = [tapPosition];
        previewError = null;
      });
      if (tapPosition == null) await _refreshDraftScreenPoints();
      return;
    }
    if (closeToStart) {
      await _finish(parcel);
      return;
    }
    setState(() {
      waypoints.add(vertex);
      projectionRevision++;
      if (tapPosition != null) {
        draftScreenPoints = [...draftScreenPoints, tapPosition];
      }
      previewError = null;
    });
    if (tapPosition == null) await _refreshDraftScreenPoints();
  }

  Future<void> _finish(LandParcel parcel) async {
    if (start == null || previewing) return;
    final revision = ++cutRevision;
    setState(() {
      previewing = true;
      previewError = null;
    });
    try {
      final traced = [start!, ...waypoints];
      final operation = ParcelSubdivisionCut.enclosed(
        fragmentIndex: 0,
        polygon: Wgs84Polygon.fromVertices(traced),
      );
      final next = [...cuts, operation];
      final result = await widget.service.previewPlan(
        subject: widget.subject,
        sourceParcelId: parcel.id,
        cuts: next,
        independentSketches: true,
        productionPlots: widget.productionPlots,
      );
      if (mounted && revision == cutRevision) {
        setState(() {
          cuts.add(next.last);
          preview = result;
          names.add(TextEditingController());
          details.add(
            _SketchDraft(
              layer: widget.productionPlots
                  ? ParcelLayer.fieldPlot
                  : details.any((entry) => entry.layer == ParcelLayer.landBlock)
                  ? ParcelLayer.fieldPlot
                  : ParcelLayer.landBlock,
            ),
          );
          completedScreenRings.add(List.of(draftScreenPoints));
          start = null;
          waypoints.clear();
          projectionRevision++;
          draftScreenPoints = const [];
          previewError = null;
          previewing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).text('subdivision.preview')}: '
              '${result.boundaries.length}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted && revision == cutRevision) {
        setState(() {
          final summary = AppLocalizations.of(
            context,
          ).text('subdivision.invalidCut');
          previewError =
              error is FormatException &&
                  error.message == 'Field plot extends outside its land block.'
              ? AppLocalizations.of(
                  context,
                ).text('production.plot.outsideBlock')
              : error is FormatException || error is StateError
              ? '$summary\n$error'
              : summary;
          previewing = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(previewError!)));
      }
    }
  }

  Future<void> _save(LandParcel source, String? villageId) async {
    final l10n = AppLocalizations.of(context);
    if (cuts.isEmpty ||
        preview == null ||
        saving ||
        start != null ||
        names.any((name) => name.text.trim().isEmpty)) {
      return;
    }
    setState(() => saving = true);
    try {
      if (widget.productionPlots) {
        await widget.service.saveProductionPlots(
          subject: widget.subject,
          sourceParcelId: source.id,
          expectedBoundaryVersion: source.boundaryVersion,
          cuts: List.of(cuts),
          names: names.map((name) => name.text).toList(),
          details: details.map((entry) => entry.toDetails()).toList(),
        );
      } else {
        await widget.service.savePlan(
          subject: widget.subject,
          sourceParcelId: source.id,
          villageId: villageId!,
          expectedBoundaryVersion: source.boundaryVersion,
          cuts: List.of(cuts),
          names: names.map((name) => name.text).toList(),
          details: details.map((entry) => entry.toDetails()).toList(),
          independentSketches: true,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.text('subdivision.saveFailed')}\n$error'),
          ),
        );
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
      if (widget.productionPlots || showLandBlock)
        Polygon(
          polygonId: const PolygonId('source-area'),
          points: vertices.map(point).toList(),
          holes: parcel.boundary.holes
              .map((ring) => ring.map(point).toList())
              .toList(),
          strokeColor: Colors.green.shade800,
          strokeWidth: 3,
          fillColor: Colors.green.withValues(alpha: 0.08),
        ),
      for (var i = 0; i < sketches.length; i++)
        if (i < details.length &&
            (details[i].layer == ParcelLayer.landBlock
                ? showLandBlock
                : showFieldPlots))
          Polygon(
            polygonId: PolygonId('sketch-$i'),
            points: sketches[i].vertices.map(point).toList(),
            strokeColor: Colors.orange.shade900,
            strokeWidth: 3,
            fillColor: Colors.orange.withValues(alpha: 0.22),
          ),
    };
    if (draft.length >= 3) {
      boundaries.add(
        Polygon(
          polygonId: const PolygonId('draft'),
          points: draft.map(point).toList(),
          strokeColor: Colors.deepOrange,
          strokeWidth: 3,
          fillColor: Colors.deepOrange.withValues(alpha: 0.25),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: (event) => lastMapPointer = event.localPosition,
              child: GoogleMap(
                key: const Key('subdivision-satellite-map'),
                mapType: MapType.satellite,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                initialCameraPosition: CameraPosition(
                  target: point(parcel.centroid),
                  zoom: 16,
                ),
                onCameraIdle: () {
                  _refreshDraftScreenPoints();
                },
                onMapCreated: (controller) async {
                  mapController = controller;
                  if (south < north && west < east) {
                    await controller.animateCamera(
                      CameraUpdate.newLatLngBounds(
                        LatLngBounds(
                          southwest: LatLng(south, west),
                          northeast: LatLng(north, east),
                        ),
                        48,
                      ),
                    );
                  }
                  await _refreshDraftScreenPoints();
                },
                onTap: (location) => _chooseVertex(
                  parcel,
                  Wgs84Vertex(
                    latitude: location.latitude,
                    longitude: location.longitude,
                  ),
                  tapPosition: lastMapPointer,
                  closeToStart:
                      start != null &&
                      waypoints.length >= 2 &&
                      lastMapPointer != null &&
                      draftScreenPoints.isNotEmpty &&
                      (lastMapPointer! - draftScreenPoints.first).distance <=
                          24,
                ),
                polygons: boundaries,
                markers: {
                  for (var i = 0; i < draft.length; i++)
                    Marker(
                      markerId: MarkerId('draft-$i'),
                      position: point(draft[i]),
                      infoWindow: InfoWindow(title: '${i + 1}'),
                    ),
                },
                circles: {
                  for (var i = 0; i < draft.length; i++)
                    Circle(
                      circleId: CircleId('draft-point-$i'),
                      center: point(draft[i]),
                      radius: 2,
                      strokeWidth: 3,
                      strokeColor: Colors.white,
                      fillColor: Colors.deepOrange,
                    ),
                },
                polylines: {
                  if (draft.length >= 2)
                    Polyline(
                      polylineId: const PolylineId('draft-edges'),
                      points: draft.map(point).toList(),
                      color: Colors.deepOrange,
                      width: 4,
                    ),
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
              ),
            ),
          ),
          if (widget.productionPlots || showLandBlock)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const Key('subdivision-source-overlay'),
                  painter: ParcelBoundaryOverlayPainter(sourceScreenRings),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DraftScreenLinePainter(draftScreenPoints, [
                  for (var i = 0; i < completedScreenRings.length; i++)
                    if (i < details.length &&
                        (details[i].layer == ParcelLayer.landBlock
                            ? showLandBlock
                            : showFieldPlots))
                      completedScreenRings[i],
                ]),
              ),
            ),
          ),
          if (preview != null && start == null)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: IgnorePointer(
                child: Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '${AppLocalizations.of(context).text('subdivision.preview')}: '
                      '${preview!.boundaries.length} · '
                      '${preview!.areasM2.last.toStringAsFixed(1)} m² · '
                      '${preview!.perimetersM.last.toStringAsFixed(1)} m',
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.white,
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('subdivision-zoom-in'),
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final controller = mapController;
                      if (controller == null) return;
                      await controller.animateCamera(CameraUpdate.zoomIn());
                      await _refreshDraftScreenPoints();
                    },
                  ),
                  IconButton(
                    key: const Key('subdivision-zoom-out'),
                    icon: const Icon(Icons.remove),
                    onPressed: () async {
                      final controller = mapController;
                      if (controller == null) return;
                      await controller.animateCamera(CameraUpdate.zoomOut());
                      await _refreshDraftScreenPoints();
                    },
                  ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < draftScreenPoints.length; i++)
            if (draftScreenPoints[i].dx >= 0 &&
                draftScreenPoints[i].dy >= 0 &&
                draftScreenPoints[i].dx <= constraints.maxWidth &&
                draftScreenPoints[i].dy <= constraints.maxHeight)
              Positioned(
                left: draftScreenPoints[i].dx - 14,
                top: draftScreenPoints[i].dy - 14,
                child: IgnorePointer(
                  child: Container(
                    key: Key('draft-screen-point-$i'),
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.text(
            widget.productionPlots
                ? 'production.plot.create'
                : 'subdivision.title',
          ),
        ),
      ),
      body: FutureBuilder<(LandParcel, String?)>(
        future: source,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('subdivision.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (parcel, villageId) = snapshot.data!;
          final fragments = preview?.boundaries ?? <Wgs84Polygon>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${parcel.parcelCode} · ${parcel.areaM2.toStringAsFixed(1)} m²',
              ),
              const SizedBox(height: 8),
              if (widget.productionPlots)
                Text(l10n.text('production.plot.hint')),
              if (!widget.productionPlots)
                Text(l10n.text('subdivision.instruction')),
              Text(l10n.text('subdivision.editSelected')),
              if (!_useSchematicMap)
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(l10n.text('parcel.layer.landBlock')),
                      selected: widget.productionPlots || showLandBlock,
                      onSelected: widget.productionPlots
                          ? null
                          : (value) => setState(() => showLandBlock = value),
                    ),
                    FilterChip(
                      label: Text(l10n.text('parcel.layer.fieldPlot')),
                      selected: showFieldPlots,
                      onSelected: (value) =>
                          setState(() => showFieldPlots = value),
                    ),
                  ],
                ),
              if (!_useSchematicMap) Text(l10n.text('subdivision.layerHint')),
              if (!_useSchematicMap)
                TextButton.icon(
                  key: const Key('subdivision-fit-source'),
                  onPressed: () async {
                    final controller = mapController;
                    if (controller == null) return;
                    final vertices = parcel.boundary.vertices;
                    await controller.animateCamera(
                      CameraUpdate.newLatLngBounds(
                        LatLngBounds(
                          southwest: LatLng(
                            vertices.map((v) => v.latitude).reduce(math.min),
                            vertices.map((v) => v.longitude).reduce(math.min),
                          ),
                          northeast: LatLng(
                            vertices.map((v) => v.latitude).reduce(math.max),
                            vertices.map((v) => v.longitude).reduce(math.max),
                          ),
                        ),
                        48,
                      ),
                    );
                    await _refreshDraftScreenPoints();
                  },
                  icon: const Icon(Icons.center_focus_strong),
                  label: Text(l10n.text('production.plot.fitBlock')),
                ),
              SizedBox(
                height: 128,
                child: start == null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(l10n.text('subdivision.tapToStart')),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l10n.text('subdivision.pointCount')}: '
                            '${waypoints.length + 1}',
                            key: const Key('subdivision-point-count'),
                          ),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              if (waypoints.isNotEmpty)
                                TextButton.icon(
                                  key: const Key('subdivision-undo-point'),
                                  onPressed: () => setState(() {
                                    cutRevision++;
                                    previewing = false;
                                    projectionRevision++;
                                    waypoints.removeLast();
                                    draftScreenPoints =
                                        draftScreenPoints.isEmpty
                                        ? const []
                                        : draftScreenPoints.sublist(
                                            0,
                                            draftScreenPoints.length - 1,
                                          );
                                    previewError = null;
                                  }),
                                  icon: const Icon(Icons.undo),
                                  label: Text(
                                    l10n.text('subdivision.undoPoint'),
                                  ),
                                ),
                              TextButton.icon(
                                key: const Key('subdivision-reset-cut'),
                                onPressed: _resetDraft,
                                icon: const Icon(Icons.restart_alt),
                                label: Text(l10n.text('subdivision.reset')),
                              ),
                              if (waypoints.length >= 2)
                                FilledButton.icon(
                                  key: const Key('subdivision-close-outline'),
                                  onPressed: previewing
                                      ? null
                                      : () => _finish(parcel),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: Text(
                                    l10n.text('subdivision.closeOutline'),
                                  ),
                                ),
                            ],
                          ),
                          if (previewing) const LinearProgressIndicator(),
                        ],
                      ),
              ),
              if (previewError != null)
                Text(
                  previewError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!_useSchematicMap)
                SizedBox(height: 640, child: _satelliteMap(parcel, fragments))
              else
                SizedBox(
                  height: 420,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = Size(box.maxWidth, box.maxHeight);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: InteractiveViewer(
                              transformationController: _drawingTransform,
                              minScale: 1,
                              maxScale: 12,
                              child: SizedBox(
                                width: size.width,
                                height: size.height,
                                child: GestureDetector(
                                  key: const Key('subdivision-map'),
                                  onTapUp: (details) => _choose(
                                    parcel,
                                    details.localPosition,
                                    size,
                                  ),
                                  child: CustomPaint(
                                    size: size,
                                    painter: _CutPainter(
                                      parcel.boundary,
                                      [?start, ...waypoints],
                                      fragments,
                                      -1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Material(
                              color: Colors.white,
                              elevation: 4,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: const Key('drawing-zoom-in'),
                                    icon: const Icon(Icons.add),
                                    onPressed: () => _zoomDrawing(1.5, size),
                                  ),
                                  IconButton(
                                    key: const Key('drawing-zoom-out'),
                                    icon: const Icon(Icons.remove),
                                    onPressed: () =>
                                        _zoomDrawing(1 / 1.5, size),
                                  ),
                                  IconButton(
                                    key: const Key('drawing-zoom-reset'),
                                    icon: const Icon(Icons.center_focus_strong),
                                    onPressed: () {
                                      _drawingTransform.value =
                                          Matrix4.identity();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              if (_useSchematicMap && preview != null) ...[
                Text(l10n.text('subdivision.overview')),
                SizedBox(
                  height: 180,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = Size(box.maxWidth, box.maxHeight);
                      return GestureDetector(
                        key: const Key('subdivision-overview'),
                        child: CustomPaint(
                          size: size,
                          painter: _CutPainter(
                            parcel.boundary,
                            const [],
                            fragments,
                            -1,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (cuts.isNotEmpty)
                TextButton.icon(
                  key: const Key('subdivision-reset-all'),
                  onPressed: _resetAll,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.text('subdivision.resetAll')),
                ),
              if (preview != null) ...[
                Text(
                  '${l10n.text('subdivision.preview')}: ${fragments.length}',
                ),
                for (var i = 0; i < fragments.length; i++)
                  Text(
                    '${_sketchLabel(l10n, i)}: '
                    '${preview!.areasM2[i].toStringAsFixed(1)} m² · '
                    '${preview!.perimetersM[i].toStringAsFixed(1)} m',
                  ),
              ],
              if (!widget.productionPlots && villageId == null)
                Text(l10n.text('subdivision.locationRequired')),
              const SizedBox(height: 12),
              if (cuts.isNotEmpty)
                for (var i = 0; i < names.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _sketchLabel(l10n, i),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextField(
                            key: Key('subdivision-name-$i'),
                            controller: names[i],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l10n.text('subdivision.name'),
                            ),
                          ),
                          if (!widget.productionPlots)
                            DropdownButtonFormField<ParcelLayer>(
                              isExpanded: true,
                              key: Key('subdivision-layer-$i'),
                              initialValue: details[i].layer,
                              decoration: InputDecoration(
                                labelText: l10n.text('subdivision.layer'),
                              ),
                              items: [
                                for (final layer in ParcelLayer.values)
                                  DropdownMenuItem(
                                    value: layer,
                                    child: Text(
                                      l10n.text('parcel.layer.${layer.name}'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setState(() {
                                details[i].layer = value!;
                                if (value == ParcelLayer.landBlock) {
                                  details[i].parentSketchIndex = null;
                                } else {
                                  for (final entry in details.skip(i + 1)) {
                                    if (entry.parentSketchIndex == i) {
                                      entry.parentSketchIndex = null;
                                    }
                                  }
                                }
                              }),
                            ),
                          if (!widget.productionPlots &&
                              details[i].layer == ParcelLayer.fieldPlot)
                            DropdownButtonFormField<int?>(
                              isExpanded: true,
                              key: Key('subdivision-parent-$i'),
                              initialValue: details[i].parentSketchIndex,
                              decoration: InputDecoration(
                                labelText: l10n.text('subdivision.parentBlock'),
                              ),
                              items: [
                                DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text(
                                    parcel.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                for (var j = 0; j < i; j++)
                                  if (details[j].layer == ParcelLayer.landBlock)
                                    DropdownMenuItem<int?>(
                                      value: j,
                                      child: Text(
                                        names[j].text.isEmpty
                                            ? _sketchLabel(l10n, j)
                                            : names[j].text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                              ],
                              onChanged: (value) => setState(
                                () => details[i].parentSketchIndex = value,
                              ),
                            ),
                          Text(
                            '${l10n.text('geometry.areaM2')}: '
                            '${preview!.areasM2[i].toStringAsFixed(1)} m² · '
                            '${l10n.text('geometry.perimeter')}: '
                            '${preview!.perimetersM[i].toStringAsFixed(1)} m',
                          ),
                          Text(
                            '${l10n.text('subdivision.location')}: '
                            '${const Wgs84GeometryService().measure(fragments[i]).centroid.latitude.toStringAsFixed(6)}, '
                            '${const Wgs84GeometryService().measure(fragments[i]).centroid.longitude.toStringAsFixed(6)}',
                          ),
                          _statusPicker<LandUseType>(
                            l10n,
                            'survey.landUse',
                            'landUse',
                            details[i].landUseType,
                            LandUseType.values,
                            (value) =>
                                setState(() => details[i].landUseType = value),
                          ),
                          _statusPicker<LandCondition>(
                            l10n,
                            'survey.landCondition',
                            'landCondition',
                            details[i].landCondition,
                            LandCondition.values,
                            (value) => setState(
                              () => details[i].landCondition = value,
                            ),
                          ),
                          _statusPicker<ClearingStatus>(
                            l10n,
                            'survey.clearingStatus',
                            'clearing',
                            details[i].clearingStatus,
                            ClearingStatus.values,
                            (value) => setState(
                              () => details[i].clearingStatus = value,
                            ),
                          ),
                          _statusPicker<ReadinessStatus>(
                            l10n,
                            'survey.readinessStatus',
                            'readiness',
                            details[i].readinessStatus,
                            ReadinessStatus.values,
                            (value) => setState(
                              () => details[i].readinessStatus = value,
                            ),
                          ),
                          TextField(
                            controller: details[i].notes,
                            decoration: InputDecoration(
                              labelText: l10n.text('subdivision.notes'),
                            ),
                          ),
                          if (widget.catalog != null)
                            CatalogValuePicker(
                              service: widget.catalog!,
                              kind: CatalogKind.crop,
                              controller: details[i].cropType,
                              label: l10n.text('crop.type'),
                              allowEmpty: true,
                              onSelected: () => setState(() {}),
                            )
                          else
                            TextField(
                              controller: details[i].cropType,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: l10n.text('crop.type'),
                              ),
                            ),
                          if (details[i].cropType.text.trim().isNotEmpty) ...[
                            TextField(
                              controller: details[i].cropQuantity,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: l10n.text('crop.quantity'),
                              ),
                            ),
                            if (widget.catalog != null)
                              CatalogValuePicker(
                                service: widget.catalog!,
                                kind: CatalogKind.unit,
                                controller: details[i].cropUnit,
                                label: l10n.text('crop.unit'),
                              )
                            else
                              TextField(
                                controller: details[i].cropUnit,
                                decoration: InputDecoration(
                                  labelText: l10n.text('crop.unit'),
                                ),
                              ),
                            DropdownButtonFormField<CropGrowthStage?>(
                              isExpanded: true,
                              initialValue: details[i].cropGrowthStage,
                              decoration: InputDecoration(
                                labelText: l10n.text('crop.growthStage'),
                              ),
                              items: [
                                DropdownMenuItem<CropGrowthStage?>(
                                  value: null,
                                  child: Text(
                                    l10n.text('crop.growthStage.unknown'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                for (final stage in CropGrowthStage.values)
                                  DropdownMenuItem<CropGrowthStage?>(
                                    value: stage,
                                    child: Text(
                                      l10n.text(
                                        'crop.growthStage.${stage.name}',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setState(
                                () => details[i].cropGrowthStage = value,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('subdivision-save'),
                onPressed:
                    preview == null ||
                        (!widget.productionPlots && villageId == null) ||
                        saving ||
                        start != null ||
                        names.any((n) => n.text.trim().isEmpty)
                    ? null
                    : () => _save(parcel, villageId),
                child: Text(l10n.text('subdivision.save')),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusPicker<T extends Enum>(
    AppLocalizations l10n,
    String labelKey,
    String valuePrefix,
    T value,
    List<T> options,
    ValueChanged<T> onChanged,
  ) => DropdownButtonFormField<T>(
    isExpanded: true,
    initialValue: value,
    decoration: InputDecoration(labelText: l10n.text(labelKey)),
    items: [
      for (final option in options)
        DropdownMenuItem<T>(
          value: option,
          child: Text(
            l10n.text('$valuePrefix.${option.name}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (selected) {
      if (selected != null) onChanged(selected);
    },
  );
}

class _SketchDraft {
  _SketchDraft({required this.layer});

  ParcelLayer layer;
  int? parentSketchIndex;
  LandUseType landUseType = LandUseType.agricultural;
  LandCondition landCondition = LandCondition.unknown;
  ClearingStatus clearingStatus = ClearingStatus.unknown;
  ReadinessStatus readinessStatus = ReadinessStatus.unknown;
  CropGrowthStage? cropGrowthStage;
  final notes = TextEditingController();
  final cropType = TextEditingController();
  final cropQuantity = TextEditingController();
  final cropUnit = TextEditingController();

  ParcelSketchDetails toDetails() => ParcelSketchDetails(
    layer: layer,
    parentSketchIndex: parentSketchIndex,
    landUseType: landUseType,
    landCondition: landCondition,
    clearingStatus: clearingStatus,
    readinessStatus: readinessStatus,
    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
    cropType: cropType.text.trim().isEmpty ? null : cropType.text.trim(),
    cropQuantity: double.tryParse(cropQuantity.text.trim()),
    cropUnit: cropUnit.text.trim(),
    cropGrowthStage: cropGrowthStage,
  );

  void dispose() {
    notes.dispose();
    cropType.dispose();
    cropQuantity.dispose();
    cropUnit.dispose();
  }
}

class _DraftScreenLinePainter extends CustomPainter {
  const _DraftScreenLinePainter(this.points, this.completedRings);

  final List<Offset> points;
  final List<List<Offset>> completedRings;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ring in completedRings) {
      if (ring.length < 3) continue;
      final outline = Path()..moveTo(ring.first.dx, ring.first.dy);
      for (final point in ring.skip(1)) {
        outline.lineTo(point.dx, point.dy);
      }
      outline.close();
      canvas.drawPath(
        outline,
        Paint()..color = Colors.orange.withValues(alpha: 0.28),
      );
      canvas.drawPath(
        outline,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      canvas.drawPath(
        outline,
        Paint()
          ..color = Colors.deepOrange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.deepOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_DraftScreenLinePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.completedRings != completedRings;
}

class _Projection {
  _Projection(this.polygon, this.size) : vertices = polygon.vertices {
    final lons = vertices.map((v) => v.longitude);
    final lats = vertices.map((v) => v.latitude);
    left = lons.reduce(math.min);
    right = lons.reduce(math.max);
    bottom = lats.reduce(math.min);
    top = lats.reduce(math.max);
    scale = math.min(
      (size.width - 40) / math.max(right - left, 1e-12),
      (size.height - 40) / math.max(top - bottom, 1e-12),
    );
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
        if (i == 0) {
          path.moveTo(vertex.dx, vertex.dy);
        } else {
          path.lineTo(vertex.dx, vertex.dy);
        }
      }
      path.close();
    }
    return path.contains(point);
  }

  Wgs84Vertex? nearestBoundary(Offset point, {double tolerance = 24}) =>
      _nearestBoundary(point, [vertices, ...polygon.holes], tolerance);

  Wgs84Vertex? nearestOuterBoundary(Offset point, {double tolerance = 24}) =>
      _nearestBoundary(point, [vertices], tolerance);

  Wgs84Vertex? nearestHoleBoundary(Offset point, {double tolerance = 24}) =>
      _nearestBoundary(point, polygon.holes, tolerance);

  Wgs84Vertex? _nearestBoundary(
    Offset point,
    List<List<Wgs84Vertex>> rings,
    double tolerance,
  ) {
    var distance = double.infinity;
    Offset? nearest;
    for (final ring in rings) {
      for (var i = 0; i < ring.length - 1; i++) {
        final a = position(ring[i]);
        final b = position(ring[i + 1]);
        final direction = b - a;
        final length2 =
            direction.dx * direction.dx + direction.dy * direction.dy;
        if (length2 <= 0) continue;
        final t =
            ((point.dx - a.dx) * direction.dx +
                (point.dy - a.dy) * direction.dy) /
            length2;
        final candidate = a + direction * t.clamp(0.0, 1.0).toDouble();
        final d = (candidate - point).distance;
        if (d < distance) {
          distance = d;
          nearest = candidate;
        }
      }
    }
    return distance <= tolerance && nearest != null
        ? coordinate(nearest)
        : null;
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
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
      }
      return path;
    }

    canvas.drawColor(const Color(0xfff1f6ee), BlendMode.src);
    if (children != null) {
      for (var i = 0; i < children!.length; i++) {
        canvas.drawPath(
          outline(children![i]),
          Paint()
            ..color = (i == selected
                ? const Color(0xffa9d99d)
                : const Color(0xffe7dfac)),
        );
        canvas.drawPath(
          outline(children![i]),
          Paint()
            ..color = (i == selected
                ? const Color(0xff146b32)
                : const Color(0xff795d25))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
    canvas.drawPath(
      outline(source),
      Paint()
        ..color = const Color(0xff217a3b)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (cut.length >= 3) {
      final draft = Path()
        ..moveTo(
          projection.position(cut.first).dx,
          projection.position(cut.first).dy,
        );
      for (final vertex in cut.skip(1)) {
        final position = projection.position(vertex);
        draft.lineTo(position.dx, position.dy);
      }
      draft.close();
      canvas.drawPath(draft, Paint()..color = const Color(0x55ff7a32));
      canvas.drawPath(
        draft,
        Paint()
          ..color = const Color(0xffe65d16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    for (var i = 0; i < cut.length; i++) {
      final point = projection.position(cut[i]);
      canvas.drawCircle(point, 6, Paint()..color = Colors.deepOrange);
      if (i > 0) {
        canvas.drawLine(
          projection.position(cut[i - 1]),
          point,
          Paint()
            ..color = Colors.deepOrange
            ..strokeWidth = 3,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CutPainter old) =>
      old.source != source ||
      old.cut != cut ||
      old.children != children ||
      old.selected != selected;
}

/// The parent boundary is drawn above the platform map even when native
/// polygon rendering or satellite tiles are unavailable. Hole interiors remain clear.
class ParcelBoundaryOverlayPainter extends CustomPainter {
  const ParcelBoundaryOverlayPainter(this.rings);
  final List<List<Offset>> rings;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in rings) {
      if (ring.length < 3) continue;
      path.moveTo(ring.first.dx, ring.first.dy);
      for (final point in ring.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
    }
    canvas.drawPath(
      path,
      Paint()..color = Colors.green.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.green.shade800
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(ParcelBoundaryOverlayPainter oldDelegate) =>
      oldDelegate.rings != rings;
}
