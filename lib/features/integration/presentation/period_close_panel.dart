import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../application/period_close_service.dart';
import '../domain/period_close.dart';

class PeriodClosePanel extends StatefulWidget {
  const PeriodClosePanel({
    super.key,
    required this.service,
    required this.period,
    required this.onChanged,
  });
  final PeriodCloseService service;
  final String period;
  final VoidCallback onChanged;
  @override
  State<PeriodClosePanel> createState() => _PeriodClosePanelState();
}

class _PeriodClosePanelState extends State<PeriodClosePanel> {
  late Future<PeriodReview> future;
  bool busy = false;
  String tr(String vi, String en, String lo) =>
      switch (AppLocalizations.of(context).locale.languageCode) {
        'vi' => vi,
        'lo' => lo,
        _ => en,
      };
  @override
  void initState() {
    super.initState();
    future = widget.service.review(widget.period);
  }

  @override
  void didUpdateWidget(covariant PeriodClosePanel old) {
    super.didUpdateWidget(old);
    future = widget.service.review(widget.period);
  }

  String issue(String value) {
    final key = value.split(':').first;
    final source = value.split(':').length > 1 ? value.split(':')[1] : '';
    final module = switch (source) {
      'personnel_entries_v1' => tr('Chấm công', 'Attendance', 'ບັນທຶກເວລາ'),
      'personnel_payrolls_v1' => tr('Bảng lương', 'Payroll', 'ບັນຊີເງິນເດືອນ'),
      'personnel_payroll_adjustments_v1' => tr(
        'Điều chỉnh lương',
        'Payroll corrections',
        'ປັບເງິນເດືອນ',
      ),
      'machine_runs_v1' => tr('Ca máy', 'Machine runs', 'ກະເຄື່ອງຈັກ'),
      'machine_expenses_v1' => tr(
        'Chi phí máy',
        'Machine expenses',
        'ຄ່າເຄື່ອງຈັກ',
      ),
      'trade_documents_v1' => tr(
        'Thu hoạch / mua bán',
        'Harvest / trade',
        'ເກັບກ່ຽວ / ຊື້ຂາຍ',
      ),
      _ => '',
    };
    return switch (key) {
      'monthNotEnded' => tr(
        'Chưa kết thúc tháng.',
        'Month has not ended.',
        'ເດືອນຍັງບໍ່ສິ້ນສຸດ.',
      ),
      'laterPeriodClosed' => tr(
        'Có kỳ sau đã khóa; mở lại từ kỳ mới nhất.',
        'A later period is closed; reopen newest first.',
        'ມີເດືອນຕໍ່ໄປລັອກແລ້ວ; ເປີດເດືອນລ່າສຸດກ່ອນ.',
      ),
      'draft' =>
        tr(
              'Còn chứng từ nháp cần xử lý',
              'Unresolved draft documents',
              'ມີເອກະສານຮ່າງທີ່ຕ້ອງຈັດການ',
            ) +
            ' · $module (${value.split(':').last})',
      'unlinkedSalary' =>
        tr(
              'Chi lương chưa liên kết sổ tiền',
              'Salary payments need cash links',
              'ການຈ່າຍເງິນເດືອນຍັງບໍ່ເຊື່ອມບັນຊີເງິນ',
            ) +
            ' (${value.split(':').last})',
      'unclassifiedMachine' => tr(
        'Khoản máy chưa phân loại nguồn.',
        'Machine expenses need source classification.',
        'ລາຍຈ່າຍເຄື່ອງຈັກຍັງບໍ່ຈັດປະເພດແຫຼ່ງ.',
      ),
      'historicalStockNegative' => tr(
        'Tồn kho cuối kỳ âm; kiểm tra ngày nhập/xuất.',
        'Negative closing stock; check receipt/issue dates.',
        'ສາງທ້າຍເດືອນຕິດລົບ; ກວດວັນຮັບ/ຈ່າຍ.',
      ),
      _ => tr(
        'Sổ chưa khớp; kiểm tra đối soát trước khi chốt.',
        'Ledger mismatch; reconcile before closing.',
        'ບັນຊີບໍ່ກົງ; ກວດທຽບກ່ອນປິດ.',
      ),
    };
  }

