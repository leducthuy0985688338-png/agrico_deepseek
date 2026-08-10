import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';

import '../models/field_model.dart';
import '../models/finance_model.dart';
import '../models/task_model.dart';
import '../providers/field_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/fuel_provider.dart';
import '../providers/task_provider.dart';
import '../providers/production_season_provider.dart';
import '../providers/production_log_provider.dart';
import '../providers/harvest_provider.dart';
import '../widgets/photo_gallery.dart';
import 'field_edit_screen.dart';
import 'field_gps_measure_screen.dart';
import 'field_measurement_history_screen.dart';
import 'machine_assignment_screen.dart';
import 'production_season_screen.dart';
import 'task_screen.dart';

class FieldDetailScreen extends StatefulWidget {
  final FieldModel field;
  const FieldDetailScreen({super.key, required this.field});

  @override
  State<FieldDetailScreen> createState() => _FieldDetailScreenState();
}

class _FieldDetailScreenState extends State<FieldDetailScreen> {
  final Location _location = Location();
  late final FieldProvider _fieldProvider;
  late final MachineProvider _machineProvider;
  late final FinanceProvider _financeProvider;
  late final FuelProvider _fuelProvider;
  late final TaskProvider _taskProvider;
  late final ProductionSeasonProvider _seasonProvider;
  late final ProductionLogProvider _logProvider;
  late final HarvestProvider _harvestProvider;
  LocationData? _currentLocation;
  bool _productionLoading = true;

  FieldModel get _field => _fieldProvider.getFieldById(widget.field.id) ?? widget.field;

  @override
  void initState() {
    super.initState();
    _fieldProvider = context.read<FieldProvider>();
    _machineProvider = context.read<MachineProvider>();
    _financeProvider = context.read<FinanceProvider>();
    _fuelProvider = context.read<FuelProvider>();
    _taskProvider = context.read<TaskProvider>();
    _seasonProvider = context.read<ProductionSeasonProvider>();
    _logProvider = context.read<ProductionLogProvider>();
    _harvestProvider = context.read<HarvestProvider>();
    _getLocation();
    _loadProductionProfile();
  }

  Future<void> _loadProductionProfile() async {
    setState(() => _productionLoading = true);
    try {
      await _seasonProvider.loadForField(_field.id);
      final seasons = _seasonProvider.seasonsForField(_field.id);
      await Future.wait(seasons.map((season) async {
        await Future.wait([
          _logProvider.loadForSeason(season.id),
          _harvestProvider.loadForSeason(season.id),
        ]);
      }));
    } finally {
      if (mounted) setState(() => _productionLoading = false);
    }
  }

