import 'package:flutter/material.dart';

import '../application/workspace_service.dart';
import '../../../core/permissions/authorization.dart';
import 'workspace_strings.dart';

class WorkspaceAssistantScreen extends StatefulWidget {
  const WorkspaceAssistantScreen({super.key, required this.service});
  final WorkspaceService service;
  @override
  State<WorkspaceAssistantScreen> createState() => _AssistantState();
}

class _AssistantState extends State<WorkspaceAssistantScreen> {
  final input = TextEditingController();
  final period = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 7),
  );
  bool financial = false;
  Json? pendingPayload;
  String? answer, error, operation, question;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final s = widget.service;
    final old = await s.local.value(s.farm, s.uid, 'ai_pending');
    if (old != null && old['operation'] is String && mounted) {
      setState(() {
        operation = old['operation'] as String;
        question = old['question'] as String;
        input.text = question!;
        pendingPayload = jsonMap(
          old['payload'] ??
              {'question': question, 'language': 'vi', 'financial': false},
        );
        financial = pendingPayload!['financial'] == true;
        if (pendingPayload!['period'] is String) {
          period.text = pendingPayload!['period'] as String;
        }
      });
    }
  }

  @override
  void dispose() {
    input.dispose();
    period.dispose();
    super.dispose();
  }

  Future<void> ask() async {
    if (busy || input.text.trim().isEmpty) return;
    final s = WorkspaceStrings(context);
    final service = widget.service;
    setState(() => busy = true);
    try {
      operation ??= service.newId();
      question ??= input.text.trim();
      pendingPayload ??= {
        'question': question,
        'language': s.language,
        'financial': financial,
        if (financial) 'period': period.text.trim(),
      };
      await service.local.putValue(service.farm, service.uid, 'ai_pending', {
        'operation': operation,
        'question': question,
        'payload': pendingPayload,
      });
      final result = await service.request(
        'ai.ask',
        operation: operation,
        entity: operation,
        payload: pendingPayload!,
      );
      if (mounted) {
        setState(() {
          answer = result['answer'] as String;
          error = null;
        });
      }
      await service.local.putValue(service.farm, service.uid, 'ai_pending', {});
      operation = null;
      question = null;
      pendingPayload = null;
    } on WorkspaceRejected catch (e) {
      await service.local.putValue(service.farm, service.uid, 'ai_pending', {});
      if (mounted) {
        setState(() {
          operation = null;
          question = null;
          pendingPayload = null;
          error = s.error(e);
        });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.tr('Trợ lý AGRICO', 'AGRICO assistant', 'ຜູ້ຊ່ວຍ AGRICO'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            s.tr(
              'Chỉ đọc hồ sơ được phép xem. Không tự gửi, duyệt hoặc thay đổi số liệu. Cần máy chủ AI đã cấu hình.',
              'Reads authorized records only. Cannot send, approve or modify data. Requires configured AI backend.',
              'ອ່ານແຕ່ເອກະສານທີ່ມີສິດ. ບໍ່ສົ່ງ ອະນຸມັດ ຫຼື ແກ້ຂໍ້ມູນ.',
            ),
          ),
          if (widget.service.can(PermissionCodes.reportFinance))
            CheckboxListTile(
              value: financial,
              onChanged: busy || operation != null
                  ? null
                  : (v) => setState(() => financial = v!),
              title: Text(
                s.tr(
                  'Dùng tổng thu/chi từ bản chụp đã công bố (Admin)',
                  'Use published snapshot cash totals (Admin)',
                  'ໃຊ້ຍອດຮັບ/ຈ່າຍຈາກສຳເນົາ (ຜູ້ດູແລ)',
                ),
              ),
            ),
          if (financial)
            TextField(
              controller: period,
              enabled: !busy && operation == null,
              decoration: const InputDecoration(labelText: 'YYYY-MM'),
            ),
          TextField(
            controller: input,
            enabled: !busy && operation == null,
            maxLength: 2000,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: s.tr('Câu hỏi', 'Question', 'ຄຳຖາມ'),
            ),
          ),
          FilledButton(
            onPressed: busy || !widget.service.canOpen ? null : ask,
            child: Text(
              s.tr(
                'Hỏi / kiểm tra lại yêu cầu',
                'Ask / check pending request',
                'ຖາມ / ກວດຄຳຂໍ',
              ),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (answer != null) SelectableText(answer!),
        ],
      ),
    );
  }
}
