import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';
import '../services/gps_field_service.dart';

class FieldPolygonEditScreen extends StatefulWidget {
  final FieldModel field;
  const FieldPolygonEditScreen({super.key, required this.field});

  @override
  State<FieldPolygonEditScreen> createState() => _FieldPolygonEditScreenState();
}

class _FieldPolygonEditScreenState extends State<FieldPolygonEditScreen> {
  final _gps = GpsFieldService();
  final _provider = FieldProvider();
  late List<LatLng> _points;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _points = List<LatLng>.from(widget.field.polygon);
  }

  double get _area => _gps.calculateAreaSquareMeters(_points);
  double get _perimeter => _gps.calculatePerimeterMeters(_points);

  Set<Marker> get _markers => {
        for (var i = 0; i < _points.length; i++)
          Marker(
            markerId: MarkerId('edit-$i'),
            position: _points[i],
            draggable: true,
            infoWindow: InfoWindow(title: 'Điểm ${i + 1}'),
            onDragEnd: (position) => setState(() => _points[i] = position),
          ),
      };

  Set<Polygon> get _polygons => {
        if (_points.length >= 3)
          Polygon(
            polygonId: const PolygonId('editable-field'),
            points: _points,
            strokeWidth: 3,
            fillColor: Colors.green.withValues(alpha: 0.22),
          ),
      };

  Future<void> _save() async {
    if (_saving || _points.length < 3) return;
    setState(() => _saving = true);
    final updated = widget.field.copyWith(
      polygon: List.unmodifiable(_points),
      area: _area,
      perimeter: _perimeter,
      measurementMethod: '${widget.field.measurementMethod}+edited',
      measuredAt: DateTime.now().toUtc(),
    );
    _provider.updateField(updated);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật ranh giới và diện tích thửa.')));
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    final center = _points.isEmpty ? const LatLng(16.55, 104.75) : _points.first;
    return Scaffold(
      appBar: AppBar(
        title: Text('Chỉnh ranh: ${widget.field.name}'),
        actions: [
          IconButton(onPressed: _saving || _points.length < 3 ? null : _save, icon: _saving ? const CircularProgressIndicator() : const Icon(Icons.save), tooltip: 'Lưu thay đổi'),
        ],
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 17),
          mapType: MapType.satellite,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          markers: _markers,
          polygons: _polygons,
        ),
        Positioned(left: 12, right: 12, top: 12, child: Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_area.toStringAsFixed(1)} m² • ${(_area / 10000).toStringAsFixed(4)} ha', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Chu vi: ${_perimeter.toStringAsFixed(1)} m • ${_points.length} điểm'),
            const SizedBox(height: 4),
            const Text('Kéo các điểm trên bản đồ để chỉnh ranh giới.'),
          ]),
        ))),
        Positioned(left: 16, right: 16, bottom: 20, child: SafeArea(child: FilledButton.icon(
          onPressed: _saving || _points.length < 3 ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('LƯU RANH GIỚI MỚI'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ))),
      ]),
    );
  }
}
