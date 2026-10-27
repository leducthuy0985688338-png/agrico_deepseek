import 'package:flutter/material.dart';

import '../application/workspace_service.dart';
import '../domain/administrative_templates.dart';
import '../../../core/permissions/authorization.dart';
import 'workspace_strings.dart';

class WorkspaceSettingsScreen extends StatefulWidget {
  const WorkspaceSettingsScreen({super.key, required this.service});
  final WorkspaceService service;
  @override
  State<WorkspaceSettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<WorkspaceSettingsScreen> {
  List<Json> templates = administrativeTemplates, routes = [], members = [];
  bool busy = false;
  String? error;
  WorkspaceStrings get s => WorkspaceStrings(context);
  WorkspaceService get service => widget.service;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await run(() async {
      final t = await service.request('template.list');
      final r = await service.request('route.list');
      final directory = await service.directory();
      if (mounted) {
        setState(() {
          templates = (t['templates'] as List).map(jsonMap).toList();
          routes = (r['routes'] as List).map(jsonMap).toList();
          members = directory;
        });
      }
    });
  }

  Future<void> run(Future<void> Function() body) async {
    setState(() => busy = true);
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => error = s.error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> route({Json? old}) async {
    var template =
        old?['templateId'] as String? ?? templates.first['id'] as String;
    final department = TextEditingController(
      text: old?['department'] as String? ?? '',
    );
    final steps = (old?['steps'] as List? ?? [])
        .map((e) => e['uid'] as String)
        .toList();
    String? localError;
    final value = await showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            s.tr(
              'Tuyến duyệt 1–4 cấp',
              'Approval route (1–4 steps)',
              'ເສັ້ນທາງອະນຸມັດ 1–4 ຂັ້ນ',
            ),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: template,
                    isExpanded: true,
                    items: [
                      for (final t in templates)
                        DropdownMenuItem(
                          value: t['id'] as String,
                          child: Text(s.name(t['names'])),
                        ),
                    ],
                    onChanged: old != null
                        ? null
                        : (v) => update(() => template = v!),
                  ),
                  TextField(
                    controller: department,
                    decoration: InputDecoration(
                      labelText: s.tr(
                        'Mã phòng ban của người gửi',
                        'Sender department code',
                        'ລະຫັດພະແນກຜູ້ສົ່ງ',
                      ),
                    ),
                  ),
                  for (var i = 0; i < steps.length; i++)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: steps[i],
                            isExpanded: true,
                            items: [
                              if (!members.any((m) => m['uid'] == steps[i]))
                                DropdownMenuItem(
                                  value: steps[i],
                                  enabled: false,
                                  child: Text(
                                    s.tr(
                                      'Tài khoản ngừng hoạt động – chọn thay thế',
                                      'Inactive account – select replacement',
                                      'ບັນຊີປິດ – ເລືອກຜູ້ແທນ',
                                    ),
                                  ),
                                ),
                              for (final m in members)
                                DropdownMenuItem(
                                  value: m['uid'] as String,
                                  child: Text(m['name'] as String),
                                ),
                            ],
                            onChanged: (v) => steps[i] = v!,
                          ),
                        ),
                        IconButton(
                          onPressed: () => update(() => steps.removeAt(i)),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: steps.length >= 4 || members.isEmpty
                        ? null
                        : () => update(
                            () => steps.add(members.first['uid'] as String),
                          ),
                    child: Text(
                      s.tr('Thêm cấp duyệt', 'Add reviewer', 'ເພີ່ມຜູ້ອະນຸມັດ'),
                    ),
                  ),
                  if (localError != null) Text(localError!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
            ),
            FilledButton(
              onPressed: () {
                if (department.text.trim().isEmpty ||
                    steps.isEmpty ||
                    steps.toSet().length != steps.length) {
                  update(
                    () => localError = s.tr(
                      'Điền phòng ban và chọn người duyệt khác nhau.',
                      'Enter department and distinct reviewers.',
                      'ປ້ອນພະແນກ ແລະ ຜູ້ອະນຸມັດຕ່າງກັນ.',
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'templateId': template,
                  'department': department.text.trim(),
                  'steps': steps,
                });
              },
              child: Text(s.tr('Lưu', 'Save', 'ບັນທຶກ')),
            ),
          ],
        ),
      ),
    );
    department.dispose();
    if (value != null) {
      await run(() async {
        await service.request(
          'route.save',
          entity: old?['id'] as String? ?? service.newId(),
          revision: old?['revision'] as int? ?? 0,
          payload: value,
        );
      });
    }
    if (value != null) await load();
  }

  Future<void> template({Json? old}) async {
    final names = [
      for (var i = 0; i < 3; i++)
        TextEditingController(
          text: old == null ? '' : (old['names'] as List)[i] as String,
        ),
    ];
    final prefix = TextEditingController(text: old?['prefix'] as String? ?? '');
    var permission = old?['permission'] as String? ?? 'office.edit';
    final fields = (old?['fields'] as List? ?? []).map(jsonMap).toList();
    String? localError;
    Future<Json?> field(BuildContext ctx) async {
      final labels = [for (var i = 0; i < 3; i++) TextEditingController()];
      var type = 'text';
      bool required = true;
      final result = await showDialog<Json>(
        context: ctx,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: Text(s.tr('Trường thông tin', 'Form field', 'ຊ່ອງຂໍ້ມູນ')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    TextField(
                      controller: labels[i],
                      decoration: InputDecoration(
                        labelText: [
                          'Tên tiếng Việt',
                          'English label',
                          'ຊື່ພາສາລາວ',
                        ][i],
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: [
                      for (final t in [
                        'text',
                        'multiline',
                        'date',
                        'money',
                        'currency',
                        'number',
                      ])
                        DropdownMenuItem(
                          value: t,
                          child: Text(
                            {
                              'text': s.tr(
                                'Văn bản ngắn',
                                'Short text',
                                'ຂໍ້ຄວາມສັ້ນ',
                              ),
                              'multiline': s.tr(
                                'Nội dung dài',
                                'Long text',
                                'ຂໍ້ຄວາມຍາວ',
                              ),
                              'date': s.tr('Ngày', 'Date', 'ວັນທີ'),
                              'money': s.tr('Số tiền', 'Money', 'ເງິນ'),
                              'currency': s.tr(
                                'Tiền tệ',
                                'Currency',
                                'ສະກຸນເງິນ',
                              ),
                              'number': s.tr('Số lượng', 'Number', 'ຈຳນວນ'),
                            }[t]!,
                          ),
                        ),
                    ],
                    onChanged: (v) => type = v!,
                  ),
                  CheckboxListTile(
                    title: Text(s.tr('Bắt buộc', 'Required', 'ຈຳເປັນ')),
                    value: required,
                    onChanged: (v) => update(() => required = v!),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  if (labels.any((c) => c.text.trim().isEmpty)) return;
                  Navigator.pop(ctx, {
                    'key': 'field_${DateTime.now().microsecondsSinceEpoch}',
                    'label': labels.map((c) => c.text.trim()).toList(),
                    'type': type,
                    'required': required,
                  });
                },
                child: Text(s.tr('Thêm', 'Add', 'ເພີ່ມ')),
              ),
            ],
          ),
        ),
      );
      for (final c in labels) {
        c.dispose();
      }
      return result;
    }

    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            s.tr('Mẫu văn bản riêng', 'Custom template', 'ແບບເອກະສານເອງ'),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    TextField(
                      controller: names[i],
                      decoration: InputDecoration(
                        labelText: [
                          'Tên tiếng Việt',
                          'English name',
                          'ຊື່ພາສາລາວ',
                        ][i],
                      ),
                    ),
                  TextField(
                    controller: prefix,
                    decoration: InputDecoration(
                      labelText: s.tr(
                        'Tiền tố mã tự động (2–6 chữ in hoa)',
                        'Automatic code prefix (2–6 uppercase letters)',
                        'ຄຳນຳລະຫັດ (2–6 ຕົວອັກສອນໃຫຍ່)',
                      ),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: permission,
                    items: [
                      for (final entry in {
                        'office.edit': s.tr('Văn phòng', 'Office', 'ຫ້ອງການ'),
                        'finance.approve': s.tr(
                          'Tài chính',
                          'Finance',
                          'ການເງິນ',
                        ),
                        'attendance.verify': s.tr(
                          'Nhân sự',
                          'Personnel',
                          'ບຸກຄະລາກອນ',
                        ),
                        'purchase.approve': s.tr(
                          'Mua hàng',
                          'Purchasing',
                          'ຈັດຊື້',
                        ),
                        'inventory.approve': s.tr('Kho', 'Inventory', 'ສາງ'),
                        'machine.verify': s.tr(
                          'Máy móc',
                          'Machines',
                          'ເຄື່ອງຈັກ',
                        ),
                      }.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (v) => permission = v!,
                  ),
                  for (final f in fields)
                    ListTile(
                      title: Text(s.name(f['label'])),
                      trailing: IconButton(
                        onPressed: () => update(() => fields.remove(f)),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  TextButton(
                    onPressed: fields.length >= 20
                        ? null
                        : () async {
                            final f = await field(ctx);
                            if (f != null) update(() => fields.add(f));
                          },
                    child: Text(s.tr('Thêm trường', 'Add field', 'ເພີ່ມຊ່ອງ')),
                  ),
                  if (localError != null) Text(localError!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
            ),
            FilledButton(
              onPressed: () {
                if (names.any((c) => c.text.trim().isEmpty) ||
                    !RegExp(r'^[A-Z]{2,6}$').hasMatch(prefix.text.trim()) ||
                    fields.isEmpty) {
                  update(
                    () => localError = s.tr(
                      'Điền đủ tên, tiền tố và ít nhất một trường.',
                      'Fill names, prefix and at least one field.',
                      'ປ້ອນຊື່ ລະຫັດ ແລະ ຢ່າງໜ້ອຍໜຶ່ງຊ່ອງ.',
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'id': old?['id'] ?? 'custom_${service.newId()}',
                  'prefix': prefix.text.trim(),
                  'names': names.map((c) => c.text.trim()).toList(),
                  'permission': permission,
                  'fields': fields,
                });
              },
              child: Text(s.tr('Lưu phiên bản', 'Save version', 'ບັນທຶກສະບັບ')),
            ),
          ],
        ),
      ),
    );
    for (final c in [...names, prefix]) {
      c.dispose();
    }
    if (result != null) {
      await run(() async {
        await service.request(
          'template.save',
          entity: result['id'] as String,
          revision: old?['version'] as int? ?? 0,
          payload: result,
        );
      });
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!service.can(PermissionCodes.accountManage) ||
        !service.can(PermissionCodes.roleManage)) {
      return Scaffold(body: Text(s.error(const WorkspaceFailure('denied'))));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.tr(
            'Mẫu và tuyến duyệt',
            'Templates and approval routes',
            'ແບບ ແລະ ເສັ້ນທາງອະນຸມັດ',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy ? null : () => template(),
            child: Text(
              s.tr('Thêm mẫu riêng', 'Add custom template', 'ເພີ່ມແບບເອງ'),
            ),
          ),
          for (final t in templates)
            ListTile(
              title: Text(s.name(t['names'])),
              subtitle: Text('${t['prefix']} · v${t['version']}'),
              onTap: (t['id'] as String).startsWith('custom_') && !busy
                  ? () => template(old: t)
                  : null,
            ),
          FilledButton(
            onPressed: busy ? null : () => route(),
            child: Text(
              s.tr(
                'Thêm tuyến duyệt',
                'Add approval route',
                'ເພີ່ມເສັ້ນທາງອະນຸມັດ',
              ),
            ),
          ),
          for (final r in routes)
            ListTile(
              title: Text(
                '${s.name(templates.firstWhere((t) => t['id'] == r['templateId'])['names'])} · ${r['department']}',
              ),
              subtitle: Text(
                (r['steps'] as List).map((p) => p['name']).join(' → '),
              ),
              onTap: busy ? null : () => route(old: r),
            ),
        ],
      ),
    );
  }
}
