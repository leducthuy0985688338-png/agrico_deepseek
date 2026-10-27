import 'package:flutter/material.dart';

import '../application/workspace_cloud_service.dart';
import '../application/workspace_service.dart';
import 'workspace_strings.dart';

class WorkspaceCloudScreen extends StatefulWidget {
  const WorkspaceCloudScreen({
    super.key,
    required this.service,
    required this.openCatalog,
  });
  final WorkspaceCloudService service;
  final VoidCallback? openCatalog;
  @override
  State<WorkspaceCloudScreen> createState() => _CloudState();
}

class _CloudState extends State<WorkspaceCloudScreen> {
  bool busy = false;
  String? message;
  CloudPreview? preview;
  Json? head;
  WorkspaceStrings get s => WorkspaceStrings(context);
  Future<void> run(Future<void> Function() body) async {
    setState(() => busy = true);
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => message = s.error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish() async {
    try {
      final next = await widget.service.publish();
      if (mounted) {
        setState(() {
          head = next;
          message = s.tr(
            'Đã công bố bản chụp',
            'Snapshot published',
            'ເຜີຍແຜ່ສຳເນົາແລ້ວ',
          );
        });
      }
    } on WorkspaceFailure catch (e) {
      if (e.code != 'conflict') rethrow;
      final latest = await widget.service.head();
      if (!mounted) return;
      final reason = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            s.tr('Xung đột dữ liệu', 'Data conflict', 'ຂໍ້ມູນຂັດແຍ່ງ'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.tr(
                  'Máy chủ có bản mới. Hãy tải xem trước để so sánh. Chỉ chọn bản máy này khi đã kiểm tra; các thay đổi không tự gộp.',
                  'Server has a newer version. Preview it first. Select this device only after comparison; changes are not merged.',
                  'ເຊີບເວີມີສະບັບໃໝ່. ກວດກ່ອນເລືອກສະບັບເຄື່ອງນີ້; ບໍ່ລວມອັດຕະໂນມັດ.',
                ),
              ),
              Text('${latest?['revision']} · ${latest?['at']}'),
              TextField(
                controller: reason,
                decoration: InputDecoration(
                  labelText: s.tr(
                    'Lý do chọn bản máy này',
                    'Reason for choosing this device',
                    'ເຫດຜົນເລືອກເຄື່ອງນີ້',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                s.tr('Quay lại so sánh', 'Back to comparison', 'ກັບໄປປຽບທຽບ'),
              ),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().isNotEmpty) Navigator.pop(ctx, true);
              },
              child: Text(
                s.tr(
                  'Chọn bản máy này',
                  'Choose this device',
                  'ເລືອກເຄື່ອງນີ້',
                ),
              ),
            ),
          ],
        ),
      );
      final why = reason.text.trim();
      reason.dispose();
      if (confirmed == true) {
        final next = await widget.service.publish(
          resolvedRevision: latest!['revision'] as int,
          reason: why,
        );
        if (mounted) setState(() => head = next);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('Đồng bộ Cloud', 'Cloud sync', 'ຊິ້ງ Cloud')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            s.tr(
              'Giao việc, hồ sơ và chat dùng hàng chờ riêng. Số liệu kinh doanh dùng bản chụp đầy đủ dành cho Admin; chưa tự gộp giao dịch kho/kế toán từ nhiều máy.',
              'Tasks, requests and chat have their own outbox. Business data uses full Admin snapshots; concurrent stock/accounting changes are not merged.',
              'ວຽກ ເອກະສານ ແລະ ແຊັດມີຄິວແຍກ. ຂໍ້ມູນທຸລະກິດໃຊ້ສຳເນົາຄົບສຳລັບຜູ້ດູແລ; ບໍ່ລວມລາຍການອັດຕະໂນມັດ.',
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await service.workspace.sync();
                    if (mounted) {
                      setState(
                        () => message = s.tr(
                          'Đã kiểm tra hàng chờ',
                          'Outbox checked',
                          'ກວດຄິວແລ້ວ',
                        ),
                      );
                    }
                  }),
            child: Text(
              s.tr(
                'Đồng bộ hồ sơ / chat',
                'Sync requests / chat',
                'ຊິ້ງເອກະສານ / ແຊັດ',
              ),
            ),
          ),
          if (widget.openCatalog != null)
            TextButton(
              onPressed: widget.openCatalog,
              child: Text(
                s.tr(
                  'Đồng bộ danh mục chung',
                  'Sync shared catalog',
                  'ຊິ້ງລາຍການຮ່ວມ',
                ),
              ),
            ),
          if (service.canUse) ...[
            const Divider(),
            FilledButton(
              onPressed: busy ? null : () => run(publish),
              child: Text(
                s.tr(
                  'Công bố bản chụp máy này',
                  'Publish this device snapshot',
                  'ເຜີຍແຜ່ສຳເນົາເຄື່ອງນີ້',
                ),
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final p = await service.preview();
                      if (mounted) {
                        setState(() {
                          preview = p;
                          head = p.head;
                        });
                      }
                    }),
              child: Text(
                s.tr(
                  'Tải xem trước bản máy chủ',
                  'Preview server snapshot',
                  'ເບິ່ງສຳເນົາເຊີບເວີ',
                ),
              ),
            ),
            if (head != null)
              SelectableText(
                '${head!['revision']} · ${head!['at']}\n${head!['sha256']}',
              ),
            if (preview != null) ...[
              for (final c in preview!.counts.entries)
                Text('${c.key}: ${c.value}'),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                              s.tr(
                                'Thay dữ liệu máy bằng bản đã xem?',
                                'Replace local data with this preview?',
                                'ປ່ຽນຂໍ້ມູນເຄື່ອງດ້ວຍສຳເນົານີ້?',
                              ),
                            ),
                            content: Text(
                              s.tr(
                                'Đây là phục hồi toàn bộ số liệu, cần khởi động lại app sau khi hẹn phục hồi.',
                                'This restores the complete business snapshot. Restart the app after scheduling.',
                                'ຟື້ນຟູຂໍ້ມູນທັງໝົດ. ເປີດແອັບໃໝ່ຫຼັງຕັ້ງເວລາ.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(s.tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(
                                  s.tr(
                                    'Xác nhận phục hồi',
                                    'Confirm restore',
                                    'ຢືນຢັນຟື້ນຟູ',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await service.schedule(preview!);
                          if (mounted) {
                            setState(
                              () => message = s.tr(
                                'Đã hẹn phục hồi. Hãy khởi động lại app.',
                                'Restore scheduled. Restart the app.',
                                'ຕັ້ງຟື້ນຟູແລ້ວ. ເປີດແອັບໃໝ່.',
                              ),
                            );
                          }
                        }
                      }),
                child: Text(
                  s.tr(
                    'Dùng bản đã xem',
                    'Use previewed snapshot',
                    'ໃຊ້ສຳເນົານີ້',
                  ),
                ),
              ),
            ],
          ] else
            Text(
              s.tr(
                'Bản chụp chứa tài chính/lương: chỉ Admin có đủ quyền toàn công ty được sử dụng.',
                'Snapshots include finance/payroll and require full company Admin access.',
                'ສຳເນົາມີການເງິນ/ເງິນເດືອນ: ສະເພາະຜູ້ດູແລທີ່ມີສິດຄົບ.',
              ),
            ),
        ],
      ),
    );
  }
}
