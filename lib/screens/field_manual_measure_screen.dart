import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/gps_field_service.dart';

class FieldManualMeasureScreen extends StatefulWidget {
  const FieldManualMeasureScreen({super.key});

  @override
  State<FieldManualMeasureScreen> createState() => _FieldManualMeasureScreenState();
}

enum _MeasureMode { field, distance }

class _FieldManualMeasureScreenState extends State<FieldManualMeasureScreen> {
  final _gps = GpsFieldService();
  final List<LatLng> _points = [];
  GoogleMapController? _mapController;
  _MeasureMode _mode = _MeasureMode.field;

  double get _area => _gps.calculateAreaSquareMeters(_points);

  double get _perimeter => _gps.calculatePerimeterMeters(_points);

  double get _distance {
    if (_points.length < 2) return 0;
    return Geolocator.distanceBetween(
      _points[0].latitude,
      _points[0].longitude,
      _points[1].latitude,
      _points[1].longitude,
    );
  }

  void _addPoint(LatLng point) {
    if (_mode == _MeasureMode.distance && _points.length >= 2) {
      setState(() {
        _points
          ..clear()
          ..add(point);
      });
      return;
    }
    setState(() => _points.add(point));
  }

  void _undo() {
    if (_points.isEmpty) return;
    setState(() => _points.removeLast());
  }

  void _clear() => setState(_points.clear);

  Set<Marker> get _markers => {
        for (var i = 0; i < _points.length; i++)
          Marker(
            markerId: MarkerId('manual-$i'),
            position: _points[i],
            infoWindow: InfoWindow(title: 'Điểm ${i + 1}'),
            draggable: true,
            onDragEnd: (position) => setState(() => _points[i] = position),
          ),
      };

  Set<Polyline> get _lines => {
        if (_points.length >= 2)
          Polyline(
            polylineId: const PolylineId('manual-line'),
            points: _points,
            width: 5,
          ),
      };

  Set<Polygon> get _polygon => {
        if (_mode == _MeasureMode.field && _points.length >= 3)
          Polygon(
            polygonId: const PolygonId('manual-field'),
            points: _points,
            strokeWidth: 3,
            fillColor: Colors.green.withValues(alpha: 0.20),
          ),
      };

  void _finishField() {
    if (_points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần ít nhất 3 điểm để tạo thửa.')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kết quả đo thủ công'),
        content: Text(
          'Diện tích: ${_area.toStringAsFixed(1)} m²\n'
          'Diện tích: ${(_area / 10000).toStringAsFixed(4)} ha\n'
          'Chu vi: ${_perimeter.toStringAsFixed(1)} m\n'
          'Số điểm: ${_points.length}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == _MeasureMode.field ? 'Vẽ thửa thủ công' : 'Đo khoảng cách'),
        actions: [
          IconButton(tooltip: 'Hoàn tác', onPressed: _points.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Xóa', onPressed: _points.isEmpty ? null : _clear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(16.55, 104.75), zoom: 14),
            mapType: MapType.satellite,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            markers: _markers,
            polylines: _lines,
            polygons: _polygon,
            onMapCreated: (controller) => _mapController = controller,
            onTap: _addPoint,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<_MeasureMode>(
                        segments: const [
                          ButtonSegment(value: _MeasureMode.field, icon: Icon(Icons.crop_square), label: Text('Đo thửa')),
                          ButtonSegment(value: _MeasureMode.distance, icon: Icon(Icons.straighten), label: Text('Khoảng cách')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (value) => setState(() {
                          _mode = value.first;
                          _points.clear();
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 18,
            child: SafeArea(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _mode == _MeasureMode.field
                            ? '${_area.toStringAsFixed(1)} m²  •  ${(_area / 10000).toStringAsFixed(4)} ha  •  Chu vi ${_perimeter.toStringAsFixed(1)} m'
                            : (_points.length < 2 ? 'Chạm điểm A rồi điểm B' : 'A → B: ${_distance.toStringAsFixed(2)} m'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(_mode == _MeasureMode.field ? '${_points.length} điểm • Chạm bản đồ để thêm điểm' : 'Có thể kéo marker để chỉnh vị trí.'),
                      if (_mode == _MeasureMode.field) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _points.length < 3 ? null : _finishField,
                            icon: const Icon(Icons.check),
                            label: const Text('HOÀN TẤT ĐO THỬA'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
