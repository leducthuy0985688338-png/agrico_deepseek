import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_measurement_history.dart';
import '../models/field_model.dart';
import '../services/field_storage_service.dart';
import 'field_polygon_edit_screen.dart';

class FieldMeasurementHistoryScreen extends StatefulWidget {
  final FieldModel? field;
  const FieldMeasurementHistoryScreen({super.key, this.field});

  @override
  State<FieldMeasurementHistoryScreen> createState() => _FieldMeasurementHistoryScreenState();
}

class _FieldMeasurementHistoryScreenState extends State<FieldMeasurementHistoryScreen> {
  final _storage = FieldStorageService();
  late Future<List<FieldMeasurementHistory>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _storage.loadMeasurementHistory(fieldId: widget.field?.id);
  }

  String _methodLabel(String method) {
    if (method.startsWith('gps')) return 'GPS';
    if (method.startsWith('manual')) return 'THỦ CÔNG';
    if (method.contains('edited')) return 'ĐÃ CHỈNH';
    return method.toUpperCase();
  }

  void _showMap(FieldMeasurementHistory item) {
    if (item.polygon.isEmpty) return;
    final center = item.polygon.first;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            ListTile(
              title: Text(item.fieldName),
              subtitle: Text('${item.area.toStringAsFixed(1)} m² • ${item.perimeter.toStringAsFixed(1)} m'),
              trailing: IconButton(
                tooltip: 'Đóng',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: center, zoom: 17),
                mapType: MapType.satellite,
                markers: {
                  for (var i = 0; i < item.polygon.length; i++)
                    Marker(markerId: MarkerId('history-$i'), position: item.polygon[i], infoWindow: InfoWindow(title: 'Điểm ${i + 1}')),
                },
                polygons: item.polygon.length >= 3
                    ? {Polygon(polygonId: const PolygonId('history'), points: item.polygon, strokeWidth: 3, fillColor: Colors.green.withValues(alpha: .20))}
                    : {},
                polylines: item.polygon.length >= 2
                    ? {Polyline(polylineId: const PolylineId('history-line'), points: [...item.polygon, item.polygon.first], width: 3)}
                    : {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCurrentFieldEditor() async {
    final field = widget.field;
    if (field == null || field.polygon.length < 3) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FieldPolygonEditScreen(field: field)));
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.field == null ? 'Lịch sử đo đạc' : 'Lịch sử: ${widget.field!.name}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.field != null)
            IconButton(
              tooltip: 'Chỉnh ranh hiện tại',
              icon: const Icon(Icons.edit_location_alt),
              onPressed: _openCurrentFieldEditor,
            ),
        ],
      ),
      body: FutureBuilder<List<FieldMeasurementHistory>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Không tải được lịch sử: ${snapshot.error}'));
          final items = snapshot.data ?? const <FieldMeasurementHistory>[];
          if (items.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Chưa có lịch sử đo đạc. Khi đo hoặc chỉnh ranh, AGRICO sẽ tự lưu phiên bản tại đây.', textAlign: TextAlign.center)));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(_reload),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final date = item.measuredAt.toLocal();
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Row(children: [
                      Expanded(child: Text(_methodLabel(item.measurementMethod), style: const TextStyle(fontWeight: FontWeight.bold))),
                      Text('${item.area.toStringAsFixed(2)} m²', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Chu vi: ${item.perimeter.toStringAsFixed(1)} m\n${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} • ${item.polygon.length} điểm${item.gpsAccuracy == null ? '' : ' • GPS ±${item.gpsAccuracy!.toStringAsFixed(1)} m'}'),
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.map_outlined),
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
