import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../application/land_parcel_application_service.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../controllers/land_parcel_controller.dart';

/// Offline schematic editor. Camera changes never change stored coordinates.
class LandParcelBoundaryEditScreen extends StatefulWidget {
  const LandParcelBoundaryEditScreen({
    super.key,
    required this.controller,
    required this.parcel,
  });
  final LandParcelController controller;
  final LandParcel parcel;
  @override
  State<LandParcelBoundaryEditScreen> createState() => _BoundaryEditState();
}

class _BoundaryEditState extends State<LandParcelBoundaryEditScreen> {
  final camera = TransformationController();
  late List<Wgs84Vertex> points;
  late Future<List<LandParcel>> references;
  double viewportExtent = 400;
  int selected = 0;
  bool redrawing = false;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    points = widget.parcel.boundary.vertices
        .take(widget.parcel.boundary.vertices.length - 1)
        .toList();
    references = widget.controller.parcels
        .listByFarm(widget.parcel.farmId)
        .then(
          (all) => all
              .where(
                (p) =>
                    p.active &&
                    p.id != widget.parcel.id &&
                    ((widget.parcel.layer == ParcelLayer.landBlock &&
                            p.layer == ParcelLayer.landBlock &&
                            p.projectId == widget.parcel.projectId) ||
                        p.id == widget.parcel.parentBlockId ||
                        p.parentBlockId == widget.parcel.id ||
                        (widget.parcel.parentBlockId != null &&
                            p.parentBlockId == widget.parcel.parentBlockId)),
              )
              .toList(),
        );
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  void zoom(double factor) {
    final scale = camera.value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 12.0);
    final f = next / scale;
    final matrix = camera.value.clone();
    final center = viewportExtent / 2;
    matrix.setEntry(0, 0, next);
    matrix.setEntry(1, 1, next);
    matrix.setEntry(0, 3, f * camera.value.entry(0, 3) + center * (1 - f));
    matrix.setEntry(1, 3, f * camera.value.entry(1, 3) + center * (1 - f));
    camera.value = matrix;
  }

  bool get changed {
    final original = widget.parcel.boundary.vertices;
    return points.length != original.length - 1 ||
        List.generate(
          points.length,
          (i) => points[i] != original[i],
        ).any((v) => v);
  }

  Future<void> save() async {
    final l10n = AppLocalizations.of(context);
    try {
      Wgs84Polygon.fromVertices(points, holes: widget.parcel.boundary.holes);
    } on FormatException {
      setState(() => error = 'landParcel.geometry.invalid');
      return;
    }
    bool confirmed = false;
    if (widget.parcel.verificationStatus ==
        BoundaryVerificationStatus.verified) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.text('boundaryEdit.title')),
              content: Text(
                l10n.text('landParcel.boundary.verifiedConfirmation'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.text('common.cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.text('common.confirm')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.controller.replaceBoundary!(
        widget.controller.subject,
        ReplaceBoundaryCommand(
          farmId: widget.parcel.farmId,
          parcelId: widget.parcel.id,
          vertices: List.of(points),
          holes: widget.parcel.boundary.holes
              .map((ring) => ring.toList())
              .toList(),
          source: BoundarySource.manual,
          actorMembershipId: widget.controller.subject.membershipId,
          occurredAt: DateTime.now().toUtc(),
          expectedBoundaryVersion: widget.parcel.boundaryVersion,
          expectedUpdatedAt: widget.parcel.updatedAt,
          confirmVerifiedReplacement: confirmed,
        ),
      );
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        Navigator.pop(context, true);
      } else {
        setState(() => error = result.messageKey);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'landParcel.persistence.failed');
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.text('boundaryEdit.title'))),
        body: FutureBuilder<List<LandParcel>>(
          future: references,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(l10n.text('landParcel.persistence.failed')),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final frame = _Frame([
              widget.parcel.boundary,
              ...snapshot.data!
                  .where(
                    (p) =>
                        p.id == widget.parcel.parentBlockId ||
                        p.parentBlockId == widget.parcel.id ||
                        p.parentBlockId == widget.parcel.parentBlockId &&
                            widget.parcel.parentBlockId != null,
                  )
                  .map((p) => p.boundary),
            ]);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${widget.parcel.parcelCode} · ${widget.parcel.name}'),
                Text(l10n.text('boundaryEdit.hint')),
                Text(l10n.text('boundaryEdit.legend')),
                Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      key: const Key('boundary-zoom-in'),
                      tooltip: l10n.text('boundaryEdit.zoomIn'),
                      onPressed: () => zoom(1.5),
                      icon: const Icon(Icons.zoom_in),
                    ),
                    IconButton(
                      key: const Key('boundary-zoom-out'),
                      tooltip: l10n.text('boundaryEdit.zoomOut'),
                      onPressed: () => zoom(1 / 1.5),
                      icon: const Icon(Icons.zoom_out),
                    ),
                    IconButton(
                      tooltip: l10n.text('boundaryEdit.fit'),
                      onPressed: () => camera.value = Matrix4.identity(),
                      icon: const Icon(Icons.fit_screen),
                    ),
                  ],
                ),
                SizedBox(
                  height: 420,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      viewportExtent = math.min(constraints.maxWidth, 420.0);
                      frame.extent = viewportExtent;
                      return AbsorbPointer(
                        absorbing: saving,
                        child: InteractiveViewer(
                          transformationController: camera,
                          minScale: 1,
                          maxScale: 12,
                          constrained: false,
                          child: GestureDetector(
                            key: const Key('boundary-edit-canvas'),
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (event) => setState(() {
                              final point = frame.vertex(event.localPosition);
                              if (redrawing) {
                                points.add(point);
                                selected = points.length - 1;
                              } else if (points.isNotEmpty) {
                                points[selected] = point;
                              }
                              error = null;
                            }),
                            child: CustomPaint(
                              size: Size(viewportExtent, viewportExtent),
                              painter: _BoundaryPainter(
                                frame,
                                widget.parcel.boundary,
                                snapshot.data!,
                                points,
                                selected,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!redrawing)
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var i = 0; i < points.length; i++)
                        ChoiceChip(
                          label: Text('${i + 1}'),
                          selected: selected == i,
                          onSelected: saving
                              ? null
                              : (_) => setState(() => selected = i),
                        ),
                    ],
                  ),
                Text('${l10n.text('boundaryEdit.points')}: ${points.length}'),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const Key('boundary-redraw'),
                      onPressed: saving
                          ? null
                          : () => setState(() {
                              points = [];
                              selected = 0;
                              redrawing = true;
                              error = null;
                            }),
                      child: Text(l10n.text('boundaryEdit.redraw')),
                    ),
                    TextButton(
                      onPressed: saving || points.isEmpty
                          ? null
                          : () => setState(() {
                              points.removeAt(
                                redrawing ? points.length - 1 : selected,
                              );
                              selected = math.max(
                                0,
                                math.min(selected, points.length - 1),
                              );
                            }),
                      child: Text(l10n.text('boundaryEdit.remove')),
                    ),
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => setState(() {
                              points = widget.parcel.boundary.vertices
                                  .take(
                                    widget.parcel.boundary.vertices.length - 1,
                                  )
                                  .toList();
                              selected = 0;
                              redrawing = false;
                              error = null;
                            }),
                      child: Text(l10n.text('boundaryEdit.reset')),
                    ),
                  ],
                ),
                if (error != null)
                  Text(
                    l10n.text(error!),
                    key: const Key('boundary-edit-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                FilledButton(
                  key: const Key('boundary-edit-save'),
                  onPressed: saving || !changed || points.length < 3
                      ? null
                      : save,
                  child: Text(l10n.text('common.save')),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Frame {
  _Frame(List<Wgs84Polygon> polygons) {
    final points = polygons.expand((p) => p.vertices).toList();
    west = points.map((p) => p.longitude).reduce(math.min);
    south = points.map((p) => p.latitude).reduce(math.min);
    final east = points.map((p) => p.longitude).reduce(math.max);
    final north = points.map((p) => p.latitude).reduce(math.max);
    final correction = math.cos((north + south) / 2 * math.pi / 180);
    width = math.max(east - west, (north - south) / correction);
    height = width * correction;
    west -= (width - (east - west)) / 2;
    south -= (height - (north - south)) / 2;
  }
  late double west, south, width, height;
  double extent = 500;
  Offset offset(Wgs84Vertex p) => Offset(
    extent * (0.08 + (p.longitude - west) / width * 0.84),
    extent * (0.92 - (p.latitude - south) / height * 0.84),
  );
  Wgs84Vertex vertex(Offset p) => Wgs84Vertex(
    longitude: west + (p.dx / extent - 0.08) / 0.84 * width,
    latitude: south + (0.92 - p.dy / extent) / 0.84 * height,
  );
}

class _BoundaryPainter extends CustomPainter {
  _BoundaryPainter(
    this.frame,
    this.original,
    this.references,
    this.points,
    this.selected,
  );
  final _Frame frame;
  final Wgs84Polygon original;
  final List<LandParcel> references;
  final List<Wgs84Vertex> points;
  final int selected;
  void outline(
    Canvas canvas,
    List<Wgs84Vertex> ring,
    Color color,
    double width, {
    bool close = true,
  }) {
    if (ring.isEmpty) {
      return;
    }
    final path = Path()
      ..moveTo(frame.offset(ring.first).dx, frame.offset(ring.first).dy);
    for (final point in ring.skip(1)) {
      final p = frame.offset(point);
      path.lineTo(p.dx, p.dy);
    }
    if (close) {
      path.close();
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff0eee5),
    );
    outline(canvas, original.vertices, Colors.grey, 2);
    for (final parcel in references) {
      outline(
        canvas,
        parcel.boundary.vertices,
        parcel.layer == ParcelLayer.landBlock ? Colors.green : Colors.blue,
        3,
      );
      for (final hole in parcel.boundary.holes) {
        outline(canvas, hole, Colors.purple, 2);
      }
    }
    for (final hole in original.holes) {
      outline(canvas, hole, Colors.purple, 2);
    }
    outline(canvas, points, Colors.deepOrange, 3, close: points.length >= 3);
    for (var i = 0; i < points.length; i++) {
      final p = frame.offset(points[i]);
      canvas.drawCircle(
        p,
        i == selected ? 12 : 9,
        Paint()..color = Colors.deepOrange,
      );
      final text = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, p - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BoundaryPainter oldDelegate) => true;
}
