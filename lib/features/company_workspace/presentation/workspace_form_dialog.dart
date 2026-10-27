import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../application/workspace_service.dart';
import 'workspace_strings.dart';

class WorkspaceFormDialog extends StatefulWidget {
  const WorkspaceFormDialog({
    super.key,
    required this.service,
    required this.template,
    this.record,
  });
  final WorkspaceService service;
  final Json template;
  final Json? record;
  @override
  State<WorkspaceFormDialog> createState() => _FormState();
}

class _FormState extends State<WorkspaceFormDialog> {
  final form = GlobalKey<FormState>();
  final controls = <String, TextEditingController>{};
  final files = <Json>[];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final content = jsonMap(widget.record?['content'] ?? {});
    final old = jsonMap(content['fields'] ?? {});
    for (final raw in widget.template['fields'] as List) {
      final f = jsonMap(raw);
      controls[f['key'] as String] = TextEditingController(
        text:
            old[f['key']] as String? ?? (f['type'] == 'currency' ? 'VND' : ''),
      );
    }
    files.addAll((content['files'] as List? ?? []).map(jsonMap));
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> attach() async {
    final s = WorkspaceStrings(context);
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result != null) {
        final file = result.files.single;
        if (file.bytes == null) {
          throw const WorkspaceFailure('invalidAttachment');
        }
        final saved = await widget.service.upload(file.bytes!, file.name);
        if (mounted) setState(() => files.add(saved));
      }
    } catch (e) {
      if (mounted) setState(() => error = s.error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkspaceStrings(context);
    return AlertDialog(
      title: Text(s.name(widget.template['names'])),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final raw in widget.template['fields'] as List)
                  Builder(
                    builder: (context) {
                      final f = jsonMap(raw);
                      final type = f['type'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: type == 'currency'
                            ? DropdownButtonFormField<String>(
                                initialValue: controls[f['key']]!.text,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'VND',
                                    child: Text('VND'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'LAK',
                                    child: Text('LAK'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: s.name(f['label']),
                                ),
                                onChanged: busy
                                    ? null
                                    : (v) => controls[f['key']]!.text = v!,
                              )
                            : TextFormField(
                                controller: controls[f['key']],
                                maxLines: type == 'multiline' ? 3 : 1,
                                decoration: InputDecoration(
                                  labelText: s.name(f['label']),
                                  hintText: type == 'date'
                                      ? 'YYYY-MM-DD'
                                      : null,
                                ),
                                validator: (v) {
                                  if (f['required'] == true &&
                                      (v ?? '').trim().isEmpty) {
                                    return s.tr(
                                      'Bắt buộc',
                                      'Required',
                                      'ຈຳເປັນ',
                                    );
                                  }
                                  if ((v ?? '').isNotEmpty &&
                                      ['money', 'number'].contains(type) &&
                                      !RegExp(
                                        r'^\d{1,15}(\.\d{1,4})?$',
                                      ).hasMatch(v!)) {
                                    return s.tr(
                                      'Nhập số, dùng dấu chấm thập phân',
                                      'Enter a decimal number',
                                      'ປ້ອນຕົວເລກ',
                                    );
                                  }
                                  if (type == 'date' &&
                                      (v ?? '').isNotEmpty &&
                                      (!RegExp(
                                            r'^\d{4}-\d{2}-\d{2}$',
                                          ).hasMatch(v!) ||
                                          DateTime.tryParse(v) == null)) {
                                    return 'YYYY-MM-DD';
                                  }
                                  return null;
                                },
                              ),
                      );
                    },
                  ),
                for (final f in files)
                  ListTile(
                    title: Text(f['name'] as String),
                    trailing: IconButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => files.remove(f)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                TextButton.icon(
                  onPressed: busy || files.length >= 5 ? null : attach,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    s.tr(
                      'Đính kèm (tối đa 5MB/tệp)',
                      'Attach (up to 5MB/file)',
                      'ແນບໄຟລ໌ (ສູງສຸດ 5MB)',
                    ),
                  ),
                ),
                Text(
                  s.tr(
                    'Duyệt phiếu chưa tự ghi tiền, lương hoặc xuất kho.',
                    'Approval does not post cash, payroll or stock.',
                    'ອະນຸມັດບໍ່ລົງເງິນ ເງິນເດືອນ ຫຼື ສາງ.',
                  ),
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(s.tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () {
                  if (form.currentState!.validate()) {
                    setState(() => busy = true);
                    Navigator.pop(context, {
                      'templateId': widget.template['id'],
                      'fields': {
                        for (final e in controls.entries)
                          e.key: e.value.text.trim(),
                      },
                      'files': files,
                    });
                  }
                },
          child: Text(s.tr('Lưu nháp', 'Save draft', 'ບັນທຶກຮ່າງ')),
        ),
      ],
    );
  }
}
