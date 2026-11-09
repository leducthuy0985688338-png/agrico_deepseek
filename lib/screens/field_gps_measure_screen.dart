import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/field_model.dart';
import '../providers/field_provider.dart';
import '../services/gps_field_service.dart';

class FieldGpsMeasureScreen extends StatefulWidget {
  const FieldGpsMeasureScreen({
    super.key,
    this.persistResult = true,
    this.gpsOverride,
    this.mapBuilder,
    this.saveOverride,
  }) : existingField = null;

  /// Remeasures an existing legacy field without creating another identity.
  const FieldGpsMeasureScreen.forField({
    super.key,
    required FieldModel field,
    this.gpsOverride,
    this.mapBuilder,
    this.saveOverride,
  }) : existingField = field,
       persistResult = true;

  /// Returns a measurement for the caller's preview/commit workflow.
  const FieldGpsMeasureScreen.draft({
    super.key,
    this.gpsOverride,
    this.mapBuilder,
  }) : persistResult = false,
       existingField = null,
       saveOverride = null;

  final FieldModel? existingField;
  final bool persistResult;
  final GpsFieldService? gpsOverride;
  final Widget Function()? mapBuilder;
  final Future<void> Function(FieldModel)? saveOverride;
  @override
  State<FieldGpsMeasureScreen> createState() => _FieldGpsMeasureScreenState();
}

class _FieldGpsMeasureScreenState extends State<FieldGpsMeasureScreen> {
  late final _gps = widget.gpsOverride ?? GpsFieldService();
  final List<LatLng> _points = [];
  StreamSubscription<Position>? _subscription;
  GoogleMapController? _mapController;
  Position? _lastPosition;
  bool _recording = false;
  bool _saving = false;
  FieldModel? _pendingSave;

  double get _area => _gps.calculateAreaSquareMeters(_points);
  double get _perimeter => _gps.calculatePerimeterMeters(_points);

  @override
  void dispose() { _subscription?.cancel(); super.dispose(); }

  Future<void> _startMeasurement() async {
    if (!await _gps.ensureLocationReady()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy bật GPS và cấp quyền vị trí cho AGRICO.')));
      return;
    }
    final current = await _gps.getCurrentPosition();
    if (current == null || !mounted) return;
    setState(() { _recording = true; _pendingSave = null; _points.clear(); _lastPosition = current; });
    _addPosition(current);
    await _subscription?.cancel();
    _subscription = _gps.positionStream().listen(_addPosition);
  }

  void _addPosition(Position position) {
    if (!mounted) return;
    _lastPosition = position;
    final point = LatLng(position.latitude, position.longitude);
    if (_points.isNotEmpty) {
      final last = _points.last;
      final distance = Geolocator.distanceBetween(last.latitude, last.longitude, point.latitude, point.longitude);
      if (distance < 2) { setState(() {}); return; }
    }
    setState(() { _pendingSave = null; _points.add(point); });
    _mapController?.animateCamera(CameraUpdate.newLatLng(point));
  }

  Future<void> _stopMeasurement() async { await _subscription?.cancel(); _subscription = null; if (mounted) setState(() => _recording = false); }
  void _undoLastPoint() { if (_points.isNotEmpty && !_saving) setState(() { _pendingSave = null; _points.removeLast(); }); }

