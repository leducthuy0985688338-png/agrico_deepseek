import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';
import 'field_detail_screen.dart';
import 'field_gps_measure_screen.dart';

class FieldMapScreen extends StatefulWidget {
  const FieldMapScreen({super.key});

  @override
  State<FieldMapScreen> createState() => _FieldMapScreenState();
}

class _FieldMapScreenState extends State<FieldMapScreen> {
  final _provider = FieldProvider();
  GoogleMapController? _controller;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bản đồ trang trại'),
        actions: [
          IconButton(
            tooltip: 'Đo thửa mới',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen()),
            ),
            icon: const Icon(Icons.gps_fixed),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) {
          final fields = _provider.fields.where((f) => f.polygon.length >= 3).toList();
          final selected = _selectedId == null
              ? null
              : _provider.getFieldById(_selectedId!);
          final center = _centerFor(fields, selected);

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: center, zoom: 14),
                mapType: MapType.satellite,
                myLocationButtonEnabled: true,
                myLocationEnabled: true,
                polygons: {
                  for (final field in fields)
                    Polygon(
                      polygonId: PolygonId(field.id),
                      points: field.polygon,
                      strokeWidth: field.id == _selectedId ? 4 : 2,
                      fillColor: Colors.green.withValues(
                        alpha: field.id == _selectedId ? 0.30 : 0.16,
                      ),
                      consumeTapEvents: true,
                      onTap: () => _selectField(field),
                    ),
                },
                markers: {
                  for (final field in fields)
                    Marker(
                      markerId: MarkerId('field-${field.id}'),
                      position: _centroid(field.polygon),
                      infoWindow: InfoWindow(
                        title: field.name,
                        snippet: '${(field.area / 10000).toStringAsFixed(2)} ha • ${field.crop}',
                      ),
                      onTap: () => _selectField(field),
                    ),
                },
                onMapCreated: (controller) => _controller = controller,
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
                        const Icon(Icons.map, color: Colors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${fields.length} thửa có ranh giới • ${_provider.fields.fold<double>(0, (sum, f) => sum + f.area) / 10000 .toStringAsFixed(2)} ha',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (selected != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: SafeArea(
                    child: Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.grass)),
                        title: Text(selected.name),
                        subtitle: Text(
                          '${selected.area.toStringAsFixed(1)} m² • ${selected.crop} • ${selected.status}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FieldDetailScreen(field: selected),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _selectField(FieldModel field) {
    setState(() => _selectedId = field.id);
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(_centroid(field.polygon), 17),
    );
  }

  LatLng _centerFor(List<FieldModel> fields, FieldModel? selected) {
    if (selected != null && selected.polygon.length >= 3) {
      return _centroid(selected.polygon);
    }
    if (fields.isNotEmpty) return _centroid(fields.first.polygon);
    return const LatLng(16.55, 104.75);
  }

  LatLng _centroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(16.55, 104.75);
    final lat = points.fold<double>(0, (sum, p) => sum + p.latitude) / points.length;
    final lng = points.fold<double>(0, (sum, p) => sum + p.longitude) / points.length;
    return LatLng(lat, lng);
  }
}
