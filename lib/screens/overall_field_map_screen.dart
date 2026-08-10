import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';
import '../services/farm_map_management_service.dart';
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

enum _MapLayer { crop, status, measurement }

class _OverallFieldMapScreenState extends State<OverallFieldMapScreen> {
  final _provider = FieldProvider();
  final _mapService = const FarmMapManagementService();
  final _searchController = TextEditingController();
  GoogleMapController? _controller;
  String? _selectedId;
  String _cropFilter = 'Tất cả';
  String _statusFilter = 'Tất cả';
  _MapLayer _layer = _MapLayer.crop;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FieldModel> _filtered(List<FieldModel> source) => _mapService.filterFields(
        source,
        query: _searchController.text,
        crop: _cropFilter,
        status: _statusFilter,
      );

  Color _fieldColor(FieldModel field) {
    if (_selectedId == field.id) return Colors.amber;
    if (_layer == _MapLayer.measurement) {
      switch (field.measurementMethod) {
        case 'gps': return Colors.blue;
        case 'manual': return Colors.orange;
        default: return Colors.grey;
      }
    }
    if (_layer == _MapLayer.status) return _statusColor(field.status);
    return _cropColor(field.crop);
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();
    if (value.contains('đang') || value.contains('sản xuất') || value.contains('trồng')) return Colors.green;
    if (value.contains('thu hoạch') || value.contains('hoàn')) return Colors.blue;
    if (value.contains('nghỉ') || value.contains('trống')) return Colors.orange;
    return Colors.grey;
  }

