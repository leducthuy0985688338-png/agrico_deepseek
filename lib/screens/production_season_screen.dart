import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../providers/production_season_provider.dart';
import '../widgets/production_dashboard_card.dart';
import '../widgets/season_economics_card.dart';
import 'harvest_screen.dart';
import 'production_cost_screen.dart';
import 'production_log_screen.dart';

class ProductionSeasonScreen extends StatefulWidget {
  final FieldModel field;
  const ProductionSeasonScreen({super.key, required this.field});

  @override
  State<ProductionSeasonScreen> createState() => _ProductionSeasonScreenState();
}

class _ProductionSeasonScreenState extends State<ProductionSeasonScreen> {
  late final ProductionSeasonProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = ProductionSeasonProvider()..loadForField(widget.field.id);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  Future<void> _createSeason() async {
    final result = await showDialog<ProductionSeasonModel>(
      context: context,
      builder: (_) => _SeasonFormDialog(field: widget.field),
    );
    if (result != null) await _provider.save(result);
  }

  Future<void> _deleteSeason(ProductionSeasonModel season) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa vụ sản xuất?'),
        content: Text('Xóa ${season.name}? Dữ liệu vụ sẽ bị xóa khỏi thiết bị.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (confirmed == true) await _provider.delete(season);
  }

  Future<void> _openLogs(ProductionSeasonModel season) async => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductionLogScreen(season: season)),
      );

  Future<void> _openHarvest(ProductionSeasonModel season) async => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HarvestScreen(season: season)),
      );

  Future<void> _openCosts(ProductionSeasonModel season) async => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductionCostScreen(season: season)),
      );

  void _openSeason(ProductionSeasonModel season) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Tổng quan vụ'),
              subtitle: Text(season.name),
            ),
            ListTile(
              leading: const Icon(Icons.payments),
              title: const Text('Chi phí sản xuất'),
              subtitle: const Text('Vật tư • nhân công • máy móc • nhiên liệu'),
              onTap: () {
                Navigator.pop(ctx);
                _openCosts(season);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Nhật ký sản xuất'),
              onTap: () {
                Navigator.pop(ctx);
                _openLogs(season);
              },
            ),
            ListTile(
              leading: const Icon(Icons.agriculture),
              title: const Text('Thu hoạch'),
              onTap: () {
                Navigator.pop(ctx);
                _openHarvest(season);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Vụ sản xuất • ${widget.field.name}')),
      body: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) {
          final seasons = _provider.seasonsForField(widget.field.id);
          if (_provider.isLoading) return const Center(child: CircularProgressIndicator());
          if (seasons.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.agriculture, size: 64),
                    const SizedBox(height: 12),
                    const Text('Chưa có vụ sản xuất nào cho thửa này.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _createSeason,
                      icon: const Icon(Icons.add),
                      label: const Text('Tạo vụ sản xuất'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: seasons.length,
            itemBuilder: (context, index) {
              final season = seasons[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(child: Icon(Icons.grass)),
                        title: Text(season.name),
                        subtitle: Text(
                          '${season.crop} • ${season.variety}\n'
                          'Bắt đầu: ${_date(season.startDate)} • ${season.status}',
                        ),
                        isThreeLine: true,
                        onTap: () => _openSeason(season),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'costs') _openCosts(season);
                            if (value == 'logs') _openLogs(season);
                            if (value == 'harvest') _openHarvest(season);
                            if (value == 'delete') _deleteSeason(season);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'costs', child: Text('Chi phí sản xuất')),
                            PopupMenuItem(value: 'logs', child: Text('Nhật ký sản xuất')),
                            PopupMenuItem(value: 'harvest', child: Text('Thu hoạch')),
                            PopupMenuItem(value: 'delete', child: Text('Xóa vụ')),
                          ],
                        ),
                      ),
                      ProductionDashboardCard(season: season),
                      const SizedBox(height: 8),
                      SeasonEconomicsCard(season: season),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSeason,
        icon: const Icon(Icons.add),
        label: const Text('Tạo vụ'),
      ),
    );
  }

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _SeasonFormDialog extends StatefulWidget {
  final FieldModel field;
  const _SeasonFormDialog({required this.field});

  @override
  State<_SeasonFormDialog> createState() => _SeasonFormDialogState();
}

class _SeasonFormDialogState extends State<_SeasonFormDialog> {
  final _name = TextEditingController();
  final _variety = TextEditingController();
  final _notes = TextEditingController();
  late final TextEditingController _crop;
  DateTime _startDate = DateTime.now();
  DateTime? _harvestDate;
  String _status = 'Đang sản xuất';

  @override
  void initState() {
    super.initState();
    _crop = TextEditingController(text: widget.field.crop);
  }

  @override
  void dispose() {
    _name.dispose();
    _variety.dispose();
    _crop.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tạo vụ sản xuất'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên vụ *')),
              TextField(controller: _crop, decoration: const InputDecoration(labelText: 'Cây trồng')),
              TextField(controller: _variety, decoration: const InputDecoration(labelText: 'Giống')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngày bắt đầu'),
                subtitle: Text(_date(_startDate)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDate: _startDate,
                  );
                  if (date != null) setState(() => _startDate = date);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngày dự kiến thu hoạch'),
                subtitle: Text(_harvestDate == null ? 'Chưa chọn' : _date(_harvestDate!)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: _startDate,
                    lastDate: DateTime(2100),
                    initialDate: _harvestDate ?? _startDate.add(const Duration(days: 90)),
                  );
                  if (date != null) setState(() => _harvestDate = date);
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: const [
                  'Đang sản xuất',
                  'Chuẩn bị thu hoạch',
                  'Đã thu hoạch',
                  'Tạm dừng',
                ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Ghi chú')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                ProductionSeasonModel(
                  id: 'VU-${DateTime.now().microsecondsSinceEpoch}',
                  fieldId: widget.field.id,
                  name: _name.text.trim(),
                  crop: _crop.text.trim(),
                  variety: _variety.text.trim(),
                  startDate: _startDate,
                  expectedHarvestDate: _harvestDate,
                  status: _status,
                  plannedArea: widget.field.area,
                  notes: _notes.text.trim(),
                ),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      );

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
