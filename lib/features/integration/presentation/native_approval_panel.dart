import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/approval/native_approval_store.dart';
import '../../../core/localization/app_localizations.dart';

/// Reused inside existing module routes. No second approval workspace.
class NativeApprovalHost extends StatelessWidget {
  const NativeApprovalHost({
    super.key,
    required this.child,
    required this.store,
    required this.types,
  });
  final Widget child;
  final NativeApprovalStore store;
  final Set<NativeApprovalType> types;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(child: child),
        SafeArea(
          top: false,
          child: NativeApprovalPanel(store: store, types: types),
        ),
      ],
    ),
  );
}

class NativeApprovalPanel extends StatefulWidget {
  const NativeApprovalPanel({
    super.key,
    required this.store,
    required this.types,
  });
  final NativeApprovalStore store;
  final Set<NativeApprovalType> types;
  @override
  State<NativeApprovalPanel> createState() => _NativeApprovalPanelState();
}

class _NativeApprovalPanelState extends State<NativeApprovalPanel> {
  List<NativeApprovalView> rows = [];
  String? message;
  bool busy = false;
  String tr(String vi, String en, String lo) =>
      switch (AppLocalizations.of(context).locale.languageCode) {
        'vi' => vi,
        'lo' => lo,
        _ => en,
      };
  String reason(String key) => switch (key) {
    'noActivePolicy' => tr(
      'Chưa có chính sách/thẩm quyền hiệu lực',
      'No verified active policy or authority',
      'ບໍ່ມີນະໂຍບາຍ ຫຼື ອຳນາດທີ່ຢືນຢັນ',
    ),
    'independentApprovalRequired' => tr(
      'Cần người duyệt độc lập',
      'Independent reviewer required',
      'ຕ້ອງມີຜູ້ອະນຸມັດແຍກຕ່າງຫາກ',
    ),
    'selfPermissionMissing' => tr(
      'Thiếu quyền tự duyệt riêng',
      'Explicit self-approval permission missing',
      'ຂາດສິດອະນຸມັດຕົນເອງ',
    ),
    'conflictOfInterest' => tr(
      'Người hưởng lợi không được duyệt',
      'Beneficiary cannot approve',
      'ຜູ້ຮັບຜົນປະໂຫຍດອະນຸມັດບໍ່ໄດ້',
    ),
    'periodClosed' => tr('Kỳ đã khóa', 'Period closed', 'ປິດເດືອນແລ້ວ'),
    'selfLimitExceeded' || 'independentLimitExceeded' => tr(
      'Vượt hạn mức theo tiền tệ',
      'Currency approval limit exceeded',
      'ເກີນວົງເງິນສະກຸນນີ້',
    ),
    'relatedDocumentsRequireIndependentReview' => tr(
      'Các chứng từ liên quan cần duyệt độc lập',
      'Related documents require independent review',
      'ເອກະສານທີ່ກ່ຽວຂ້ອງຕ້ອງກວດແຍກ',
    ),
    'insufficientConflictOrLinkEvidence' => tr(
      'Chưa đủ bằng chứng quan hệ/quyền lợi để tự duyệt',
      'Insufficient link/beneficiary evidence for self approval',
      'ຫຼັກຖານຄວາມກ່ຽວຂ້ອງບໍ່ພຽງພໍ',
    ),
    'policyCannotUpgradePendingSelf' => tr(
      'Policy mới không hợp thức hóa chứng từ chờ của chính mình',
      'New policy cannot authorize older own pending documents',
      'ນະໂຍບາຍໃໝ່ບໍ່ຮັບຮອງຮ່າງເກົ່າຂອງຕົນ',
    ),
    'explicitSelfApproval' => tr(
      'Đủ điều kiện tự duyệt rõ ràng',
      'Eligible for explicit self approval',
      'ອະນຸມັດຕົນເອງໄດ້ຕາມເງື່ອນໄຂ',
    ),
    'independentApproval' => tr(
      'Đủ điều kiện duyệt độc lập',
      'Eligible independent reviewer',
      'ຜູ້ອະນຸມັດແຍກທີ່ມີສິດ',
    ),
    _ =>
      tr('Chưa đủ điều kiện', 'Not eligible', 'ຍັງບໍ່ຄົບເງື່ອນໄຂ') + ' ($key)',
  };
  Future<void> load() async {
    if (!widget.store.canView()) {
      if (mounted) setState(() => rows = []);
      return;
    }
    final data = await widget.store.list(widget.types);
    if (mounted) setState(() => rows = widget.store.canView() ? data : []);
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      rows = [];
      message = null;
    });
    try {
      await action();
      await load();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> ask(String title) async {
    final controller = TextEditingController();
    try {
      final route = DialogRoute<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            key: const ValueKey('native-approval-reason'),
            controller: controller,
            decoration: InputDecoration(
              labelText: tr(
                'Lý do bắt buộc',
                'Reason required',
                'ຕ້ອງລະບຸເຫດຜົນ',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(tr('Xác nhận', 'Confirm', 'ຢືນຢັນ')),
            ),
          ],
        ),
      );
      final result = await Navigator.of(context).push(route);
      await route.completed;
      return result;
    } finally {
      controller.dispose();
    }
  }

  Future<void> decide(NativeApprovalView row, bool reject) async {
    final text = await ask(
      reject
          ? tr('Từ chối', 'Reject', 'ປະຕິເສດ')
          : tr('Phê duyệt rõ ràng', 'Explicit approval', 'ຢືນຢັນການອະນຸມັດ'),
    );
    if (text == null) return;
    if (reject) {
      await widget.store.reject(row.ref, text);
    } else {
      final d = await widget.store.approve(row.ref, text);
      if (!d.allowed) throw StateError(reason(d.reason));
    }
  }

  Future<void> history(NativeApprovalView row) async {
    final data = await widget.store.history(row.ref);
    if (!mounted || !widget.store.canView(row)) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tr('Lịch sử phê duyệt', 'Approval history', 'ປະຫວັດການອະນຸມັດ'),
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(data),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Đóng', 'Close', 'ປິດ')),
          ),
        ],
      ),
    );
  }

  List<String> commands(NativeApprovalType type) => switch (type) {
    NativeApprovalType.finance => ['financeReverse'],
    NativeApprovalType.trade => ['tradeSettle', 'tradeReverse', 'tradeVoid'],
    NativeApprovalType.payroll => [
      'payrollPay',
      'payrollRefund',
      'payrollRefundReverse',
      'salaryLink',
      'salaryReverse',
    ],
    NativeApprovalType.machineRun => ['machineVoid'],
    NativeApprovalType.machineExpense => [
      'machineVoid',
      'machinePayable',
      'fuelIssue',
      'fuelReverse',
    ],
    NativeApprovalType.fieldWork => ['fieldVoid'],
    _ => [],
  };
  String operationName(String op) => switch (op) {
    'fuelIssue' => tr(
      'Xuất nhiên liệu nội bộ',
      'Internal fuel issue',
      'ເບີກນ້ຳມັນພາຍໃນ',
    ),
    'fuelReverse' => tr(
      'Hoàn nhiên liệu vào kho',
      'Return fuel to inventory',
      'ຄືນນ້ຳມັນເຂົ້າສາງ',
    ),
    'financeReverse' => tr(
      'Đảo thu/chi',
      'Reverse cash document',
      'ກັບເອກະສານເງິນ',
    ),
    'tradeSettle' => tr(
      'Thanh toán thương mại',
      'Trade settlement',
      'ຊຳລະການຄ້າ',
    ),
    'tradeReverse' => tr('Đảo thanh toán', 'Reverse settlement', 'ກັບການຊຳລະ'),
    'tradeVoid' => tr(
      'Hủy chứng từ thương mại',
      'Void trade document',
      'ຍົກເລີກເອກະສານການຄ້າ',
    ),
    'machineVoid' => tr(
      'Hủy nhật ký máy',
      'Void machine record',
      'ຍົກເລີກບັນທຶກເຄື່ອງຈັກ',
    ),
    'machinePayable' => tr(
      'Ghi nhận phải trả máy',
      'Machine payable',
      'ໜີ້ຄ່າເຄື່ອງຈັກ',
    ),
    'fieldVoid' => tr('Hủy công việc', 'Void field work', 'ຍົກເລີກວຽກ'),
    'payrollPay' => tr('Trả lương', 'Pay salary', 'ຈ່າຍເງິນເດືອນ'),
    'payrollRefund' => tr('Thu hồi lương', 'Recover salary', 'ຮັບຄືນເງິນເດືອນ'),
    'payrollRefundReverse' => tr(
      'Đảo thu hồi lương',
      'Reverse salary recovery',
      'ກັບການຮັບຄືນ',
    ),
    'salaryLink' => tr(
      'Nối sổ tiền lương',
      'Link salary cash',
      'ເຊື່ອມບັນຊີເງິນເດືອນ',
    ),
    'salaryReverse' => tr(
      'Đảo trả lương',
      'Reverse salary payment',
      'ກັບການຈ່າຍເງິນເດືອນ',
    ),
    _ => op,
  };
  Set<String> commandFields(String? op) => {
    'id',
    'day',
    'reason',
    if ({
      'tradeSettle',
      'payrollPay',
      'payrollRefund',
      'payrollRefundReverse',
    }.contains(op))
      'amount',
    if ({'tradeSettle', 'machinePayable'}.contains(op)) 'reference',
    if ({'tradeReverse', 'salaryLink', 'salaryReverse'}.contains(op))
      'paymentId',
    if (op == 'payrollRefundReverse') 'refundId',
    if (op == 'salaryLink') 'financeId',
    if (op == 'machinePayable') 'rounding',
    if (op == 'fuelIssue') ...{'itemId', 'price'},
  };
  Future<void> command(NativeApprovalView row) async {
    final fields = {
      for (final key in [
        'id',
        'day',
        'amount',
        'reference',
        'reason',
        'paymentId',
        'refundId',
        'financeId',
        'rounding',
        'itemId',
        'price',
      ])
        key: TextEditingController(),
    };
    String? operation;
    try {
      final route = DialogRoute<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              tr(
                'Đề xuất thanh toán/hoàn tác',
                'Propose settlement/correction',
                'ສະເໜີຊຳລະ/ແກ້ໄຂ',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    items: [
                      for (final op in commands(row.ref.type))
                        DropdownMenuItem(
                          value: op,
                          child: Text(operationName(op)),
                        ),
                    ],
                    onChanged: (v) => update(() => operation = v),
                    decoration: InputDecoration(
                      labelText: tr(
                        'Nghiệp vụ phải chọn',
                        'Choose operation',
                        'ເລືອກທຸລະກຳ',
                      ),
                    ),
                  ),
                  for (final e in fields.entries.where(
                    (e) => commandFields(operation).contains(e.key),
                  ))
                    if (e.key == 'rounding')
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: tr(
                            'Chính sách làm tròn',
                            'Rounding policy',
                            'ນະໂຍບາຍປັດເສດ',
                          ),
                        ),
                        items: [
                          for (final value in ['halfUp', 'down'])
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) =>
                            fields['rounding']!.text = value ?? '',
                      )
                    else
                      TextField(
                        controller: e.value,
                        decoration: InputDecoration(
                          labelText: switch (e.key) {
                            'id' => tr(
                              'ID thao tác ổn định (dùng lại khi retry)',
                              'Stable operation ID (reuse for retry)',
                              'ID ຄົງທີ່ (ໃຊ້ຊ້ຳເມື່ອລອງໃໝ່)',
                            ),
                            'day' => tr(
                              'Ngày nghiệp vụ YYYY-MM-DD',
                              'Business day YYYY-MM-DD',
                              'ວັນທີ YYYY-MM-DD',
                            ),
                            'amount' => tr(
                              'Tiền exact, nếu có thanh toán',
                              'Exact money for payments',
                              'ເງິນທີ່ແນ່ນອນ',
                            ),
                            'reason' => tr(
                              'Lý do/nội dung',
                              'Reason/note',
                              'ເຫດຜົນ/ເນື້ອໃນ',
                            ),
                            'reference' => tr(
                              'Tham chiếu chứng từ',
                              'Document reference',
                              'ເອກະສານອ້າງອີງ',
                            ),
                            'paymentId' => tr(
                              'ID khoản thanh toán',
                              'Payment ID',
                              'ID ການຈ່າຍ',
                            ),
                            'refundId' => tr(
                              'ID khoản thu hồi',
                              'Recovery ID',
                              'ID ຮັບຄືນ',
                            ),
                            'financeId' => tr(
                              'ID chứng từ tiền đã có (tùy chọn)',
                              'Existing cash document ID (optional)',
                              'ID ເອກະສານເງິນ (ທາງເລືອກ)',
                            ),
                            'itemId' => tr(
                              'ID vật tư nhiên liệu (lít)',
                              'Fuel material ID (litres)',
                              'ID ວັດສະດຸນ້ຳມັນ (ລິດ)',
                            ),
                            'price' => tr(
                              'Đơn giá xuất exact',
                              'Exact issue unit price',
                              'ລາຄາເບີກທີ່ແນ່ນອນ',
                            ),
                            _ => e.key,
                          },
                        ),
                      ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
              ),
              FilledButton(
                onPressed: operation == null
                    ? null
                    : () => Navigator.pop(context, operation),
                child: Text(tr('Lưu pending', 'Save pending', 'ບັນທຶກລໍຖ້າ')),
              ),
            ],
          ),
        ),
      );
      final value = await Navigator.of(context).push(route);
      await route.completed;
      if (value == null || !mounted || !widget.store.canView(row)) return;
      await widget.store.proposeCommand(
        id: fields['id']!.text.trim(),
        operation: value,
        target: row.ref,
        payload: {
          for (final e in fields.entries)
            if (e.key != 'id' &&
                commandFields(value).contains(e.key) &&
                e.value.text.trim().isNotEmpty)
              e.key: e.value.text.trim(),
        },
      );
    } finally {
      for (final field in fields.values) field.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.canView()) return const SizedBox.shrink();
    return ExpansionTile(
      key: const ValueKey('native-approval-panel'),
      title: Text(
        tr('Phê duyệt nghiệp vụ B', 'Business approval B', 'ອະນຸມັດທຸລະກິດ B'),
      ),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView(
            shrinkWrap: true,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => perform(() async {}),
                child: Text(
                  tr(
                    'Tải/làm mới trạng thái',
                    'Load/refresh status',
                    'ໂຫຼດ/ປັບສະຖານະ',
                  ),
                ),
              ),
              if (message != null) SelectableText(message!),
              for (final row in rows.where(widget.store.canView))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          '${row.ref.key} · ${row.request?['state'] ?? row.source.state}',
                        ),
                        SelectableText(
                          '${row.source.total} ${row.source.currency} · ${row.source.creator} → ${row.request?['decided_by'] ?? ''}\n'
                          'revision ${row.source.revision} · policy ${row.source.policyVersion}\n${row.source.digest}\n${row.request?['decided_at'] ?? ''}',
                        ),
                        Text(reason(row.decision.reason)),
                        Wrap(
                          spacing: 6,
                          children: [
                            OutlinedButton(
                              onPressed:
                                  busy ||
                                      row.source.creator !=
                                          widget.store.actorId ||
                                      row.source.state != 'pending' ||
                                      row.source.policyVersion < 1
                                  ? null
                                  : () => perform(
                                      () => widget.store.submit(row.ref),
                                    ),
                              child: Text(
                                tr(
                                  'Gửi/gửi lại',
                                  'Submit/resubmit',
                                  'ສົ່ງ/ສົ່ງຄືນ',
                                ),
                              ),
                            ),
                            FilledButton(
                              onPressed:
                                  busy ||
                                      !row.decision.allowed ||
                                      row.request?['state'] != 'pending'
                                  ? null
                                  : () => perform(() => decide(row, false)),
                              child: Text(
                                row.source.creator == widget.store.actorId
                                    ? tr(
                                        'Tự duyệt',
                                        'Self approve',
                                        'ອະນຸມັດຕົນເອງ',
                                      )
                                    : tr(
                                        'Duyệt độc lập',
                                        'Independent approve',
                                        'ອະນຸມັດແຍກ',
                                      ),
                              ),
                            ),
                            OutlinedButton(
                              onPressed:
                                  busy ||
                                      !row.decision.allowed ||
                                      row.request?['state'] != 'pending' ||
                                      row.source.creator == widget.store.actorId
                                  ? null
                                  : () => perform(() => decide(row, true)),
                              child: Text(tr('Từ chối', 'Reject', 'ປະຕິເສດ')),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => perform(() => history(row)),
                              child: Text(tr('Lịch sử', 'History', 'ປະຫວັດ')),
                            ),
                            if (row.source.state == 'approved' &&
                                commands(row.ref.type).isNotEmpty)
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => perform(() => command(row)),
                                child: Text(
                                  tr(
                                    'Đề xuất thao tác mới',
                                    'Propose operation',
                                    'ສະເໜີທຸລະກຳ',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