  Color _cropColor(String crop) {
    final palette = <Color>[Colors.green, Colors.blue, Colors.orange, Colors.purple, Colors.teal, Colors.indigo];
    var hash = 0;
    for (final code in crop.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return crop.isEmpty ? Colors.grey : palette[hash % palette.length];
  }

  String get _layerLabel {
    switch (_layer) {
      case _MapLayer.crop: return 'Cây trồng';
      case _MapLayer.status: return 'Trạng thái';
      case _MapLayer.measurement: return 'Phương pháp đo';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bản đồ tổng thể AGRICO'),
        actions: [
          IconButton(tooltip: 'Thống kê trang trại', onPressed: _showStatistics, icon: const Icon(Icons.analytics_outlined)),
          IconButton(tooltip: 'Lớp bản đồ', onPressed: _showLayers, icon: const Icon(Icons.layers_outlined)),
          IconButton(tooltip: 'Bộ lọc', onPressed: _showFilters, icon: const Icon(Icons.filter_alt_outlined)),
          IconButton(tooltip: 'Đo khoảng cách', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DistanceMeasureScreen())), icon: const Icon(Icons.straighten)),
          IconButton(tooltip: 'Đo thủ công', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FieldManualMeasureScreen())), icon: const Icon(Icons.edit_location_alt)),
          IconButton(tooltip: 'Đo GPS', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen())), icon: const Icon(Icons.gps_fixed)),
        ],
      ),
      body: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) {
          final allFields = _provider.fields;
          final fields = _filtered(allFields);
          final summary = _mapService.summarize(fields);
          final selected = _selectedId == null ? null : _provider.getFieldById(_selectedId!);
          final center = selected != null
              ? _centroid(selected.polygon)
              : fields.isNotEmpty ? _centroid(fields.first.polygon) : const LatLng(16.55, 104.75);

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
                    if (field.polygon.length >= 3)
                      Polygon(
                        polygonId: PolygonId(field.id),
                        points: field.polygon,
                        strokeWidth: field.id == _selectedId ? 5 : 2,
                        strokeColor: _fieldColor(field),
                        fillColor: _fieldColor(field).withValues(alpha: field.id == _selectedId ? .32 : .18),
                        consumeTapEvents: true,
                        onTap: () => _selectField(field),
                      ),
                },
                markers: {
                  for (final field in fields)
                    if (field.polygon.length >= 3)
                      Marker(
                        markerId: MarkerId('field-${field.id}'),
                        position: _centroid(field.polygon),
                        infoWindow: InfoWindow(title: field.name, snippet: '${(field.area / 10000).toStringAsFixed(2)} ha • ${field.crop}'),
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
                                decoration: const InputDecoration(hintText: 'Tìm mã hoặc tên thửa...', border: InputBorder.none, isDense: true),
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              IconButton(onPressed: () { _searchController.clear(); setState(() {}); }, icon: const Icon(Icons.clear)),
                          ],
                        ),
                        const Divider(height: 10),
                        Row(
                          children: [
                            Expanded(child: Text('${fields.length}/${allFields.length} thửa • ${summary.totalAreaHa.toStringAsFixed(2)} ha', style: const TextStyle(fontWeight: FontWeight.w600))),
                            Chip(
                              avatar: Icon(Icons.layers, size: 16, color: fields.isEmpty ? Colors.grey : _fieldColor(fields.first)),
                              label: Text(_layerLabel),
                            ),
                            TextButton.icon(onPressed: fields.isEmpty ? null : () => _fitAll(fields), icon: const Icon(Icons.fit_screen, size: 18), label: const Text('Tất cả')),
                          ],
                        ),
                        if (_cropFilter != 'Tất cả' || _statusFilter != 'Tất cả')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 6,
                              children: [
                                if (_cropFilter != 'Tất cả') Chip(label: Text(_cropFilter), onDeleted: () => setState(() => _cropFilter = 'Tất cả')),
                                if (_statusFilter != 'Tất cả') Chip(label: Text(_statusFilter), onDeleted: () => setState(() => _statusFilter = 'Tất cả')),
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
                      child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.layers, size: 15, color: Colors.green), const SizedBox(width: 5), Text('Lớp: $_layerLabel', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))]),
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
                        leading: CircleAvatar(backgroundColor: _fieldColor(selected), child: const Icon(Icons.grass, color: Colors.white)),
                        title: Text(selected.name),
                        subtitle: Text('${selected.area.toStringAsFixed(1)} m² • ${selected.crop} • ${selected.status}\n${selected.perimeter.toStringAsFixed(1)} m • ${selected.measurementMethod}'),
                        isThreeLine: true,
                        trailing: Wrap(spacing: 2, children: [
                          IconButton(tooltip: 'Chỉnh ranh', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FieldPolygonEditScreen(field: selected))), icon: const Icon(Icons.edit)),
                          const Icon(Icons.chevron_right),
                        ]),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FieldDetailScreen(field: selected))),
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
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(_centroid(field.polygon), 17));
  }

  Future<void> _showLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Lớp dữ liệu bản đồ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            RadioListTile<_MapLayer>(value: _MapLayer.crop, groupValue: _layer, title: const Text('🌱 Cây trồng'), subtitle: const Text('Màu thửa theo loại cây trồng'), onChanged: (value) { if (value != null) { setState(() => _layer = value); Navigator.pop(sheetContext); } }),
            RadioListTile<_MapLayer>(value: _MapLayer.status, groupValue: _layer, title: const Text('🚜 Trạng thái sản xuất'), subtitle: const Text('Màu thửa theo tình trạng sản xuất'), onChanged: (value) { if (value != null) { setState(() => _layer = value); Navigator.pop(sheetContext); } }),
            RadioListTile<_MapLayer>(value: _MapLayer.measurement, groupValue: _layer, title: const Text('📐 Phương pháp đo'), subtitle: const Text('GPS / thủ công / chưa xác định'), onChanged: (value) { if (value != null) { setState(() => _layer = value); Navigator.pop(sheetContext); } }),
          ]),
        ),
      ),
    );
  }

  Future<void> _showStatistics() async {
    final summary = _mapService.summarize(_filtered(_provider.fields));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        maxChildSize: .9,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
          children: [
            const Text('Thống kê trang trại', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: _StatBox(icon: Icons.grid_view, label: 'Số thửa', value: '${summary.fields.length}')), const SizedBox(width: 8), Expanded(child: _StatBox(icon: Icons.landscape, label: 'Diện tích', value: '${summary.totalAreaHa.toStringAsFixed(2)} ha'))]),
            const SizedBox(height: 18),
            const Text('Diện tích theo cây trồng', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...summary.cropArea.entries.map((entry) => _AreaRow(label: entry.key, area: entry.value, total: summary.totalArea, color: _cropColor(entry.key))),
            const SizedBox(height: 18),
            const Text('Diện tích theo trạng thái', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...summary.statusArea.entries.map((entry) => _AreaRow(label: entry.key, area: entry.value, total: summary.totalArea, color: _statusColor(entry.key))),
            const SizedBox(height: 18),
            const Text('Phương pháp đo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...summary.measurementCount.entries.map((entry) => ListTile(dense: true, leading: Icon(entry.key == 'gps' ? Icons.gps_fixed : Icons.straighten), title: Text(entry.key), trailing: Text('${entry.value} thửa'))),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilters() async {
    final fields = _provider.fields;
    final crops = _mapService.cropOptions(fields);
    final statuses = _mapService.statusOptions(fields);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Bộ lọc bản đồ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Cây trồng'),
              DropdownButton<String>(value: _cropFilter, isExpanded: true, items: crops.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (value) { if (value == null) return; setSheetState(() => _cropFilter = value); setState(() {}); }),
              const SizedBox(height: 8),
              const Text('Trạng thái'),
              DropdownButton<String>(value: _statusFilter, isExpanded: true, items: statuses.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (value) { if (value == null) return; setSheetState(() => _statusFilter = value); setState(() {}); }),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { setState(() { _cropFilter = 'Tất cả'; _statusFilter = 'Tất cả'; }); Navigator.pop(sheetContext); }, icon: const Icon(Icons.filter_alt_off), label: const Text('Xóa bộ lọc'))),
            ]),
          ),
        ),
      ),
    );
  }

  void _fitAll(List<FieldModel> fields) {
    if (_controller == null || fields.isEmpty) return;
    final points = fields.expand((field) => field.polygon).toList();
    if (points.isEmpty) return;
    if (points.length == 1) { _controller!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16)); return; }
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
    if ((maxLat - minLat).abs() < 0.0001) { minLat -= 0.001; maxLat += 0.001; }
    if ((maxLng - minLng).abs() < 0.0001) { minLng -= 0.001; maxLng += 0.001; }
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 70));
  }

  LatLng _centroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(16.55, 104.75);
    final lat = points.fold<double>(0, (sum, p) => sum + p.latitude) / points.length;
    final lng = points.fold<double>(0, (sum, p) => sum + p.longitude) / points.length;
    return LatLng(lat, lng);
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatBox({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [CircleAvatar(child: Icon(icon)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]))])));
}

class _AreaRow extends StatelessWidget {
  final String label;
  final double area;
  final double total;
  final Color color;
  const _AreaRow({required this.label, required this.area, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (area / total).clamp(0.0, 1.0);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text(label)), Text('${(area / 10000).toStringAsFixed(2)} ha')]), const SizedBox(height: 4), LinearProgressIndicator(value: ratio, minHeight: 5)]));
  }
}
