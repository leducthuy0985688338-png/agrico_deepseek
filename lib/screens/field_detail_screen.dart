import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

import '../models/field_model.dart';
import '../models/finance_model.dart';
import '../providers/field_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/finance_provider.dart';
import '../widgets/photo_gallery.dart';
import 'field_edit_screen.dart';
import 'field_gps_measure_screen.dart';
import 'machine_assignment_screen.dart';
import 'production_season_screen.dart';

class FieldDetailScreen extends StatefulWidget {
  final FieldModel field;
  const FieldDetailScreen({super.key, required this.field});
  @override State<FieldDetailScreen> createState() => _FieldDetailScreenState();
}

class _FieldDetailScreenState extends State<FieldDetailScreen> {
  final Location _location = Location();
  final _fieldProvider = FieldProvider();
  final _machineProvider = MachineProvider();
  final _financeProvider = FinanceProvider();
  LocationData? _currentLocation;

  FieldModel get _field => _fieldProvider.getFieldById(widget.field.id) ?? widget.field;

  @override void initState() { super.initState(); _getLocation(); }

  Future<void> _getLocation() async {
    var enabled = await _location.serviceEnabled();
    if (!enabled) { enabled = await _location.requestService(); if (!enabled) return; }
    var permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) { permission = await _location.requestPermission(); if (permission != PermissionStatus.granted) return; }
    final data = await _location.getLocation();
    if (mounted) setState(() => _currentLocation = data);
  }

  LatLng _mapCenter() {
    if (_field.polygon.isNotEmpty) {
      final lat = _field.polygon.fold<double>(0, (s, p) => s + p.latitude) / _field.polygon.length;
      final lng = _field.polygon.fold<double>(0, (s, p) => s + p.longitude) / _field.polygon.length;
      return LatLng(lat, lng);
    }
    if (_currentLocation?.latitude != null && _currentLocation?.longitude != null) return LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
    return const LatLng(16.55, 104.75);
  }

  ProfitReport? get _report {
    for (final report in _financeProvider.generateProfitReport()) { if (report.fieldId == _field.id) return report; }
    return null;
  }

  Future<void> _editField() async { final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => FieldEditScreen(field: _field))); if (changed == true && mounted) setState(() {}); }
  Future<void> _openSeasons() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductionSeasonScreen(field: _field))); if (mounted) setState(() {}); }
  void _addPhoto(String path) { _fieldProvider.addPhotoToField(_field.id, path); if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final center = _mapCenter();
    final polygon = _field.polygon;
    final report = _report;
    final machines = _machineProvider.getMachinesByField(_field.id);
    return Scaffold(
      appBar: AppBar(title: Text(_field.name), backgroundColor: Colors.green, foregroundColor: Colors.white, actions: [
        IconButton(tooltip: 'Sửa thông tin', onPressed: _editField, icon: const Icon(Icons.edit)),
        IconButton(tooltip: 'Đo/cập nhật thửa', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen())), icon: const Icon(Icons.gps_fixed)),
      ]),
      body: RefreshIndicator(onRefresh: () async { await _getLocation(); if (mounted) setState(() {}); }, child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        SizedBox(height: 300, child: GoogleMap(initialCameraPosition: CameraPosition(target: center, zoom: 17), mapType: MapType.satellite, myLocationEnabled: _currentLocation != null, myLocationButtonEnabled: true,
          polygons: {if (polygon.length >= 3) Polygon(polygonId: PolygonId(_field.id), points: polygon, fillColor: Colors.green.withValues(alpha: .22), strokeColor: Colors.green, strokeWidth: 3)},
          markers: {if (_currentLocation?.latitude != null && _currentLocation?.longitude != null) Marker(markerId: const MarkerId('current'), position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!))},
        )),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_field.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(children: [_InfoChip(icon: Icons.square_foot, label: '${_field.area.toStringAsFixed(1)} m²'), const SizedBox(width: 8), _InfoChip(icon: Icons.landscape, label: '${(_field.area / 10000).toStringAsFixed(3)} ha')]),
          const SizedBox(height: 8), Text('Cây trồng: ${_field.crop}'), Text('Trạng thái: ${_field.status}'), Text('Số điểm ranh: ${_field.polygon.length}'),
          const Divider(height: 28), const Text('Hiệu quả thửa đất', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
            _metric('Doanh thu', _money(report?.totalRevenue ?? 0)), _metric('Chi phí', _money(report?.totalCost ?? 0)),
            _metric('Lợi nhuận', _money(report?.profit ?? 0), bold: true),
            _metric('Lợi nhuận/ha', _money((_field.area > 0 ? (report?.profit ?? 0) / (_field.area / 10000) : 0)), bold: true),
            _metric('Biên lợi nhuận', '${(report?.profitMargin ?? 0).toStringAsFixed(1)}%'),
          ]))),
          const SizedBox(height: 12),
          Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.agriculture)), title: const Text('Vụ sản xuất'), subtitle: const Text('Gieo trồng • vật tư • tưới • máy móc • thu hoạch'), trailing: const Icon(Icons.chevron_right), onTap: _openSeasons)),
          if (machines.isNotEmpty) ...[const SizedBox(height: 12), const Text('Máy móc đang làm trên lô', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8), ...machines.map((m) => Card(child: ListTile(leading: const Icon(Icons.agriculture, color: Colors.green), title: Text(m.name), subtitle: Text('${m.type} • ${m.status} • ${m.totalHours}h'))))],
          const SizedBox(height: 12), PhotoGallery(photoPaths: _field.photoPaths, onAddPhoto: _addPhoto),
          const SizedBox(height: 20), Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MachineAssignmentScreen())).then((_) { if (mounted) setState(() {}); }), icon: const Icon(Icons.agriculture), label: const Text('Gán máy')))]),
        ]),
      ])),
    );
  }

  Widget _metric(String label, String value, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(label)), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : null))]));
  String _money(double value) => '${value.toStringAsFixed(0)} đ';
}

class _InfoChip extends StatelessWidget { final IconData icon; final String label; const _InfoChip({required this.icon, required this.label}); @override Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 18), label: Text(label)); }
