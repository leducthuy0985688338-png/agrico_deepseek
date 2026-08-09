import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';
import 'field_detail_screen.dart';
import 'field_gps_measure_screen.dart';
import 'field_manual_measure_screen.dart';
import 'field_polygon_edit_screen.dart';

class FieldMapScreen extends StatefulWidget {
  const FieldMapScreen({super.key});
  @override
  State<FieldMapScreen> createState() => _FieldMapScreenState();
}

class _FieldMapScreenState extends State<FieldMapScreen> {
  final _provider = FieldProvider();
  GoogleMapController? _controller;
  String? _selectedId;

  Future<void> _openManualMeasurement() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const FieldManualMeasureScreen())); }
  Future<void> _openGpsMeasurement() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen())); }
  Future<void> _editSelectedField(FieldModel field) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FieldPolygonEditScreen(field: field)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bản đồ trang trại'), actions: [
        IconButton(tooltip: 'Đo thủ công trên bản đồ', onPressed: _openManualMeasurement, icon: const Icon(Icons.edit_location_alt)),
        IconButton(tooltip: 'Đo thửa bằng GPS', onPressed: _openGpsMeasurement, icon: const Icon(Icons.gps_fixed)),
      ]),
      body: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) {
          final fields = _provider.fields.where((f) => f.polygon.length >= 3).toList();
          final selected = _selectedId == null ? null : _provider.getFieldById(_selectedId!);
          final center = _centerFor(fields, selected);
          final totalArea = _provider.fields.fold<double>(0, (sum, f) => sum + f.area);
          return Stack(children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: 14),
              mapType: MapType.satellite, myLocationButtonEnabled: true, myLocationEnabled: true,
              polygons: {for (final field in fields) Polygon(polygonId: PolygonId(field.id), points: field.polygon, strokeWidth: field.id == _selectedId ? 4 : 2, fillColor: Colors.green.withValues(alpha: field.id == _selectedId ? 0.30 : 0.16), consumeTapEvents: true, onTap: () => _selectField(field))},
              markers: {for (final field in fields) Marker(markerId: MarkerId('field-${field.id}'), position: _centroid(field.polygon), infoWindow: InfoWindow(title: field.name, snippet: '${(field.area / 10000).toStringAsFixed(2)} ha • ${field.crop}'), onTap: () => _selectField(field))},
              onMapCreated: (controller) => _controller = controller,
            ),
            Positioned(left: 12, right: 12, top: 12, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.map, color: Colors.green), const SizedBox(width: 10), Expanded(child: Text('${fields.length} thửa có ranh giới • ${(totalArea / 10000).toStringAsFixed(2)} ha', style: const TextStyle(fontWeight: FontWeight.w600)))])))),
            Positioned(right: 12, bottom: selected == null ? 18 : 92, child: FloatingActionButton.extended(heroTag: 'map-tools', onPressed: () => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(leading: Icon(Icons.straighten), title: Text('Công cụ đo'), subtitle: Text('Đo thửa và khoảng cách trực tiếp trên bản đồ')),
              ListTile(leading: const Icon(Icons.edit_location_alt), title: const Text('Vẽ thửa thủ công'), onTap: () { Navigator.pop(context); _openManualMeasurement(); }),
              ListTile(leading: const Icon(Icons.gps_fixed), title: const Text('Đo thửa bằng GPS'), onTap: () { Navigator.pop(context); _openGpsMeasurement(); }),
              if (selected != null) ListTile(leading: const Icon(Icons.edit), title: const Text('Chỉnh sửa ranh giới thửa đang chọn'), onTap: () { Navigator.pop(context); _editSelectedField(selected); }),
            ])))), icon: const Icon(Icons.straighten), label: const Text('Công cụ đo'))),
            if (selected != null) Positioned(left: 12, right: 12, bottom: 16, child: SafeArea(child: Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.grass)),
              title: Text(selected.name),
              subtitle: Text('${selected.area.toStringAsFixed(1)} m² • ${selected.crop} • ${selected.status}'),
              trailing: Wrap(spacing: 2, children: [IconButton(tooltip: 'Chỉnh ranh giới', onPressed: () => _editSelectedField(selected), icon: const Icon(Icons.edit)), const Icon(Icons.chevron_right)]),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FieldDetailScreen(field: selected))),
            )))),
          ]);
        },
      ),
    );
  }

  void _selectField(FieldModel field) { setState(() => _selectedId = field.id); _controller?.animateCamera(CameraUpdate.newLatLngZoom(_centroid(field.polygon), 17)); }
  LatLng _centerFor(List<FieldModel> fields, FieldModel? selected) { if (selected != null && selected.polygon.length >= 3) return _centroid(selected.polygon); if (fields.isNotEmpty) return _centroid(fields.first.polygon); return const LatLng(16.55, 104.75); }
  LatLng _centroid(List<LatLng> points) { if (points.isEmpty) return const LatLng(16.55, 104.75); final lat = points.fold<double>(0, (sum, p) => sum + p.latitude) / points.length; final lng = points.fold<double>(0, (sum, p) => sum + p.longitude) / points.length; return LatLng(lat, lng); }
}
