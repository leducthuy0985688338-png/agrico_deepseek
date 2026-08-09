import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/gps_field_service.dart';

class FieldGpsMeasureScreen extends StatefulWidget {
  const FieldGpsMeasureScreen({super.key});

  @override
  State<FieldGpsMeasureScreen> createState() => _FieldGpsMeasureScreenState();
}

class _FieldGpsMeasureScreenState extends State<FieldGpsMeasureScreen> {
  final _gps = GpsFieldService();
  final List<LatLng> _points = [];
  StreamSubscription<Position>? _subscription;
  GoogleMapController? _mapController;
  Position? _lastPosition;
  bool _recording = false;

  double get _area => _gps.calculateAreaSquareMeters(_points);
  double get _perimeter => _gps.calculatePerimeterMeters(_points);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startMeasurement() async {
    if (!await _gps.ensureLocationReady()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy bật GPS và cấp quyền vị trí cho AGRICO.')),
      );
      return;
    }

    final current = await _gps.getCurrentPosition();
    if (current == null) return;

    setState(() {
      _recording = true;
      _points.clear();
      _lastPosition = current;
    });

    _addPosition(current);
    await _subscription?.cancel();
    _subscription = _gps.positionStream().listen(_addPosition);
  }

  void _addPosition(Position position) {
    _lastPosition = position;
    final point = LatLng(position.latitude, position.longitude);

    if (_points.isNotEmpty) {
      final last = _points.last;
      final distance = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < 2) {
        setState(() {});
        return;
      }
    }

    setState(() => _points.add(point));
    _mapController?.animateCamera(CameraUpdate.newLatLng(point));
  }

  Future<void> _stopMeasurement() async {
    await _subscription?.cancel();
    _subscription = null;
    setState(() => _recording = false);
  }

  void _undoLastPoint() {
    if (_points.isEmpty) return;
    setState(() => _points.removeLast());
  }

  Set<Polyline> get _polylines => {
        if (_points.length >= 2)
          Polyline(
            polylineId: const PolylineId('field-boundary'),
            points: _points,
            width: 5,
          ),
      };

  Set<Polygon> get _polygons => {
        if (_points.length >= 3)
          Polygon(
            polygonId: const PolygonId('measured-field'),
            points: _points,
            strokeWidth: 2,
            fillColor: Colors.green.withValues(alpha: 0.18),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final initial = _lastPosition == null
        ? const LatLng(16.55, 104.75)
        : LatLng(_lastPosition!.latitude, _lastPosition!.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đo thửa ruộng bằng GPS'),
        actions: [
          IconButton(
            tooltip: 'Xóa điểm cuối',
            onPressed: _points.isEmpty ? null : _undoLastPoint,
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initial, zoom: 17),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            polygons: _polygons,
            polylines: _polylines,
            markers: {
              for (var i = 0; i < _points.length; i++)
                Marker(
                  markerId: MarkerId('point-$i'),
                  position: _points[i],
                  infoWindow: InfoWindow(title: 'Điểm ${i + 1}'),
                ),
            },
            onMapCreated: (controller) => _mapController = controller,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.square_foot, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_area.toStringAsFixed(1)} m²  •  ${(_area / 10000).toStringAsFixed(4)} ha',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('Chu vi: ${_perimeter.toStringAsFixed(1)} m • ${_points.length} điểm'),
                        ],
                      ),
                    ),
                    if (_lastPosition != null)
                      Text('${_lastPosition!.accuracy.toStringAsFixed(1)} m'),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              child: FilledButton.icon(
                onPressed: _recording ? _stopMeasurement : _startMeasurement,
                icon: Icon(_recording ? Icons.stop : Icons.gps_fixed),
                label: Text(_recording ? 'DỪNG ĐO' : 'BẮT ĐẦU ĐO GPS'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