  Future<void> _getLocation() async {
    var enabled = await _location.serviceEnabled();
    if (!enabled) {
      enabled = await _location.requestService();
      if (!enabled) return;
    }
    var permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != PermissionStatus.granted) return;
    }
    final data = await _location.getLocation();
    if (mounted) setState(() => _currentLocation = data);
  }

  LatLng _mapCenter() {
    if (_field.polygon.isNotEmpty) {
      final lat = _field.polygon.fold<double>(0, (sum, p) => sum + p.latitude) / _field.polygon.length;
      final lng = _field.polygon.fold<double>(0, (sum, p) => sum + p.longitude) / _field.polygon.length;
      return LatLng(lat, lng);
    }
    if (_currentLocation?.latitude != null && _currentLocation?.longitude != null) {
      return LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
    }
    return const LatLng(16.55, 104.75);
  }

  ProfitReport? get _report {
    for (final report in _financeProvider.generateProfitReport()) {
      if (report.fieldId == _field.id) return report;
    }
    return null;
  }

  Future<void> _editField() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => FieldEditScreen(field: _field)));
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _openSeasons() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductionSeasonScreen(field: _field)));
    await _loadProductionProfile();
  }

  Future<void> _assignMachine() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MachineAssignmentScreen()));
    if (mounted) setState(() {});
  }

  void _addPhoto(String path) {
    _fieldProvider.addPhotoToField(_field.id, path);
    if (mounted) setState(() {});
  }

  String _money(double value) => '${value.toStringAsFixed(0)} đ';

  @override
  Widget build(BuildContext context) {
    final center = _mapCenter();
    final polygon = _field.polygon;
    final report = _report;
    final machines = _machineProvider.getMachinesByField(_field.id);
    final fuelTransactions = _fuelProvider.getTransactionsByField(_field.id);
    final fuelLiters = _fuelProvider.getTotalFuelByField(_field.id);
    final tasks = _taskProvider.getTasksByField(_field.id);
    final seasons = _seasonProvider.seasonsForField(_field.id);
    final productionLogs = seasons.fold<int>(0, (sum, season) => sum + _logProvider.logsForSeason(season.id).length);
    final productionCost = seasons.fold<double>(0, (sum, season) => sum + _logProvider.totalCost(season.id));
    final harvestQuantity = seasons.fold<double>(0, (sum, season) => sum + _harvestProvider.totalQuantity(season.id));
    final harvestRevenue = seasons.fold<double>(0, (sum, season) => sum + _harvestProvider.totalRevenue(season.id));
    final productionProfit = harvestRevenue - productionCost;

    final markers = <Marker>{};
    if (_currentLocation?.latitude != null && _currentLocation?.longitude != null) {
      markers.add(Marker(markerId: const MarkerId('current'), position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!)));
    }

    final polygons = <Polygon>{};
    if (polygon.length >= 3) {
      polygons.add(Polygon(
        polygonId: PolygonId(_field.id),
        points: polygon,
        fillColor: Colors.green.withValues(alpha: .22),
        strokeColor: Colors.green,
        strokeWidth: 3,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_field.name),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(tooltip: 'Sửa thông tin', onPressed: _editField, icon: const Icon(Icons.edit)),
          IconButton(tooltip: 'Đo/cập nhật thửa', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen())), icon: const Icon(Icons.gps_fixed)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await _getLocation(); await _loadProductionProfile(); },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(height: 300, child: GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: 17),
              mapType: MapType.satellite,
              myLocationEnabled: _currentLocation != null,
              myLocationButtonEnabled: true,
              polygons: polygons,
              markers: markers,
            )),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_field.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(children: [
                  _InfoChip(icon: Icons.square_foot, label: '${_field.area.toStringAsFixed(1)} m²'),
                  const SizedBox(width: 8),
                  _InfoChip(icon: Icons.landscape, label: '${(_field.area / 10000).toStringAsFixed(3)} ha'),
                ]),
                const SizedBox(height: 8),
                Text('Cây trồng: ${_field.crop}'),
                Text('Trạng thái: ${_field.status}'),
                Text('Số điểm ranh: ${_field.polygon.length}'),
                Text('Chu vi: ${_field.perimeter.toStringAsFixed(1)} m'),
                Text('Phương pháp đo: ${_field.measurementMethod}'),
                if (_field.gpsAccuracy != null) Text('Độ chính xác GPS: ±${_field.gpsAccuracy!.toStringAsFixed(1)} m'),
                const SizedBox(height: 10),
                OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FieldMeasurementHistoryScreen(field: _field))), icon: const Icon(Icons.history), label: const Text('Lịch sử đo đạc')),
                const Divider(height: 28),
                const Text('Hồ sơ sản xuất', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_productionLoading)
                  const Card(child: Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())))
                else ...[
                  Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
                    _metric('Vụ sản xuất', '${seasons.length} vụ'),
                    _metric('Nhật ký sản xuất', '$productionLogs hoạt động'),
                    _metric('Sản lượng thu hoạch', '${harvestQuantity.toStringAsFixed(1)}'),
                    _metric('Doanh thu thu hoạch', _money(harvestRevenue)),
                    _metric('Chi phí sản xuất', _money(productionCost)),
                    _metric('Lợi nhuận sản xuất', _money(productionProfit), bold: true),
                  ]))),
                  const SizedBox(height: 8),
                  if (seasons.isNotEmpty) ...[
                    const Text('Vụ sản xuất gần nhất', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...seasons.take(2).map((season) {
                      final logs = _logProvider.logsForSeason(season.id);
                      final harvest = _harvestProvider.recordsForSeason(season.id);
                      return Card(child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.grass)),
                        title: Text(season.name),
                        subtitle: Text('${season.crop}${season.variety.isEmpty ? '' : ' • ${season.variety}'}\n${season.status} • ${logs.length} nhật ký • ${harvest.length} lần thu hoạch'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openSeasons,
                      ));
                    }),
                  ],
                  const SizedBox(height: 8),
                  _SectionCard(icon: Icons.eco, title: 'Quản lý vụ sản xuất', value: 'Mở đầy đủ vụ mùa, nhật ký và thu hoạch', onTap: _openSeasons),
                ],
                const Divider(height: 28),
                const Text('Hiệu quả thửa đất', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
                  _metric('Doanh thu', _money(report?.totalRevenue ?? 0)),
                  _metric('Chi phí', _money(report?.totalCost ?? 0)),
                  _metric('Lợi nhuận', _money(report?.profit ?? 0), bold: true),
                  _metric('Lợi nhuận/ha', _money(_field.area > 0 ? (report?.profit ?? 0) / (_field.area / 10000) : 0), bold: true),
                  _metric('Biên lợi nhuận', '${(report?.profitMargin ?? 0).toStringAsFixed(1)}%'),
                ]))),
                const SizedBox(height: 12),
                _SectionCard(icon: Icons.assignment, title: 'Công việc trên thửa', value: '${tasks.length} công việc', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskScreen()))),
                const SizedBox(height: 8),
                Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.local_gas_station)), title: const Text('Nhiên liệu'), subtitle: Text('${fuelLiters.toStringAsFixed(1)} L đã xuất cho thửa • ${fuelTransactions.length} giao dịch'))),
                const SizedBox(height: 8),
                Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.agriculture)), title: const Text('Máy móc'), subtitle: Text('${machines.length} máy đang/đã làm việc trên thửa'), trailing: const Icon(Icons.chevron_right), onTap: _assignMachine)),
                if (tasks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Công việc gần đây', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...tasks.take(3).map((task) => Card(child: ListTile(dense: true, leading: Icon(task.status == TaskStatus.COMPLETED ? Icons.check_circle : Icons.pending_actions), title: Text(task.title), subtitle: Text('${task.assignedToName} • Hạn ${task.dueDate.day}/${task.dueDate.month}')))),
                ],
                const SizedBox(height: 12),
                PhotoGallery(photoPaths: _field.photoPaths, onAddPhoto: _addPhoto),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _assignMachine, icon: const Icon(Icons.agriculture), label: const Text('Gán máy'))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Expanded(child: Text(label)), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : null))]),
  );
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  const _SectionCard({required this.icon, required this.title, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(child: ListTile(
    leading: CircleAvatar(child: Icon(icon)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(value),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  ));
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 18), label: Text(label));
}
