import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/gps_field_measurement_service.dart';

class GpsFieldMeasurementScreen extends StatefulWidget {
  final LatLng? initialCenter;
  const GpsFieldMeasurementScreen({super.key, this.initialCenter});

  @override
  State<GpsFieldMeasurementScreen> createState() => _GpsFieldMeasurementScreenState();
}

class _GpsFieldMeasurementScreenState extends State<GpsFieldMeasurementScreen> {
  final _gps = GpsFieldMeasurementService();
  final List<LatLng> _points = [];
  StreamSubscription<LatLng>? _subscription;
  GoogleMapController? _map;
  LatLng? _current;
  double _accuracy = 0;
  bool _measuring = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subscription?.cancel();
    _gps.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _error = null; _points.clear(); _measuring = false; });
    try {
      final position = await _gps.currentPosition();
      _setCurrent(position);
      setState(() => _measuring = true);
      _subscription = _gps.positionStream().listen(_onPosition, onError: (Object e) => setState(() => _error = e.toString()));
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _onPosition(LatLng point) {
    _setCurrent(point);
    if (!_measuring) return;
    if (_points.isEmpty || _gps.distanceBetween(_points.last, point) >= 3) {
      setState(() => _points.add(point));
    }
  }

  void _setCurrent(LatLng point) {
    setState(() => _current = point);
    _map?.animateCamera(CameraUpdate.newLatLng(point));
  }

  Future<void> _finish() async {
    if (_points.length < 3) {
      setState(() => _error = 'Cần ít nhất 3 điểm GPS để tạo thửa.');
      return;
    }
    await _subscription?.cancel();
    setState(() { _measuring = false; _saving = true; });
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, GpsMeasurementResult(points: List.unmodifiable(_points), areaSquareMeters: _gps.areaSquareMeters(_points), perimeterMeters: _gps.perimeterMeters(_points), accuracyMeters: _accuracy));
  }

  void _clear() {
    _subscription?.cancel();
    setState(() { _points.clear(); _measuring = false; _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    final center = _current ?? widget.initialCenter ?? const LatLng(17.9757, 102.6331);
    final area = _gps.areaSquareMeters(_points);
    final perimeter = _gps.perimeterMeters(_points);
    return Scaffold(
      appBar: AppBar(title: const Text('Đo thửa bằng GPS')),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 17),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          mapType: MapType.satellite,
          onMapCreated: (c) => _map = c,
          polygons: _points.length >= 3 ? {Polygon(polygonId: const PolygonId('measuring'), points: _points, strokeWidth: 3, fillColor: Colors.green.withValues(alpha: .22))} : {},
          polylines: _points.length >= 2 ? {Polyline(polylineId: const PolylineId('boundary'), points: _points, width: 4)} : {},
          markers: _current == null ? {} : {Marker(markerId: const MarkerId('current'), position: _current!)},
        ),
        Positioned(top: 12, left: 12, right: 12, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Điểm: ${_points.length}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('GPS: ±${_accuracy.toStringAsFixed(1)} m')]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Diện tích: ${_formatArea(area)}'), Text('Chu vi: ${perimeter.toStringAsFixed(1)} m')]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]))),),
        Positioned(bottom: 20, left: 16, right: 16, child: Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _clear, icon: const Icon(Icons.refresh), label: const Text('Làm lại'))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: FilledButton.icon(onPressed: _saving ? null : (_measuring ? _finish : _start), icon: Icon(_measuring ? Icons.check : Icons.play_arrow), label: Text(_saving ? 'Đang lưu...' : (_measuring ? 'Hoàn tất & lưu' : 'Bắt đầu đo')))),
        ])),
      ]),
    );
  }

  String _formatArea(double m2) => m2 >= 10000 ? '${(m2 / 10000).toStringAsFixed(3)} ha' : '${m2.toStringAsFixed(1)} m²';
}

class GpsMeasurementResult {
  final List<LatLng> points;
  final double areaSquareMeters;
  final double perimeterMeters;
  final double accuracyMeters;
  const GpsMeasurementResult({required this.points, required this.areaSquareMeters, required this.perimeterMeters, required this.accuracyMeters});
}
