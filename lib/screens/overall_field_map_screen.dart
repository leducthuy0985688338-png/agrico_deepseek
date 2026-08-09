import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';
import 'distance_measure_screen.dart';
import 'field_detail_screen.dart';
import 'field_gps_measure_screen.dart';
import 'field_manual_measure_screen.dart';
import 'field_polygon_edit_screen.dart';

class OverallFieldMapScreen extends StatefulWidget {
  const OverallFieldMapScreen({super.key});

  @override
  State<OverallFieldMapScreen> createState() => _OverallFieldMapScreenState();
}

class _OverallFieldMapScreenState extends State<OverallFieldMapScreen> {
  final _provider = FieldProvider();
  final _searchController = TextEditingController();
  GoogleMapController? _controller;
  String? _selectedId;
  String _cropFilter = 'Tất cả';
  String _statusFilter = 'Tất cả';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FieldModel> _filtered(List<FieldModel> source) {
    final query = _searchController.text.trim().toLowerCase();
    return source.where((field) {
      final searchOk = query.isEmpty ||
          field.id.toLowerCase().contains(query) ||
          field.name.toLowerCase().contains(query);
      final cropOk = _cropFilter == 'Tất cả' || field.crop == _cropFilter;
      final statusOk = _statusFilter == 'Tất cả' || field.status == _statusFilter;
      return searchOk && cropOk && statusOk;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bản đồ tổng thể AGRICO'),
        actions: [
          IconButton(
            tooltip: 'Bộ lọc',
            onPressed: _showFilters,
            icon: const Icon(Icons.filter_alt_outlined),
          ),
          IconButton(
            tooltip: 'Đo khoảng cách',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DistanceMeasureScreen()),
            ),
            icon: const Icon(Icons.straighten),
          ),
          IconButton(
            tooltip: 'Đo thủ công',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FieldManualMeasureScreen()),
            ),
            icon: const Icon(Icons.edit_location_alt),
          ),
          IconButton(
            tooltip: 'Đo GPS',
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
          final allFields = _provider.fields;
          final fields = _filtered(allFields)
              .where((field) => field.polygon.length >= 3)
              .toList(growable: false);
          final selected = _selectedId == null
              ? null
              : _provider.getFieldById(_selectedId!);
          final totalArea = fields.fold<double>(0, (sum, field) => sum + field.area);
          final center = selected != null
              ? _centroid(selected.polygon)
              : fields.isNotEmpty
                  ? _centroid(fields.first.polygon)
                  : const LatLng(16.55, 104.75);

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: center, zoom: 14),
                mapType: MapType.satellite,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                compassEnabled: true,
                zoomControlsEnabled: false,
                polygons: {
                  for (final field in fields)
                    Polygon(
                      polygonId: PolygonId(field.id),
                      points: field.polygon,
                      strokeWidth: field.id == _selectedId ? 5 : 2,
                      strokeColor: field.id == _selectedId ? Colors.yellow : Colors.green,
                      fillColor: field.id == _selectedId
                          ? Colors.yellow.withValues(alpha: 0.30)
                          : Colors.green.withValues(alpha: 0.16),
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
                onMapCreated: (controller) {
                  _controller = controller;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && fields.isNotEmpty) _fitAll(fields);
                  });
                },
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.map, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText: 'Tìm mã hoặc tên thửa...',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                          ],
                        ),
                        const Divider(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${fields.length}/${allFields.length} thửa • ${(totalArea / 10000).toStringAsFixed(2)} ha',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: fields.isEmpty ? null : () => _fitAll(fields),
                              icon: const Icon(Icons.fit_screen, size: 18),
                              label: const Text('Tất cả'),
                            ),
                          ],
                        ),
                        if (_cropFilter != 'Tất cả' || _statusFilter != 'Tất cả')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 6,
                              children: [
                                if (_cropFilter != 'Tất cả')
                                  Chip(
                                    label: Text(_cropFilter),
                                    onDeleted: () => setState(() => _cropFilter = 'Tất cả'),
                                  ),
                                if (_statusFilter != 'Tất cả')
                                  Chip(
                                    label: Text(_statusFilter),
                                    onDeleted: () => setState(() => _statusFilter = 'Tất cả'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: selected == null ? 18 : 96,
                child: SafeArea(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          _LegendDot(color: Colors.green, label: 'Thửa'),
                          SizedBox(width: 10),
                          _LegendDot(color: Colors.yellow, label: 'Đang chọn'),
                        ],
                      ),
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
                          '${selected.area.toStringAsFixed(1)} m² • ${selected.crop} • ${selected.status}\n${selected.perimeter.toStringAsFixed(1)} m • ${selected.measurementMethod}',
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'Chỉnh ranh',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FieldPolygonEditScreen(field: selected),
                                ),
                              ),
                              icon: const Icon(Icons.edit),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FieldDetailScreen(field: selected)),
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

  Future<void> _showFilters() async {
    final fields = _provider.fields;
    final crops = <String>{'Tất cả', ...fields.map((f) => f.crop).where((v) => v.isNotEmpty)}.toList();
    final statuses = <String>{'Tất cả', ...fields.map((f) => f.status).where((v) => v.isNotEmpty)}.toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bộ lọc bản đồ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Cây trồng'),
                DropdownButton<String>(
                  value: _cropFilter,
                  isExpanded: true,
                  items: crops.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setSheetState(() => _cropFilter = value);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                const Text('Trạng thái'),
                DropdownButton<String>(
                  value: _statusFilter,
                  isExpanded: true,
                  items: statuses.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setSheetState(() => _statusFilter = value);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _cropFilter = 'Tất cả';
                        _statusFilter = 'Tất cả';
                      });
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.filter_alt_off),
                    label: const Text('Xóa bộ lọc'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _fitAll(List<FieldModel> fields) {
    if (_controller == null || fields.isEmpty) return;
    final points = fields.expand((field) => field.polygon).toList();
    if (points.isEmpty) return;
    if (points.length == 1) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    if ((maxLat - minLat).abs() < 0.0001) {
      minLat -= 0.001;
      maxLat += 0.001;
    }
    if ((maxLng - minLng).abs() < 0.0001) {
      minLng -= 0.001;
      maxLng += 0.001;
    }
    _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        70,
      ),
    );
  }

  LatLng _centroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(16.55, 104.75);
    final lat = points.fold<double>(0, (sum, p) => sum + p.latitude) / points.length;
    final lng = points.fold<double>(0, (sum, p) => sum + p.longitude) / points.length;
    return LatLng(lat, lng);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
