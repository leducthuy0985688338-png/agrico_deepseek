import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../application/workspace_service.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import 'workspace_strings.dart';

class WorkspaceChatScreen extends StatefulWidget {
  const WorkspaceChatScreen({
    super.key,
    required this.service,
    required this.room,
  });
  final WorkspaceService service;
  final Json room;
  @override
  State<WorkspaceChatScreen> createState() => _ChatState();
}

class _ChatState extends State<WorkspaceChatScreen> {
  final input = TextEditingController();
  late Json room;
  List<Json> rows = [], files = [], pending = [];
  Timer? timer;
  bool busy = false;
  String? error;
  WorkspaceService get service => widget.service;
  @override
  void initState() {
    super.initState();
    room = widget.room;
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!busy) unawaited(load());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      await service.records();
      if (!service.canReadRecord(room)) throw const WorkspaceFailure('denied');
      final old = await service.local.value(
        service.farm,
        service.uid,
        'chat_${room['id']}',
      );
      if (mounted && rows.isEmpty && old != null) {
        setState(() => rows = (old['records'] as List).map(jsonMap).toList());
      }
      await service.sync();
      final r = await service.request(
        'message.list',
        entity: room['id'] as String,
      );
      await service.local.putValue(
        service.farm,
        service.uid,
        'chat_${room['id']}',
        r,
      );
      final queued = await service.local.pending(service.farm, service.uid);
      if (mounted) {
        setState(() {
          room = jsonMap(r['room']);
          rows = (r['records'] as List).map(jsonMap).toList();
          pending = queued
              .where((q) => jsonMap(q['payload'])['roomId'] == room['id'])
              .toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = WorkspaceStrings(context).error(e));
    }
  }

  Future<void> send() async {
    if (busy || input.text.trim().isEmpty && files.isEmpty) return;
    setState(() => busy = true);
    try {
      await service.queue(
        'message.create',
        entity: service.newId(),
        revision: room['revision'] as int,
        payload: {
          'roomId': room['id'],
          'text': input.text.trim(),
          'files': files,
        },
      );
      input.clear();
      files = [];
      await load();
    } catch (e) {
      if (mounted) setState(() => error = WorkspaceStrings(context).error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkspaceStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(jsonMap(room['content'])['title'] as String)),
      body: Column(
        children: [
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final r in rows)
                  ListTile(
                    title: Text('${r['creatorName']} · ${r['createdAt']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(jsonMap(r['content'])['text'] as String),
                        for (final raw
                            in jsonMap(r['content'])['files'] as List)
                          TextButton.icon(
                            onPressed: () async {
                              try {
                                final f = jsonMap(raw);
                                await saveExcelBytes(
                                  await service.file(r, f),
                                  attachmentFileName(f),
                                );
                              } catch (e) {
                                if (mounted) setState(() => error = s.error(e));
                              }
                            },
                            icon: const Icon(Icons.download),
                            label: Text(jsonMap(raw)['name'] as String),
                          ),
                      ],
                    ),
                  ),
                for (final p in pending)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(jsonMap(p['payload'])['text'] as String? ?? ''),
                    subtitle: Text(
                      p['error'] == null
                          ? s.tr(
                              'Đang chờ máy chủ',
                              'Pending server',
                              'ລໍຖ້າເຊີບເວີ',
                            )
                          : s.error(WorkspaceFailure(p['error'] as String)),
                    ),
                  ),
              ],
            ),
          ),
          for (final f in files) Text(f['name'] as String),
          if (service.can(PermissionCodes.chatSend))
            SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: busy || files.length >= 5
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              final result = await FilePicker.platform
                                  .pickFiles(withData: true);
                              if (result != null) {
                                final f = result.files.single;
                                final saved = await service.upload(
                                  f.bytes!,
                                  f.name,
                                );
                                if (mounted) setState(() => files.add(saved));
                              }
                            } catch (e) {
                              if (mounted) setState(() => error = s.error(e));
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: input,
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: s.tr('Tin nhắn', 'Message', 'ຂໍ້ຄວາມ'),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: busy ? null : send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
