import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/production_log_provider.dart';
import '../providers/harvest_provider.dart';
import '../services/season_economics_service.dart';
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
  LocationData? _currentLocation;
  final Location _location = Location();
  final _fieldProvider = FieldProvider();
  final _machineProvider = MachineProvider();
  final _logProvider = ProductionLogProvider();
  final _harvestProvider = HarvestProvider();

  FieldModel get _field => _fieldProvider.getFieldById(widget.field.id) ?? widget.field;

  @override void initState() { super.initState(); _getLocation(); }
  @override void dispose() { _logProvider.dispose(); _harvestProvider.dispose(); super.dispose(); }

  Future<void> _getLocation() async {
    var enabled = await _location.serviceEnabled();
    if (!enabled) { enabled = await _location.requestService(); if (!enabled) return; }
    var permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) { permission = await _location.requestPermission(); if (permission != PermissionStatus.granted) return; }
    final data = await _location.getLocation();
    if (mounted) setState(() => _currentLocation = data);
  }

  void _addPhoto(String path) { _fieldProvider.addPhotoToField(_field.id, path); if (mounted) setState(() {}); }
  List<dynamic> get _machinesOnField => _machineProvider.getMachinesByField(_field.id);

  LatLng _mapCenter() {
    if (_field.polygon.isNotEmpty) {
      final lat = _field.polygon.fold<double>(0, (s, p) => s + p.latitude) / _field.polygon.length;
      final lng = _field.polygon.fold<double>(0, (s, p) => s + p.longitude) / _field.polygon.length;
      return LatLng(lat, lng);
    }
    if (_currentLocation?.latitude != null && _currentLocation?.longitude != null) return LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
    return const LatLng(16.55, 104.75);
  }

  Future<void> _editField() async { final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => FieldEditScreen(field: _field))); if (changed == true && mounted) setState(() {}); }
  Future<void> _openSeasons() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductionSeasonScreen(field: _field))); if (mounted) setState(() {}); }

  Future<void> _loadEconomics() async {
    await Future.wait([_logProvider.loadForField(_field.id), _harvestProvider.loadForField(_field.id)]);
    if (mounted) setState(() {});
  }

  SeasonEconomics get _economics => SeasonEconomics.calculate(plannedAreaSquareMeters: _field.area, totalCost: _logProvider.totalCostForField(_field.id), totalRevenue: _harvestProvider.totalRevenueForField(_field.id), totalQuantity: _harvestProvider.totalQuantityForField(_field.id));

  @override
  Widget build(BuildContext context) {
    final center = _mapCenter();
    final polygon = _field.polygon;
    final machines = _machinesOnField;
    return Scaffold(
      appBar: AppBar(title: Text(_field.name), backgroundColor: Colors.green, foregroundColor: Colors.white, actions: [IconButton(tooltip: 'Sửa thông tin', onPressed: _editField, icon: const Icon(Icons.edit)), IconButton(tooltip: 'Đo/cập nhật thửa', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen())), icon: const Icon(Icons.gps_fixed))]),
      body: RefreshIndicator(onRefresh: () async { await _getLocation(); await _loadEconomics(); }, child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        SizedBox(height: 300, child: GoogleMap(initialCameraPosition: CameraPosition(target: center, zoom: 17), mapType: MapType.satellite, myLocationEnabled: _currentLocation != null, myLocationButtonEnabled: true, polygons: {if (polygon.length >= 3) Polygon(polygonId: PolygonId(_field.id), points: polygon, fillColor: Colors.green.withValues(alpha: 0.22), strokeColor: Colors.green, strokeWidth: 3)}, markers: {if (_currentLocation?.latitude != null && _currentLocation?.longitude != null) Marker(markerId: const MarkerId('current'), position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!))})),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_field.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(children: [_InfoChip(icon: Icons.square_foot, label: '${_field.area.toStringAsFixed(1)} m²'), const SizedBox(width: 8), _InfoChip(icon: Icons.landscape, label: '${(_field.area / 10000).toStringAsFixed(3)} ha')]),
          const SizedBox(height: 8), Text('Cây trồng: ${_field.crop}'), Text('Trạng thái: ${_field.status}'), Text('Số điểm ranh: ${_field.polygon.length}'),
          const Divider(height: 28),
          const Text('Hiệu quả thửa đất', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          AnimatedBuilder(animation: Listenable.merge([_logProvider, _harvestProvider]), builder: (_, __) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [_metric('Sản lượng', '${_economics.totalQuantity.toStringAsFixed(1)} kg'), _metric('Doanh thu', _money(_economics.totalRevenue)), _metric('Chi phí', _money(_economics.totalCost)), _metric('Lợi nhuận', _money(_economics.profit), bold: true), _metric('Lợi nhuận/ha', _money(_economics.profitPerHa), bold: true)])))),
          const SizedBox(height: 12),
          Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.agriculture)), title: const Text('Vụ sản xuất'), subtitle: const Text('Gieo trồng • vật tư • tưới • máy móc • thu hoạch'), trailing: const Icon(Icons.chevron_right), onTap: _openSeasons)),
          const SizedBox(height: 12),
          if (machines.isNotEmpty) ...[const Text('Máy móc đang làm trên lô', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8), ...machines.map((m) => Card(child: ListTile(leading: const Icon(Icons.agriculture, color: Colors.green), title: Text(m.name), subtitle: Text('${m.type} • ${m.status} • ${m.totalHours}h')))), const SizedBox(height: 8)],
          PhotoGallery(photoPaths: _field.photoPaths, onAddPhoto: _addPhoto),
          const SizedBox(height: 20),
          Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MachineAssignmentScreen())).then((_) {if (mounted) setState(() {});}), icon: const Icon(Icons.agriculture), label: const Text('Gán máy'))), const SizedBox(width: 12), Expanded(child: ElevatedButton.icon(onPressed: _showMachineLogDialog, icon: const Icon(Icons.history), label: const Text('Nhật ký máy'))]),
        ]),
      ])),
    );
  }

  Widget _metric(String label, String value, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(label)), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : null))]));
  String _money(double value) => '${value.toStringAsFixed(0)} đ';
  void _showMachineLogDialog() { final logs = <Map<String, dynamic>>[]; for (final machine in _machineProvider.machines) { for (final record in machine.fieldHistory) { if (record.fieldId == _field.id) logs.add({'machineName': machine.name, 'startDate': record.startDate, 'hoursWorked': record.hoursWorked, 'fuelUsed': record.fuelUsed, 'operator': record.operatorName ?? 'Chưa có'}); } } logs.sort((a,b) => b['startDate'].compareTo(a['startDate'])); showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text('Nhật ký máy - ${_field.name}'), content: SizedBox(width: double.maxFinite, height: 400, child: logs.isEmpty ? const Center(child: Text('Chưa có nhật ký máy')) : ListView.builder(itemCount: logs.length, itemBuilder: (_, i) { final log = logs[i]; return ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: Text(log['machineName'] as String), subtitle: Text('${log['hoursWorked']}h • ${log['fuelUsed']}L • ${log['operator']}')); })), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))])); }
}

class _InfoChip extends StatelessWidget { final IconData icon; final String label; const _InfoChip({required this.icon, required this.label}); @override Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 18), label: Text(label)); }
