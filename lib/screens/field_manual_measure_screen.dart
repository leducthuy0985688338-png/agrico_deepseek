import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/distance_measurement_model.dart';
import '../models/field_model.dart';
import '../providers/field_provider.dart';
import '../services/cloud_service.dart';
import '../services/gps_field_service.dart';

enum _MeasureMode { field, distance }

class FieldManualMeasureScreen extends StatefulWidget {
  const FieldManualMeasureScreen({super.key});
  @override
  State<FieldManualMeasureScreen> createState() => _FieldManualMeasureScreenState();
}

class _FieldManualMeasureScreenState extends State<FieldManualMeasureScreen> {
  final _gps = GpsFieldService();
  final _fieldProvider = FieldProvider();
  final List<LatLng> _points = [];
  GoogleMapController? _mapController;
  _MeasureMode _mode = _MeasureMode.field;
  bool _saving = false;

  double get _area => _gps.calculateAreaSquareMeters(_points);
  double get _perimeter => _gps.calculatePerimeterMeters(_points);
  double get _distance => _points.length < 2 ? 0 : Geolocator.distanceBetween(_points[0].latitude, _points[0].longitude, _points[1].latitude, _points[1].longitude);

  void _addPoint(LatLng point) {
    if (_mode == _MeasureMode.distance && _points.length >= 2) {
      setState(() { _points..clear()..add(point); });
      return;
    }
    setState(() => _points.add(point));
  }

  void _undo() { if (_points.isNotEmpty) setState(() => _points.removeLast()); }
  void _clear() => setState(_points.clear);

  Set<Marker> get _markers => {
    for (var i = 0; i < _points.length; i++)
      Marker(
        markerId: MarkerId('manual-$i'),
        position: _points[i],
        infoWindow: InfoWindow(title: _mode == _MeasureMode.distance ? (i == 0 ? 'Điểm A' : 'Điểm B') : 'Điểm ${i + 1}'),
        draggable: true,
        onDragEnd: (position) => setState(() => _points[i] = position),
      ),
  };

  Set<Polyline> get _lines => {
    if (_points.length >= 2) Polyline(polylineId: const PolylineId('manual-line'), points: _points, width: 5),
  };

  Set<Polygon> get _polygon => {
    if (_mode == _MeasureMode.field && _points.length >= 3)
      Polygon(polygonId: const PolygonId('manual-field'), points: _points, strokeWidth: 3, fillColor: Colors.green.withValues(alpha: 0.20)),
  };

  Future<void> _saveField() async {
    if (_saving || _points.length < 3) return;
    final nameController = TextEditingController(text: 'Lô mới ${DateTime.now().millisecondsSinceEpoch % 10000}');
    final cropController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Lưu thửa thủ công'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Tên lô')),
          const SizedBox(height: 12),
          TextField(controller: cropController, decoration: const InputDecoration(labelText: 'Cây trồng')),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: Text('${_area.toStringAsFixed(1)} m² • ${(_area / 10000).toStringAsFixed(4)} ha\nChu vi ${_perimeter.toStringAsFixed(1)} m')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu thửa')),
        ],
      ),
    );
    final name = nameController.text.trim();
    final crop = cropController.text.trim();
    nameController.dispose(); cropController.dispose();
    if (result != true || !mounted) return;
    setState(() => _saving = true);
    final field = FieldModel(
      id: 'MAN-${DateTime.now().millisecondsSinceEpoch}',
      name: name.isEmpty ? 'Lô chưa đặt tên' : name,
      area: _area,
      crop: crop.isEmpty ? 'Chưa xác định' : crop,
      status: 'Mới đo thủ công',
      polygon: List.unmodifiable(_points),
      perimeter: _perimeter,
      measurementMethod: 'manual',
      measuredAt: DateTime.now().toUtc(),
    );
    _fieldProvider.addField(field);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu thửa thủ công vào AGRICO.')));
    Navigator.pop(context, field);
  }

  Future<void> _saveDistance() async {
    if (_saving || _points.length < 2) return;
    setState(() => _saving = true);
    final measurement = DistanceMeasurementModel(
      id: 'DIST-${DateTime.now().millisecondsSinceEpoch}',
      start: _points[0], end: _points[1], distanceMeters: _distance,
      measuredAt: DateTime.now().toUtc(), method: 'manual',
    );
    try {
      await CloudService.saveDistanceMeasurement(measurement);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu phép đo khoảng cách lên Firebase.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đo xong. Firebase chưa sẵn sàng, phép đo vẫn giữ trên màn hình.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == _MeasureMode.field ? 'Vẽ thửa thủ công' : 'Đo khoảng cách'),
        actions: [
          IconButton(tooltip: 'Hoàn tác', onPressed: _points.isEmpty || _saving ? null : _undo, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Xóa', onPressed: _points.isEmpty || _saving ? null : _clear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: LatLng(16.55, 104.75), zoom: 14),
          mapType: MapType.satellite, myLocationEnabled: true, myLocationButtonEnabled: true, compassEnabled: true,
          markers: _markers, polylines: _lines, polygons: _polygon,
          onMapCreated: (controller) => _mapController = controller,
          onTap: _addPoint,
        ),
        Positioned(left: 12, right: 12, top: 12, child: Card(child: Padding(
          padding: const EdgeInsets.all(10),
          child: SegmentedButton<_MeasureMode>(
            segments: const [
              ButtonSegment(value: _MeasureMode.field, icon: Icon(Icons.crop_square), label: Text('Đo thửa')),
              ButtonSegment(value: _MeasureMode.distance, icon: Icon(Icons.straighten), label: Text('Khoảng cách')),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() { _mode = value.first; _points.clear(); }),
          ),
        ))),
        Positioned(left: 12, right: 12, bottom: 18, child: SafeArea(child: Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _mode == _MeasureMode.field
                  ? '${_area.toStringAsFixed(1)} m²  •  ${(_area / 10000).toStringAsFixed(4)} ha  •  Chu vi ${_perimeter.toStringAsFixed(1)} m'
                  : (_points.length < 2 ? 'Chạm điểm A rồi điểm B' : 'A → B: ${_distance.toStringAsFixed(2)} m'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(_mode == _MeasureMode.field ? '${_points.length} điểm • Có thể kéo marker để chỉnh ranh giới.' : 'Có thể kéo A/B để chỉnh phép đo.'),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _saving || (_mode == _MeasureMode.field ? _points.length < 3 : _points.length < 2) ? null : (_mode == _MeasureMode.field ? _saveField : _saveDistance),
              icon: Icon(_mode == _MeasureMode.field ? Icons.save : Icons.save_alt),
              label: Text(_mode == _MeasureMode.field ? 'LƯU THỬA' : 'LƯU PHÉP ĐO'),
            )),
          ]),
        )))),
      ]),
    );
  }
}