  Future<void> act(PeriodReview review) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) =>
          _PeriodReasonDialog(closed: review.closed, period: review.period),
    );
    if (text == null || !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      if (review.closed) {
        await widget.service.reopen(review, text);
      } else {
        await widget.service.close(review, text);
      }
      if (mounted) {
        widget.onChanged();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Chưa thực hiện. Làm mới đối soát; kiểm tra quyền, kỳ và dữ liệu đã thay đổi.',
                'Not applied. Refresh the review; check permissions, period and changed data.',
                'ບໍ່ສຳເລັດ. ໂຫຼດການກວດຄືນ; ກວດສິດ, ເດືອນ ແລະ ຂໍ້ມູນ.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          future = widget.service.review(widget.period);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<PeriodReview>(
        future: future,
        builder: (ctx, s) {
          if (s.hasError) {
            return Text(
              tr(
                'Không tải được trạng thái khóa kỳ.',
                'Cannot load closing state.',
                'ໂຫຼດສະຖານະປິດບໍ່ໄດ້.',
              ),
            );
          }
          if (!s.hasData) {
            return const LinearProgressIndicator();
          }
          final r = s.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.period} · ${r.closed ? tr('Đã khóa', 'Closed', 'ລັອກແລ້ວ') : tr('Đang mở', 'Open', 'ເປີດຢູ່')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...r.issues
                  .where((v) => !r.closed || v == 'laterPeriodClosed')
                  .map((v) => Text('• ${issue(v)}')),
              if (busy) const LinearProgressIndicator(),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            setState(
                              () =>
                                  future = widget.service.review(widget.period),
                            );
                          },
                    child: Text(
                      tr(
                        'Làm mới đối soát kỳ',
                        'Refresh closing review',
                        'ກວດທຽບເດືອນຄືນ',
                      ),
                    ),
                  ),
                  if (r.closed
                      ? widget.service.canReopen
                      : widget.service.canClose)
                    FilledButton(
                      onPressed:
                          busy ||
                              (!r.closed && r.issues.isNotEmpty) ||
                              (r.closed &&
                                  r.issues.contains('laterPeriodClosed'))
                          ? null
                          : () => act(r),
                      child: Text(
                        r.closed
                            ? tr('Mở lại kỳ', 'Reopen period', 'ເປີດເດືອນຄືນ')
                            : tr('Khóa kỳ', 'Close period', 'ປິດເດືອນ'),
                      ),
                    ),
                ],
              ),
              for (final e in r.history.reversed)
                ListTile(
                  dense: true,
                  title: Text(
                    '${e['action'] == 'close' ? tr('Khóa kỳ', 'Close', 'ປິດ') : tr('Mở lại', 'Reopen', 'ເປີດຄືນ')} · ${e['actor_id']}',
                  ),
                  subtitle: Text('${e['occurred_at']}\n${e['reason']}'),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _PeriodReasonDialog extends StatefulWidget {
  const _PeriodReasonDialog({required this.closed, required this.period});
  final bool closed;
  final String period;
  @override
  State<_PeriodReasonDialog> createState() => _PeriodReasonDialogState();
}

class _PeriodReasonDialogState extends State<_PeriodReasonDialog> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  String tr(String vi, String en, String lo) =>
      switch (AppLocalizations.of(context).locale.languageCode) {
        'vi' => vi,
        'lo' => lo,
        _ => en,
      };
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.closed
          ? '${widget.period} · ${tr('Mở lại kỳ', 'Reopen period', 'ເປີດເດືອນຄືນ')}'
          : '${widget.period} · ${tr('Xác nhận khóa kỳ', 'Confirm closing', 'ຢືນຢັນປິດເດືອນ')}',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.closed
                  ? tr(
                      'Cho phép sửa kỳ này. Lịch sử chốt cũ được giữ nguyên.',
                      'Allows changes to this period. Previous closing history is retained.',
                      'ອະນຸຍາດແກ້ໄຂເດືອນນີ້. ເກັບປະຫວັດການປິດເກົ່າ.',
                    )
                  : tr(
                      'Chặn ghi lùi ngày đến hết kỳ này. Báo cáo 20 sheet dùng bản chốt; công nợ còn lại chuyển tiếp, VND và LAK tách riêng.',
                      'Blocks backdated postings through this month. The 20-sheet report uses the frozen snapshot; outstanding debts carry forward and VND/LAK stay separate.',
                      'ຫ້າມບັນທຶກຍ້ອນວັນເຖິງສິ້ນເດືອນ. ລາຍງານ 20 ແຜ່ນໃຊ້ຂໍ້ມູນທີ່ປິດ; ຍົກໜີ້ໄປ ແລະ ແຍກ VND/LAK.',
                    ),
            ),
            TextFormField(
              controller: reason,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: tr(
                  'Lý do bắt buộc',
                  'Reason required',
                  'ຕ້ອງລະບຸເຫດຜົນ',
                ),
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? tr('Nhập lý do', 'Enter a reason', 'ປ້ອນເຫດຜົນ')
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: Text(tr('Xác nhận', 'Confirm', 'ຢືນຢັນ')),
      ),
    ],
  );
}
