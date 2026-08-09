import 'package:flutter/material.dart';

import '../models/production_log_model.dart';
import '../models/production_season_model.dart';
import '../providers/production_log_provider.dart';

class ProductionLogScreen extends StatefulWidget {
  final ProductionSeasonModel season;

  const ProductionLogScreen({super.key, required this.season});

  @override
  State<ProductionLogScreen> createState() => _ProductionLogScreenState();
}

class _ProductionLogScreenState extends State<ProductionLogScreen> {
  late final ProductionLogProvider _provider;

  static const _types = [
    'Gieo trồng',
    'Bón phân',
    'Phun thuốc',
    'Tưới',
    'Làm cỏ',
    'Thu hoạch',
    'Máy móc',
    'Nhân công',
    'Khác',
  ];

  @override
  void initState() {
    super.initState();
    _provider = ProductionLogProvider()..loadForSeason(widget.season.id);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  Future<void> _addLog() async {
    final log = await showDialog<ProductionLogModel>(
      context: context,
      builder: (_) => _ProductionLogForm(
        season: widget.season,
        types: _types,
      ),
    );
    if (log != null) await _provider.save(log);
  }

  Future<void> _delete(ProductionLogModel log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa nhật ký?'),
        content: Text('Xóa hoạt động "${log.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) await _provider.delete(log);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Nhật ký • ${widget.season.name}')),
      body: AnimatedBuilder(
        animation: _provider,
        builder: (context, _) {
          final logs = _provider.logsForSeason(widget.season.id);
          final total = _provider.totalCost(widget.season.id);
          if (_provider.isLoading) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.payments)),
                  title: const Text('Tổng chi phí'),
                  subtitle: Text('${total.toStringAsFixed(0)} đ'),
                  trailing: Text('${logs.length} hoạt động'),
                ),
              ),
              const SizedBox(height: 8),
              if (logs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Chưa có nhật ký sản xuất.')),
                ),
              ...logs.map((log) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_iconFor(log.activityType))),
                      title: Text(log.title),
                      subtitle: Text(
                        '${_date(log.date)} • ${log.activityType}\n'
                        '${log.quantity > 0 ? '${log.quantity} ${log.unit} • ' : ''}'
                        '${log.cost > 0 ? '${log.cost.toStringAsFixed(0)} đ' : 'Không ghi chi phí'}'
                        '${log.worker.isNotEmpty ? ' • ${log.worker}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(log)),
                    ),
                  )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLog,
        icon: const Icon(Icons.add),
        label: const Text('Ghi hoạt động'),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'Gieo trồng': return Icons.grass;
      case 'Bón phân': return Icons.eco;
      case 'Phun thuốc': return Icons.water_drop;
      case 'Tưới': return Icons.water;
      case 'Làm cỏ': return Icons.content_cut;
      case 'Thu hoạch': return Icons.agriculture;
      case 'Máy móc': return Icons.precision_manufacturing;
      case 'Nhân công': return Icons.groups;
      default: return Icons.notes;
    }
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _ProductionLogForm extends StatefulWidget {
  final ProductionSeasonModel season;
  final List<String> types;

  const _ProductionLogForm({required this.season, required this.types});

  @override
  State<_ProductionLogForm> createState() => _ProductionLogFormState();
}

class _ProductionLogFormState extends State<_ProductionLogForm> {
  final _title = TextEditingController();
  final _quantity = TextEditingController();
  final _unit = TextEditingController();
  final _cost = TextEditingController();
  final _worker = TextEditingController();
  final _notes = TextEditingController();
  late String _type;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _type = widget.types.first;
  }

  @override
  void dispose() {
    for (final c in [_title, _quantity, _unit, _cost, _worker, _notes]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ghi hoạt động sản xuất'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Loại hoạt động'),
              items: widget.types.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Nội dung *')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ngày thực hiện'),
              subtitle: Text(_format(_date)),
              onTap: () async {
                final value = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: _date);
                if (value != null) setState(() => _date = value);
              },
            ),
            TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Khối lượng')),
            TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Đơn vị (kg, lít, giờ...)')),
            TextField(controller: _cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Chi phí (VNĐ)')),
            TextField(controller: _worker, decoration: const InputDecoration(labelText: 'Người thực hiện')),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Ghi chú')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(context, ProductionLogModel(
              id: 'NK-${DateTime.now().microsecondsSinceEpoch}',
              seasonId: widget.season.id,
              fieldId: widget.season.fieldId,
              date: _date,
              activityType: _type,
              title: _title.text.trim(),
              quantity: double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0,
              unit: _unit.text.trim(),
              cost: double.tryParse(_cost.text.replaceAll(',', '.')) ?? 0,
              worker: _worker.text.trim(),
              notes: _notes.text.trim(),
            ));
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }

  String _format(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
