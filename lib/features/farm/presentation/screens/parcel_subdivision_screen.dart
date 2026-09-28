import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/geography/domain/administrative_catalog_repository.dart';
import '../../../../core/geography/domain/entities/administrative_unit.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_subdivision_service.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';

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
  final firstName = TextEditingController();
  final secondName = TextEditingController();
  Wgs84Vertex? start;
  Wgs84Vertex? end;
  ParcelSubdivisionPreview? preview;
  String? previewError;
  bool saving = false;
  int cutRevision = 0;

  Future<(LandParcel, String?)> _load() async {
    final parcel = await widget.service.parcels.getById(
      farmId: widget.subject.farmId, id: widget.sourceParcelId);
    if (parcel == null) throw StateError('Source parcel is missing.');
    final units = await widget.administrativeCatalog.all();
    final byId = {for (final unit in units) unit.id: unit};
    final matches = units.where((v) {
      if (!v.active || v.level != AdministrativeLevel.village ||
          v.code != parcel.villageCode) return false;
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
    firstName.dispose();
    secondName.dispose();
    super.dispose();
  }

  Future<void> _choose(LandParcel parcel, Offset point, Size size) async {
    final projection = _Projection(parcel.boundary, size);
    final candidate = projection.nearestBoundary(point);
    if (candidate == null) return;
    final previous = start;
    setState(() {
      cutRevision++;
      if (previous == null || end != null) {
        start = candidate;
        end = null;
      } else {
        end = candidate;
      }
      preview = null;
      previewError = null;
    });
    if (previous == null || end == null) return;
    final revision = cutRevision;
    try {
      final result = await widget.service.preview(
        subject: widget.subject, sourceParcelId: parcel.id,
        cutStart: start!, cutEnd: end!);
      if (mounted && revision == cutRevision) setState(() => preview = result);
    } catch (_) {
      if (mounted && revision == cutRevision) setState(() => previewError =
          AppLocalizations.of(context).text('subdivision.invalidCut'));
    }
  }

  Future<void> _save(LandParcel source, String villageId) async {
    final l10n = AppLocalizations.of(context);
    if (start == null || end == null || preview == null || saving) return;
    setState(() => saving = true);
    try {
      await widget.service.save(
        subject: widget.subject, sourceParcelId: source.id,
        villageId: villageId, expectedBoundaryVersion: source.boundaryVersion,
        cutStart: start!, cutEnd: end!, firstName: firstName.text,
        secondName: secondName.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.text('subdivision.saveFailed'))));
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
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${parcel.parcelCode} · ${parcel.areaM2.toStringAsFixed(1)} m²'),
            const SizedBox(height: 8),
            Text(l10n.text('subdivision.instruction')),
            const SizedBox(height: 12),
            SizedBox(height: 320, child: LayoutBuilder(builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                key: const Key('subdivision-map'),
                onTapDown: (details) => _choose(parcel, details.localPosition, size),
                child: CustomPaint(size: size,
                  painter: _CutPainter(parcel.boundary, start, end,
                    preview?.boundaries)),
              );
            })),
            if (previewError != null) Text(previewError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (preview != null) Text('${l10n.text('subdivision.preview')}: '
              '${preview!.areasM2[0].toStringAsFixed(1)} + '
              '${preview!.areasM2[1].toStringAsFixed(1)} m²'),
            if (villageId == null) Text(l10n.text('subdivision.locationRequired')),
            const SizedBox(height: 12),
            TextField(key: const Key('subdivision-first-name'),
              controller: firstName,
              decoration: InputDecoration(labelText: l10n.text('subdivision.firstName'))),
            TextField(key: const Key('subdivision-second-name'),
              controller: secondName,
              decoration: InputDecoration(labelText: l10n.text('subdivision.secondName'))),
            const SizedBox(height: 12),
            FilledButton(key: const Key('subdivision-save'),
              onPressed: preview == null || villageId == null || saving
                  ? null : () => _save(parcel, villageId),
              child: Text(l10n.text('subdivision.save'))),
          ]);
        }),
    );
  }
}

class _Projection {
  _Projection(Wgs84Polygon polygon, this.size) : vertices = polygon.vertices {
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

  Wgs84Vertex? nearestBoundary(Offset point) {
    var distance = double.infinity;
    Offset? nearest;
    for (var i = 0; i < vertices.length - 1; i++) {
      final a = position(vertices[i]);
      final b = position(vertices[i + 1]);
      final direction = b - a;
      final length2 = direction.dx * direction.dx + direction.dy * direction.dy;
      if (length2 <= 0) continue;
      final t = ((point.dx - a.dx) * direction.dx +
          (point.dy - a.dy) * direction.dy) / length2;
      final candidate = a + direction * t.clamp(0.0, 1.0).toDouble();
      final d = (candidate - point).distance;
      if (d < distance) { distance = d; nearest = candidate; }
    }
    return distance <= 24 && nearest != null ? coordinate(nearest) : null;
  }
}

class _CutPainter extends CustomPainter {
  const _CutPainter(this.source, this.start, this.end, this.children);
  final Wgs84Polygon source;
  final Wgs84Vertex? start, end;
  final List<Wgs84Polygon>? children;

  @override
  void paint(Canvas canvas, Size size) {
    final projection = _Projection(source, size);
    Path outline(Wgs84Polygon polygon) {
      final path = Path();
      for (var i = 0; i < polygon.vertices.length; i++) {
        final point = projection.position(polygon.vertices[i]);
        if (i == 0) { path.moveTo(point.dx, point.dy); }
        else { path.lineTo(point.dx, point.dy); }
      }
      path.close();
      return path;
    }
    canvas.drawColor(const Color(0xfff1f6ee), BlendMode.src);
    if (children != null) {
      for (var i = 0; i < children!.length; i++) {
        canvas.drawPath(outline(children![i]), Paint()
          ..color = i == 0 ? const Color(0x9967b468) : const Color(0x99e2b561));
      }
    }
    canvas.drawPath(outline(source), Paint()
      ..color = const Color(0xff217a3b)..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    if (start != null) {
      final a = projection.position(start!);
      canvas.drawCircle(a, 7, Paint()..color = Colors.deepOrange);
      if (end != null) {
        final b = projection.position(end!);
        canvas.drawLine(a, b, Paint()..color = Colors.deepOrange
          ..strokeWidth = 3);
        canvas.drawCircle(b, 7, Paint()..color = Colors.deepOrange);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CutPainter old) =>
      old.source != source || old.start != start || old.end != end ||
      old.children != children;
}