  Future<void> _saveField() async {
    if (_saving) return;
    if (_points.length < 3 || _area <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ranh giới GPS chưa hợp lệ. Hãy di chuyển quanh khu đất để tạo ít nhất 3 điểm khác nhau và diện tích lớn hơn 1 m².',
            ),
          ),
        );
      }
      return;
    }
    final accuracy = _lastPosition?.accuracy;
    if (accuracy != null && accuracy > 20) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS đang sai số ${accuracy.toStringAsFixed(1)} m. Hãy chờ tín hiệu tốt hơn.')));
      return;
    }
    final target = widget.existingField;
    final result = await showDialog<({String name, String crop})>(
      context: context,
      builder: (_) => _GpsMeasurementDialog(
        existingField: target,
        initialName: _pendingSave?.name ?? target?.name ??
            'Lô GPS ${DateTime.now().millisecondsSinceEpoch % 10000}',
        initialCrop: _pendingSave?.crop ?? target?.crop ?? '',
        area: _area, perimeter: _perimeter, accuracy: accuracy,
      ),
    );
    if (result == null || !mounted) return;
    final name = result.name;
    final crop = result.crop;
    setState(() => _saving = true);
    final field = FieldModel(
      id: target?.id ?? _pendingSave?.id ?? 'GPS-${DateTime.now().millisecondsSinceEpoch}',
      name: name.isEmpty ? 'Lô chưa đặt tên' : name,
      area: _area,
      crop: crop.isEmpty ? 'Chưa xác định' : crop,
      status: target?.status ?? 'Mới đo GPS',
      photoPaths: target?.photoPaths ?? const [],
      polygon: List.unmodifiable(_points),
      perimeter: _perimeter,
      measurementMethod: 'gps',
      gpsAccuracy: accuracy,
      measuredAt: _pendingSave?.measuredAt ?? DateTime.now().toUtc(),
    );
    _pendingSave = field;
    try {
      if (widget.persistResult) {
        final save = widget.saveOverride ?? (target == null
            ? FieldProvider().createMeasuredFieldLocally
            : FieldProvider().saveBoundaryLocally);
        await save(field);
      }
      if (!mounted) return;
      Navigator.pop(context, field);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không thể lưu thửa và lịch sử đo đạc. Vui lòng thử lại.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<Polyline> get _polylines => {if (_points.length >= 2) Polyline(polylineId: const PolylineId('field-boundary'), points: _points, width: 5)};
  Set<Polygon> get _polygons => {if (_points.length >= 3) Polygon(polygonId: const PolygonId('measured-field'), points: _points, strokeWidth: 2, fillColor: Colors.green.withValues(alpha: 0.18))};

  @override
  Widget build(BuildContext context) {
    final initial = _lastPosition == null ? const LatLng(16.55, 104.75) : LatLng(_lastPosition!.latitude, _lastPosition!.longitude);
    return Scaffold(
      appBar: AppBar(title: const Text('Đo thửa ruộng bằng GPS'), actions: [
        IconButton(tooltip: 'Xóa điểm cuối', onPressed: _points.isEmpty || _saving ? null : _undoLastPoint, icon: const Icon(Icons.undo)),
        IconButton(tooltip: 'Lưu thửa', onPressed: _recording || _saving || _points.length < 3 ? null : _saveField, icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save)),
      ]),
      body: Stack(children: [
        widget.mapBuilder?.call() ?? GoogleMap(
          initialCameraPosition: CameraPosition(target: initial, zoom: 17),
          myLocationEnabled: true, myLocationButtonEnabled: true, compassEnabled: true,
          polygons: _polygons, polylines: _polylines,
          markers: {for (var i = 0; i < _points.length; i++) Marker(markerId: MarkerId('point-$i'), position: _points[i], infoWindow: InfoWindow(title: 'Điểm ${i + 1}'))},
          onMapCreated: (controller) => _mapController = controller,
        ),
        Positioned(left: 12, right: 12, top: 12, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          const Icon(Icons.square_foot, color: Colors.green), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_area.toStringAsFixed(1)} m² • ${(_area / 10000).toStringAsFixed(4)} ha', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Chu vi: ${_perimeter.toStringAsFixed(1)} m • ${_points.length} điểm'),
          ])),
          if (_lastPosition != null) Text('${_lastPosition!.accuracy.toStringAsFixed(1)} m'),
        ]))),),
        Positioned(left: 16, right: 16, bottom: 20, child: SafeArea(child: Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _saving ? null : (_recording ? _stopMeasurement : _startMeasurement), icon: Icon(_recording ? Icons.stop : Icons.gps_fixed), label: Text(_recording ? 'DỪNG ĐO' : 'BẮT ĐẦU ĐO GPS'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)))),
          if (!_recording && _points.length >= 3) ...[const SizedBox(width: 10), SizedBox(height: 54, child: FilledButton(onPressed: _saving ? null : _saveField, child: const Icon(Icons.save)))],
        ]))),
      ]),
    );
  }
}


class _GpsMeasurementDialog extends StatefulWidget {
  const _GpsMeasurementDialog({required this.existingField,
    required this.initialName, required this.initialCrop,
    required this.area, required this.perimeter, required this.accuracy});

  final FieldModel? existingField;
  final String initialName;
  final String initialCrop;
  final double area;
  final double perimeter;
  final double? accuracy;

  @override
  State<_GpsMeasurementDialog> createState() => _GpsMeasurementDialogState();
}

class _GpsMeasurementDialogState extends State<_GpsMeasurementDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _crop = TextEditingController(text: widget.initialCrop);

  @override
  void dispose() {
    _name.dispose();
    _crop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existingField == null
        ? 'Lưu thửa GPS' : 'Cập nhật ranh giới GPS'),
    content: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.existingField == null) ...[
          TextField(controller: _name,
            decoration: const InputDecoration(labelText: 'Tên lô')),
          const SizedBox(height: 12),
          TextField(controller: _crop,
            decoration: const InputDecoration(labelText: 'Cây trồng')),
        ] else Text(widget.existingField!.name),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: Text(
          '${widget.area.toStringAsFixed(1)} m² • ${(widget.area / 10000).toStringAsFixed(4)} ha\n'
          'Chu vi ${widget.perimeter.toStringAsFixed(1)} m\n'
          'Độ chính xác cuối: ${(widget.accuracy ?? 0).toStringAsFixed(1)} m')),
      ],
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
      FilledButton(key: const Key('gps-confirm-save'),
        onPressed: () => Navigator.pop(context,
          (name: _name.text.trim(), crop: _crop.text.trim())),
        child: Text(widget.existingField == null ? 'Lưu thửa' : 'Lưu ranh giới')),
    ],
  );
}
