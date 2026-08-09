import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/distance_measurement.dart';
import '../services/field_storage_service.dart';

class DistanceMeasureScreen extends StatefulWidget {
  const DistanceMeasureScreen({super.key});

  @override
  State<DistanceMeasureScreen> createState() => _DistanceMeasureScreenState();
}

class _DistanceMeasureScreenState extends State<DistanceMeasureScreen> {
  final _storage = FieldStorageService();
  final List<LatLng> _points = [];
  final List<double> _segments = [];
  GoogleMapController? _mapController;
  bool _saving = false;

  double get _total => _segments.fold(0, (sum, value) => sum + value);

  Future<void> _addPoint(LatLng point) async {
    if (_saving) return;
    if (_points.isNotEmpty) {
      final previous = _points.last;
      final distance = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );
      _segments.add(distance);
    }
    setState(() => _points.add(point));
  }

  void _undo() {
    if (_points.isEmpty || _saving) return;
    setState(() {
      _points.removeLast();
      if (_segments.isNotEmpty) _segments.removeLast();
    });
  }

  void _clear() {
    if (_saving) return;
    setState(() {
      _points.clear();
      _segments.clear();
    });
  }

  Future<void> _save() async {
    if (_saving || _points.length < 2) return;
    setState(() => _saving = true);
    final measurement = DistanceMeasurement(
      id: 'DIST-${DateTime.now().millisecondsSinceEpoch}',
      points: List.unmodifiable(_points),
      segmentDistances: List.unmodifiable(_segments),
      totalDistance: _total,
      measuredAt: DateTime.now().toUtc(),
    );
    try {
      await _storage.saveDistanceMeasurement(measurement);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu phép đo khoảng cách vào AGRICO.')),
      );
      Navigator.pop(context, measurement);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(3)} km';
    return '${meters.toStringAsFixed(2)} m';
  }

  @override
  Widget build(BuildContext context) {
    final center = _points.isNotEmpty ? _points.last : const LatLng(16.55, 104.75);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đo khoảng cách thủ công'),
        actions: [
          IconButton(tooltip: 'Lịch sử', icon: const Icon(Icons.history), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DistanceHistoryScreen()))),
          IconButton(tooltip: 'Xóa điểm cuối', icon: const Icon(Icons.undo), onPressed: _points.isEmpty ? null : _undo),
          IconButton(tooltip: 'Xóa tất cả', icon: const Icon(Icons.delete_outline), onPressed: _points.isEmpty ? null : _clear),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 16),
            mapType: MapType.satellite,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: {
              for (var i = 0; i < _points.length; i++)
                Marker(
                  markerId: MarkerId('distance-$i'),
                  position: _points[i],
                  infoWindow: InfoWindow(title: 'Điểm ${i + 1}'),
                  draggable: true,
                  onDragEnd: (newPosition) => _movePoint(i, newPosition),
                ),
            },
            polylines: {
              if (_points.length >= 2)
                Polyline(
                  polylineId: const PolylineId('distance-line'),
                  points: _points,
                  width: 5,
                ),
            },
            onTap: _addPoint,
            onMapCreated: (controller) => _mapController = controller,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tổng: ${_formatDistance(_total)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${_points.length} điểm • ${_segments.length} đoạn'),
                    if (_segments.isNotEmpty)
                      Text('Đoạn cuối: ${_formatDistance(_segments.last)}'),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: SafeArea(
              child: FilledButton.icon(
                onPressed: _points.length >= 2 && !_saving ? _save : null,
                icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: Text(_points.length < 2 ? 'Chạm ít nhất 2 điểm trên bản đồ' : 'LƯU PHÉP ĐO'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _movePoint(int index, LatLng position) {
    setState(() {
      _points[index] = position;
      _recalculateSegments();
    });
  }

  void _recalculateSegments() {
    _segments
      ..clear()
      ..addAll(List<double>.generate(
        _points.length > 1 ? _points.length - 1 : 0,
        (i) => Geolocator.distanceBetween(
          _points[i].latitude,
          _points[i].longitude,
          _points[i + 1].latitude,
          _points[i + 1].longitude,
        ),
      ));
  }
}

class DistanceHistoryScreen extends StatefulWidget {
  const DistanceHistoryScreen({super.key});

  @override
  State<DistanceHistoryScreen> createState() => _DistanceHistoryScreenState();
}

class _DistanceHistoryScreenState extends State<DistanceHistoryScreen> {
  final _storage = FieldStorageService();
  late Future<List<DistanceMeasurement>> _future;

  @override
  void initState() {
    super.initState();
    _future = _storage.loadDistanceMeasurements();
  }

  String _formatDistance(double meters) => meters >= 1000 ? '${(meters / 1000).toStringAsFixed(3)} km' : '${meters.toStringAsFixed(2)} m';

  Future<void> _delete(DistanceMeasurement item) async {
    await _storage.deleteDistanceMeasurement(item.id);
    if (mounted) setState(() => _future = _storage.loadDistanceMeasurements());
  }

  void _showMap(DistanceMeasurement item) {
    if (item.points.length < 2) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            ListTile(
              title: Text('Tổng: ${_formatDistance(item.totalDistance)}'),
              subtitle: Text('${item.points.length} điểm • ${item.segmentDistances.length} đoạn'),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ),
            Expanded(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: item.points.first, zoom: 17),
                mapType: MapType.satellite,
                markers: {
                  for (var i = 0; i < item.points.length; i++) Marker(markerId: MarkerId('history-distance-$i'), position: item.points[i], infoWindow: InfoWindow(title: 'Điểm ${i + 1}')),
                },
                polylines: {Polyline(polylineId: const PolylineId('history-distance-line'), points: item.points, width: 5)},
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử đo khoảng cách')),
      body: FutureBuilder<List<DistanceMeasurement>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Không tải được lịch sử: ${snapshot.error}'));
          final items = snapshot.data ?? const <DistanceMeasurement>[];
          if (items.isEmpty) return const Center(child: Text('Chưa có phép đo khoảng cách.'));
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _storage.loadDistanceMeasurements()),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final date = item.measuredAt.toLocal();
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.straighten)),
                    title: Text(_formatDistance(item.totalDistance), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${item.points.length} điểm • ${item.segmentDistances.length} đoạn\n${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) { if (value == 'delete') _delete(item); },
                      itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Xóa phép đo'))],
                    ),
                    onTap: () => _showMap(item),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
