import 'dart:async';

import 'package:flutter/material.dart';

import '../application/workspace_service.dart';
import '../application/workspace_document_export.dart';
import '../domain/administrative_templates.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import 'workspace_strings.dart';
import 'workspace_form_dialog.dart';
import 'workspace_chat_screen.dart';
import 'workspace_settings_screen.dart';

class CompanyWorkspaceScreen extends StatefulWidget {
  const CompanyWorkspaceScreen({
    super.key,
    required this.service,
    this.initialTab = 0,
  });
  final WorkspaceService service;
  final int initialTab;
  @override
  State<CompanyWorkspaceScreen> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<CompanyWorkspaceScreen> {
  List<Json> rows = [], outbox = [];
  bool busy = false;
  String? error;
  Timer? timer;
  WorkspaceService get service => widget.service;
  WorkspaceStrings get s => WorkspaceStrings(context);
  @override
  void initState() {
    super.initState();
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!busy) unawaited(load());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final cached = await service.records();
      final pending = await service.local.pending(service.farm, service.uid);
      if (mounted) {
        setState(() {
          rows = cached;
          outbox = pending;
        });
      }
      await service.sync();
      final current = await service.records();
      final next = await service.local.pending(service.farm, service.uid);
      if (mounted) {
        setState(() {
          rows = current;
          outbox = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = s.error(e));
    }
  }

  Future<void> work(Future<void> Function() body) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await body();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = s.error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> text(
    String title, {
    String initial = '',
    String? hint,
  }) async {
    final c = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(hintText: hint),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(s.tr('Tiếp tục', 'Continue', 'ຕໍ່ໄປ')),
          ),
        ],
      ),
    );
    c.dispose();
    return value;
  }

  Future<Json?> choose(
    List<Json> choices,
    String title,
    String Function(Json) label,
  ) async {
    if (!mounted) return null;
    return showDialog<Json>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          if (choices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                s.tr(
                  'Chưa có lựa chọn phù hợp. Admin cần cấu hình trước.',
                  'No eligible choices. Ask Admin to configure them.',
                  'ຍັງບໍ່ມີທາງເລືອກ. ໃຫ້ຜູ້ດູແລຕັ້ງຄ່າ.',
                ),
              ),
            ),
          for (final c in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text(label(c)),
            ),
        ],
      ),
    );
  }

  Future<void> createTask() async {
    final members = await service.directory();
    final user = await choose(
      members.where((u) => u['uid'] != service.uid).toList(),
      s.tr('Người nhận', 'Assignee', 'ຜູ້ຮັບ'),
      (u) => u['name'] as String,
    );
    if (user == null) return;
    final title = await text(s.tr('Tên công việc', 'Task title', 'ຊື່ວຽກ'));
    if (title == null || title.isEmpty) return;
    final details = await text(
      s.tr(
        'Nội dung / tiêu chí nghiệm thu',
        'Details / acceptance criteria',
        'ເນື້ອໃນ / ເກນກວດຮັບ',
      ),
    );
    if (details == null || details.isEmpty) return;
    final due = await text(
      s.tr('Hạn hoàn thành', 'Due date', 'ກຳນົດສຳເລັດ'),
      hint: 'YYYY-MM-DD',
    );
    if (due == null || due.isEmpty) return;
    await service.queue(
      'task.create',
      entity: service.newId(),
      payload: {
        'assignee': user['uid'],
        'title': title,
        'details': details,
        'due': due,
      },
    );
  }

  Future<void> createForm() async {
    List<Json> templates = administrativeTemplates;
    try {
      final result = await service.request('template.list');
      templates = (result['templates'] as List).map(jsonMap).toList();
    } catch (_) {
      /* Offline built-in templates remain available. */
    }
    final template = await choose(
      templates,
      s.tr('Mẫu văn bản', 'Administrative template', 'ແບບເອກະສານ'),
      (t) => s.name(t['names']),
    );
    if (template == null || !mounted) return;
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => WorkspaceFormDialog(service: service, template: template),
    );
    if (result != null) {
      await service.queue(
        'form.create',
        entity: service.newId(),
        payload: result,
      );
    }
  }

  Future<void> createRoom({Json? source}) async {
    final directory = await service.directory();
    final options = directory
        .where(
          (u) =>
              u['uid'] != service.uid &&
              (source == null ||
                  (source['participants'] as List).contains(u['uid'])),
        )
        .toList();
    final selected = <String>{};
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            s.tr(
              'Chọn người tham gia',
              'Select participants',
              'ເລືອກຜູ້ເຂົ້າຮ່ວມ',
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final u in options)
                    CheckboxListTile(
                      value: selected.contains(u['uid']),
                      title: Text(u['name'] as String),
                      onChanged: (v) => update(() {
                        if (v == true && selected.length < 19) {
                          selected.add(u['uid'] as String);
                        } else {
                          selected.remove(u['uid']);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.tr('Tiếp tục', 'Continue', 'ຕໍ່ໄປ')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selected.isEmpty) return;
    final title = await text(
      s.tr('Tên cuộc trò chuyện', 'Conversation title', 'ຊື່ການສົນທະນາ'),
      initial: source?['code'] as String? ?? '',
    );
    if (title == null || title.isEmpty) return;
    await service.queue(
      'room.create',
      entity: service.newId(),
      payload: {
        'title': title,
        'members': selected.toList(),
        if (source != null) ...{
          'sourceId': source['id'],
          'sourceKind': source['kind'],
        },
      },
    );
  }

  Future<void> action(Json r, String action) async {
    final payload = <String, dynamic>{};
    if (action == 'form.submit') {
      final result = await service.request('route.list');
      final template = jsonMap(jsonMap(r['content'])['template']);
      final selected = await choose(
        (result['routes'] as List)
            .map(jsonMap)
            .where(
              (v) =>
                  v['templateId'] == template['id'] &&
                  service.subject.departmentIds.contains(v['department']),
            )
            .toList(),
        s.tr('Tuyến duyệt', 'Approval route', 'ເສັ້ນທາງອະນຸມັດ'),
        (v) =>
            '${v['department']} · ${(v['steps'] as List).map((p) => p['name']).join(' → ')}',
      );
      if (selected == null) return;
      payload['routeId'] = selected['id'];
    } else if (action == 'task.progress') {
      final value = await text(
        s.tr('Tiến độ 0–100%', 'Progress 0–100%', 'ຄວາມຄືບໜ້າ 0–100%'),
      );
      final n = int.tryParse(value ?? '');
      if (n == null || n < 0 || n > 100) return;
      payload['progress'] = n;
    } else if ([
      'task.rework',
      'task.cancel',
      'form.changes',
      'form.reject',
      'form.withdraw',
    ].contains(action)) {
      final reason = await text(s.tr('Lý do', 'Reason', 'ເຫດຜົນ'));
      if (reason == null || reason.isEmpty) return;
      payload['reason'] = reason;
    }
    await service.queue(
      action,
      entity: r['id'] as String,
      revision: r['revision'] as int,
      payload: payload,
    );
  }

  List<(String, String)> actions(Json r) {
    final c = jsonMap(r['content']);
    final state = r['state'];
    final result = <(String, String)>[];
    if (r['kind'] == 'task') {
      if (c['assignee'] == service.uid &&
          service.can(PermissionCodes.taskComplete)) {
        if (state == 'assigned') {
          result.add(('task.accept', s.tr('Nhận việc', 'Accept', 'ຮັບວຽກ')));
        }
        if (['accepted', 'rework'].contains(state)) {
          result.add(('task.start', s.tr('Bắt đầu', 'Start', 'ເລີ່ມ')));
        }
        if (state == 'inProgress') {
          result.addAll([
            (
              'task.progress',
              s.tr('Cập nhật tiến độ', 'Update progress', 'ປັບຄວາມຄືບໜ້າ'),
            ),
            ('task.submit', s.tr('Nộp nghiệm thu', 'Submit', 'ສົ່ງກວດຮັບ')),
          ]);
        }
      }
      if (r['creator'] == service.uid &&
          service.can(PermissionCodes.taskVerify) &&
          state == 'submitted') {
        result.addAll([
          ('task.verify', s.tr('Nghiệm thu', 'Verify', 'ກວດຮັບ')),
          ('task.rework', s.tr('Làm lại', 'Rework', 'ເຮັດໃໝ່')),
        ]);
      }
      if (r['creator'] == service.uid &&
          service.can(PermissionCodes.taskAssign) &&
          !['verified', 'cancelled'].contains(state)) {
        result.add((
          'task.cancel',
          s.tr('Hủy việc', 'Cancel task', 'ຍົກເລີກວຽກ'),
        ));
      }
    } else {
      if (r['creator'] == service.uid &&
          service.can(PermissionCodes.officeRequest)) {
        if (['draft', 'needsChanges'].contains(state)) {
          result.add((
            'form.submit',
            s.tr('Gửi duyệt', 'Submit', 'ສົ່ງອະນຸມັດ'),
          ));
        }
        if ([
          'draft',
          'needsChanges',
          'submitted',
          'received',
        ].contains(state)) {
          result.add(('form.withdraw', s.tr('Rút phiếu', 'Withdraw', 'ຖອນໃບ')));
        }
      } else if (service.can(jsonMap(c['template'])['permission'] as String)) {
        final steps = jsonMap(c['route'] ?? {})['steps'] as List? ?? [];
        if (['submitted', 'received'].contains(state) &&
            steps.isNotEmpty &&
            steps[c['step'] as int]['uid'] == service.uid) {
          result.addAll([
            ('form.receive', s.tr('Tiếp nhận', 'Receive', 'ຮັບໃບ')),
            ('form.approve', s.tr('Duyệt', 'Approve', 'ອະນຸມັດ')),
            (
              'form.changes',
              s.tr('Yêu cầu bổ sung', 'Request changes', 'ຂໍເພີ່ມເຕີມ'),
            ),
            ('form.reject', s.tr('Từ chối', 'Reject', 'ປະຕິເສດ')),
          ]);
        }
        if (state == 'approved') {
          result.add((
            'form.complete',
            s.tr('Hoàn tất hồ sơ', 'Complete filing', 'ສຳເລັດເອກະສານ'),
          ));
        }
      }
    }
    return result;
  }

  Future<void> detail(Json r) async {
    if (!service.canReadRecord(r)) {
      setState(() => error = s.error(const WorkspaceFailure('denied')));
      return;
    }
    final c = jsonMap(r['content']);
    if (r['kind'] == 'room') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceChatScreen(service: service, room: r),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r['code']} · ${s.state(r['state'] as String)}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['creatorName']} · ${r['createdAt']}'),
                if (r['kind'] == 'task') ...[
                  Text(c['title'] as String),
                  Text(c['details'] as String),
                  Text(
                    '${c['assigneeName']} · ${c['due']} · ${c['progress']}%',
                  ),
                ] else ...[
                  Text(s.name(jsonMap(c['template'])['names'])),
                  for (final raw in jsonMap(c['template'])['fields'] as List)
                    Text(
                      '${s.name(jsonMap(raw)['label'])}: ${jsonMap(c['fields'])[jsonMap(raw)['key']] ?? ''}',
                    ),
                  Text(
                    s.tr(
                      'Duyệt chưa tự phát sinh thu chi/lương/kho.',
                      'Approval does not post cash/payroll/stock.',
                      'ອະນຸມັດບໍ່ລົງເງິນ/ເງິນເດືອນ/ສາງ.',
                    ),
                  ),
                ],
                for (final raw in c['files'] as List? ?? [])
                  TextButton.icon(
                    onPressed: () => work(() async {
                      final f = jsonMap(raw);
                      await saveExcelBytes(
                        await service.file(r, f),
                        attachmentFileName(f),
                      );
                    }),
                    icon: const Icon(Icons.download),
                    label: Text(jsonMap(raw)['name'] as String),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final a in actions(r))
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                unawaited(work(() => action(r, a.$1)));
                              },
                        child: Text(a.$2),
                      ),
                  ],
                ),
                if (r['kind'] == 'form' &&
                    r['creator'] == service.uid &&
                    service.can(PermissionCodes.officeRequest) &&
                    ['draft', 'needsChanges'].contains(r['state']))
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(
                        work(() async {
                          final result = await showDialog<Json>(
                            context: context,
                            builder: (_) => WorkspaceFormDialog(
                              service: service,
                              template: jsonMap(c['template']),
                              record: r,
                            ),
                          );
                          if (result != null) {
                            await service.queue(
                              'form.edit',
                              entity: r['id'] as String,
                              revision: r['revision'] as int,
                              payload: result,
                            );
                          }
                        }),
                      );
                    },
                    child: Text(s.tr('Sửa nháp', 'Edit draft', 'ແກ້ຮ່າງ')),
                  ),
                if (r['kind'] == 'form')
                  TextButton(
                    onPressed: () => work(() async {
                      await saveExcelBytes(
                        WorkspaceDocumentExport.create(r, s.index),
                        'AGRICO-${r['code']}.docx',
                      );
                    }),
                    child: Text(
                      s.tr('Xuất Word', 'Export Word', 'ສົ່ງອອກ Word'),
                    ),
                  ),
                if (service.can(PermissionCodes.chatSend))
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(work(() => createRoom(source: r)));
                    },
                    child: Text(
                      s.tr(
                        'Trao đổi theo hồ sơ',
                        'Discuss this record',
                        'ສົນທະນາຕາມເອກະສານ',
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(work(() => history(r)));
                  },
                  child: Text(s.tr('Lịch sử', 'History', 'ປະຫວັດ')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.tr('Đóng', 'Close', 'ປິດ')),
          ),
        ],
      ),
    );
  }

  Future<void> history(Json r) async {
    final result = await service.request(
      'record.history',
      entity: r['id'] as String,
      payload: {'kind': r['kind']},
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tr('Lịch sử', 'History', 'ປະຫວັດ')),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final e in result['events'] as List)
                  ListTile(
                    title: Text(
                      '${e['name']} · ${s.state(e['state'] as String)}',
                    ),
                    subtitle: Text('${e['at']}\n${e['reason']}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.tr('Đóng', 'Close', 'ປິດ')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!service.canOpen) {
      return Scaffold(
        body: Center(child: Text(s.error(const WorkspaceFailure('denied')))),
      );
    }
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            s.tr('Không gian công ty', 'Company workspace', 'ພື້ນທີ່ບໍລິສັດ'),
          ),
          actions: [
            if (service.can(PermissionCodes.accountManage) &&
                service.can(PermissionCodes.roleManage))
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => WorkspaceSettingsScreen(service: service),
                  ),
                ),
                icon: const Icon(Icons.settings),
              ),
            IconButton(
              onPressed: busy ? null : () => work(load),
              icon: const Icon(Icons.sync),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: s.tr('Giao việc', 'Tasks', 'ມອບວຽກ')),
              Tab(text: s.tr('Hành chính', 'Requests', 'ເອກະສານ')),
              Tab(text: s.tr('Chat', 'Chat', 'ສົນທະນາ')),
              Tab(text: s.tr('Hàng chờ', 'Outbox', 'ລໍຖ້າ')),
            ],
          ),
        ),
        body: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            Expanded(
              child: TabBarView(
                children: [
                  for (final kind in ['task', 'form', 'room'])
                    Column(
                      children: [
                        if (kind == 'task' &&
                                service.can(PermissionCodes.taskCreate) &&
                                service.can(PermissionCodes.taskAssign) ||
                            kind == 'form' &&
                                service.can(PermissionCodes.officeRequest) ||
                            kind == 'room' &&
                                service.can(PermissionCodes.chatSend))
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => work(
                                    kind == 'task'
                                        ? createTask
                                        : kind == 'form'
                                        ? createForm
                                        : createRoom,
                                  ),
                            icon: const Icon(Icons.add),
                            label: Text(s.tr('Tạo mới', 'Create', 'ສ້າງໃໝ່')),
                          ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final r in rows.where(
                                (r) => r['kind'] == kind,
                              ))
                                ListTile(
                                  title: Text(
                                    kind == 'form'
                                        ? s.name(
                                            jsonMap(
                                              jsonMap(r['content'])['template'],
                                            )['names'],
                                          )
                                        : jsonMap(r['content'])['title']
                                              as String,
                                  ),
                                  subtitle: Text(
                                    '${r['code'] ?? ''} · ${s.state(r['state'] as String)}',
                                  ),
                                  onTap: () => detail(r),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ListView(
                    children: [
                      for (final r in outbox)
                        ListTile(
                          leading: Icon(
                            r['error'] == null
                                ? Icons.schedule
                                : Icons.error_outline,
                          ),
                          title: Text('${r['action']} · ${r['entityId']}'),
                          subtitle: Text(
                            r['error'] == null
                                ? s.tr(
                                    'Chưa xác nhận máy chủ',
                                    'Server not confirmed',
                                    'ເຊີບເວີຍັງບໍ່ຢືນຢັນ',
                                  )
                                : s.error(
                                    WorkspaceFailure(r['error'] as String),
                                  ),
                          ),
                          trailing: r['error'] == null
                              ? null
                              : IconButton(
                                  onPressed: () => work(
                                    () => service.local.discard(
                                      service.farm,
                                      service.uid,
                                      r['id'] as String,
                                    ),
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
