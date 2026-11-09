import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../providers/field_provider.dart';

class FieldEditScreen extends StatefulWidget {
  final FieldModel field;
  final FieldProvider? providerOverride;
  const FieldEditScreen({
    super.key,
    required this.field,
    this.providerOverride,
  });

  @override
  State<FieldEditScreen> createState() => _FieldEditScreenState();
}

class _FieldEditScreenState extends State<FieldEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _crop = TextEditingController();
  final _status = TextEditingController();
  late final FieldProvider _provider;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.providerOverride ?? FieldProvider();
    _name.text = widget.field.name;
    _crop.text = widget.field.crop;
    _status.text = widget.field.status;
  }

  @override
  void dispose() {
    _name.dispose();
    _crop.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _provider.saveFieldLocally(
        widget.field.copyWith(
          name: _name.text.trim(),
          crop: _crop.text.trim(),
          status: _status.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không thể lưu thông tin thửa đất vào bộ nhớ cục bộ. Vui lòng thử lại.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin thửa đất')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Tên lô / thửa',
                prefixIcon: Icon(Icons.landscape),
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Nhập tên lô' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _crop,
              decoration: const InputDecoration(
                labelText: 'Cây trồng',
                prefixIcon: Icon(Icons.grass),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập cây trồng'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _status,
              decoration: const InputDecoration(
                labelText: 'Trạng thái',
                prefixIcon: Icon(Icons.flag),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập trạng thái'
                  : null,
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.square_foot),
                title: Text('${widget.field.area.toStringAsFixed(1)} m²'),
                subtitle: Text(
                  '${(widget.field.area / 10000).toStringAsFixed(3)} ha • ${widget.field.polygon.length} điểm GPS',
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('LƯU THÔNG TIN'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
