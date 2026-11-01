import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/approval/approval_administration.dart';
import '../../../core/approval/approval_policy.dart';
import '../../../core/localization/app_localizations.dart';

/// Policy administration belongs to the existing integrated workspace.
/// No authority or business limits are provisioned by this widget.
class ApprovalPolicyPanel extends StatefulWidget {
  const ApprovalPolicyPanel({
    super.key,
    required this.store,
    required this.can,
    required this.farm,
    required this.actor,
  });
  final ApprovalAdministration store;
  final bool Function(String permission) can;
  final String farm, actor;
  @override
  State<ApprovalPolicyPanel> createState() => _ApprovalPolicyPanelState();
}

class _ApprovalPolicyPanelState extends State<ApprovalPolicyPanel> {
  List<Map<String, Object?>> rows = [];
  String? message;
  bool busy = false;
  int epoch = 0;
  Route<dynamic>? policyDialog;
  int accessStamp = 0;
  int get accessBits {
    var result = 0;
    const permissions = [
      ApprovalRules.policyManage,
      ApprovalRules.limitManage,
      ApprovalRules.policyActivate,
      ApprovalRules.auditView,
    ];
    for (var i = 0; i < permissions.length; i++) {
      if (widget.can(permissions[i])) result |= 1 << i;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    accessStamp = accessBits;
  }

  ApprovalKind remoteKind = ApprovalKind.machineRun;
  String remoteCurrency = 'VND';
  bool get readable =>
      widget.can(ApprovalRules.policyManage) ||
      widget.can(ApprovalRules.policyActivate);
  @override
  void didUpdateWidget(covariant ApprovalPolicyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = accessBits, revoked = (accessStamp & ~next) != 0;
    accessStamp = next;
    if (oldWidget.actor != widget.actor ||
        oldWidget.farm != widget.farm ||
        oldWidget.store != widget.store ||
        revoked) {
      epoch++;
      final route = policyDialog;
      policyDialog = null;
      if (route != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && route.isActive) {
            Navigator.of(context).removeRoute(route);
          }
        });
      }
      rows = [];
      message = null;
      busy = false;
    }
  }

  String tr(String vi, String en, String lo) =>
      switch (AppLocalizations.of(context).locale.languageCode) {
        'vi' => vi,
        'lo' => lo,
        _ => en,
      };
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    final opened = epoch;
    setState(() => busy = true);
    try {
      await action();
      if (mounted && opened == epoch) setState(() => message = null);
    } catch (e) {
      if (mounted && opened == epoch) {
        setState(() {
          rows = [];
          message = e.toString();
        });
      }
    } finally {
      if (mounted && opened == epoch) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    final opened = epoch;
    final result = await widget.store.list();
    if (mounted && opened == epoch && readable) setState(() => rows = result);
  }

  Future<void> propose() async {
    final opened = epoch;
    final selfLimit = TextEditingController(),
        independent = TextEditingController(),
        reason = TextEditingController();
    ApprovalKind? kind;
    String? currency;
    bool self = false;
    try {
      final route =
          DialogRoute<(ApprovalKind, String, bool, String, String, String)>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: Text(
                  tr(
                    'Đề xuất chính sách (draft)',
                    'Propose policy (draft)',
                    'ສະເໜີນະໂຍບາຍ (ຮ່າງ)',
                  ),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<ApprovalKind>(
                        key: const ValueKey('approval-kind'),
                        initialValue: kind,
                        items: [
                          for (final k in ApprovalKind.values)
                            DropdownMenuItem(value: k, child: Text(k.name)),
                        ],
                        decoration: InputDecoration(
                          labelText: tr(
                            'Loại chứng từ',
                            'Document type',
                            'ປະເພດເອກະສານ',
                          ),
                        ),
                        onChanged: (v) => update(() {
                          kind = v;
                          self = false;
                        }),
                      ),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('approval-currency'),
                        initialValue: currency,
                        items: [
                          for (final c in ['VND', 'LAK'])
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        decoration: InputDecoration(
                          labelText: tr(
                            'Tiền tệ riêng biệt',
                            'Separate currency',
                            'ສະກຸນເງິນແຍກກັນ',
                          ),
                        ),
                        onChanged: (v) => update(() => currency = v),
                      ),
                      SwitchListTile(
                        value: self,
                        title: Text(
                          tr(
                            'Cho phép đề xuất tự duyệt',
                            'Allow conditional self approval',
                            'ອະນຸຍາດອະນຸມັດຕົນເອງຕາມເງື່ອນໄຂ',
                          ),
                        ),
                        onChanged:
                            DocumentApprovalPolicy.selfKinds.contains(kind)
                            ? (v) => update(() => self = v)
                            : null,
                      ),
                      TextField(
                        controller: selfLimit,
                        decoration: InputDecoration(
                          labelText: tr(
                            'Hạn mức tự duyệt (tiền exact)',
                            'Self limit (exact money)',
                            'ວົງເງິນອະນຸມັດຕົນເອງ',
                          ),
                        ),
                      ),
                      TextField(
                        controller: independent,
                        decoration: InputDecoration(
                          labelText: tr(
                            'Hạn mức duyệt độc lập (tiền exact)',
                            'Independent limit (exact money)',
                            'ວົງເງິນອະນຸມັດແຍກຕ່າງຫາກ',
                          ),
                        ),
                      ),
                      TextField(
                        controller: reason,
                        decoration: InputDecoration(
                          labelText: tr(
                            'Lý do thay đổi',
                            'Change reason',
                            'ເຫດຜົນການປ່ຽນແປງ',
                          ),
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
                    onPressed: kind == null || currency == null
                        ? null
                        : () => Navigator.pop(context, (
                            kind!,
                            currency!,
                            self,
                            selfLimit.text.trim(),
                            independent.text.trim(),
                            reason.text.trim(),
                          )),
                    child: Text(tr('Lưu draft', 'Save draft', 'ບັນທຶກຮ່າງ')),
                  ),
                ],
              ),
            ),
          );
      policyDialog = route;
      final values = await Navigator.of(context).push(route);
      await route.completed;
      if (identical(policyDialog, route)) policyDialog = null;
      if (values == null || !mounted || opened != epoch) return;
      await load();
      final versions = rows
          .where(
            (r) => r['kind'] == values.$1.name && r['currency'] == values.$2,
          )
          .map((r) => r['version'] as int);
      final version = versions.fold<int>(0, (a, b) => a > b ? a : b) + 1;
      await widget.store.propose(
        DocumentApprovalPolicy(
          farm: widget.farm,
          kind: values.$1,
          currency: values.$2,
          version: version,
          selfEnabled: values.$3,
          selfLimit: values.$4.isEmpty ? null : values.$4,
          independentLimit: values.$5.isEmpty ? null : values.$5,
          createPermission: ApprovalRules.nativeCreatePermission(values.$1),
          approvePermission: ApprovalRules.nativeApprovePermission(values.$1),
          changedBy: widget.actor,
        ),
        values.$6,
      );
      await load();
    } finally {
      selfLimit.dispose();
      independent.dispose();
      reason.dispose();
    }
  }

  Future<void> requestActivation(Map<String, Object?> row) async {
    final opened = epoch;
    final reason = TextEditingController();
    try {
      final route = DialogRoute<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            tr(
              'Kích hoạt độc lập',
              'Independent activation',
              'ເປີດໃຊ້ໂດຍຜູ້ອື່ນ',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(
                  'Cần nguồn thẩm quyền đã provision. Quyền admin không thay thế điều kiện này.',
                  'A provisioned trusted authority is required. Technical admin is insufficient.',
                  'ຕ້ອງມີແຫຼ່ງອຳນາດທີ່ກຳນົດ. ສິດ admin ບໍ່ພຽງພໍ.',
                ),
              ),
              TextField(
                controller: reason,
                decoration: InputDecoration(
                  labelText: tr(
                    'Lý do kích hoạt',
                    'Activation reason',
                    'ເຫດຜົນເປີດໃຊ້',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, reason.text.trim()),
              child: Text(
                tr('Yêu cầu kích hoạt', 'Request activation', 'ຂໍເປີດໃຊ້'),
              ),
            ),
          ],
        ),
      );
      policyDialog = route;
      final value = await Navigator.of(context).push(route);
      await route.completed;
      if (identical(policyDialog, route)) policyDialog = null;
      if (value == null || !mounted || opened != epoch) return;
      final current = rows.where(
        (r) =>
            r['state'] == 'active' &&
            r['kind'] == row['kind'] &&
            r['currency'] == row['currency'],
      );
      await widget.store.activate(
        ApprovalKind.values.byName(row['kind'] as String),
        row['currency'] as String,
        row['version'] as int,
        current.isEmpty ? 0 : current.single['version'] as int,
        value,
      );
      await load();
    } finally {
      reason.dispose();
    }
  }

  Future<void> history() async {
    final opened = epoch;
    final data = await widget.store.policyHistory();
    if (!mounted || opened != epoch || !widget.can(ApprovalRules.auditView)) {
      return;
    }
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Lịch sử chính sách', 'Policy audit', 'ປະຫວັດນະໂຍບາຍ')),
        content: SizedBox(
          width: 640,
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
    policyDialog = route;
    await Navigator.of(context).push(route);
    await route.completed;
    if (identical(policyDialog, route)) policyDialog = null;
  }

  @override
  Widget build(BuildContext context) {
    final manage = widget.can(ApprovalRules.policyManage);
    final audit = widget.can(ApprovalRules.auditView);
    final read = manage || widget.can(ApprovalRules.policyActivate);
    if (!read && !audit) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text(
        tr('Chính sách phê duyệt', 'Approval policy', 'ນະໂຍບາຍອະນຸມັດ'),
      ),
      children: [
        Text(
          tr(
            'Policy chỉ có hiệu lực khi thẩm quyền server được xác minh; thiếu cấu hình thì nghiệp vụ duyệt bị chặn.',
            'A policy is effective only with verified server authority; missing configuration blocks business approval.',
            'ນະໂຍບາຍຕ້ອງຢືນຢັນອຳນາດຈາກ server; ຖ້າຂາດການຕັ້ງຄ່າຈະອະນຸມັດບໍ່ໄດ້.',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            if (read && widget.store is RemoteApprovalAdministration) ...[
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<ApprovalKind>(
                  isExpanded: true,
                  initialValue: remoteKind,
                  items: [
                    for (final k in ApprovalKind.values)
                      DropdownMenuItem(value: k, child: Text(k.name)),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => remoteKind = v!),
                ),
              ),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: remoteCurrency,
                  items: [
                    for (final c in ['VND', 'LAK'])
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => remoteCurrency = v!),
                ),
              ),
              OutlinedButton(
                key: const ValueKey('sync-remote-policy'),
                onPressed: busy
                    ? null
                    : () => perform(() async {
                        await (widget.store as RemoteApprovalAdministration)
                            .syncPolicy(remoteKind, remoteCurrency);
                        await load();
                      }),
                child: Text(
                  tr(
                    'Đồng bộ policy server',
                    'Sync server policy',
                    'ຊິງນະໂຍບາຍເຊີບເວີ',
                  ),
                ),
              ),
            ],
            if (read)
              OutlinedButton(
                onPressed: busy ? null : () => perform(load),
                child: Text(tr('Tải cấu hình', 'Load policies', 'ໂຫຼດນະໂຍບາຍ')),
              ),
            if (manage && widget.can(ApprovalRules.limitManage))
              OutlinedButton(
                onPressed: busy ? null : () => perform(propose),
                child: Text(tr('Đề xuất draft', 'Propose draft', 'ສະເໜີຮ່າງ')),
              ),
            if (audit)
              OutlinedButton(
                onPressed: busy ? null : () => perform(history),
                child: Text(tr('Xem audit', 'View audit', 'ເບິ່ງປະຫວັດ')),
              ),
          ],
        ),
        if (message != null) SelectableText(message!),
        if (read)
          for (final row in rows)
            ListTile(
              title: Text(
                '${row['kind']} · ${row['currency']} · v${row['version']} · ${row['state']}',
              ),
              subtitle: SelectableText(
                '${row['changed_by']} · ${row['changed_at']}\n${row['payload']}',
              ),
              leading:
                  manage &&
                      widget.can(ApprovalRules.limitManage) &&
                      row['state'] == 'draft' &&
                      row['changed_by'] == widget.actor
                  ? IconButton(
                      tooltip: tr(
                        'Gửi draft bằng danh tính người đề xuất',
                        'Publish draft as authenticated author',
                        'ສົ່ງຮ່າງດ້ວຍຕົວຕົນຜູ້ສະເໜີ',
                      ),
                      onPressed: busy
                          ? null
                          : () => perform(
                              () => widget.store.publishDraft(
                                ApprovalKind.values.byName(
                                  row['kind'] as String,
                                ),
                                row['currency'] as String,
                                row['version'] as int,
                              ),
                            ),
                      icon: const Icon(Icons.upload_outlined),
                    )
                  : null,
              trailing:
                  row['state'] == 'draft' &&
                      widget.can(ApprovalRules.policyActivate)
                  ? OutlinedButton(
                      onPressed: busy || row['changed_by'] == widget.actor
                          ? null
                          : () => perform(() => requestActivation(row)),
                      child: Text(tr('Kích hoạt', 'Activate', 'ເປີດໃຊ້')),
                    )
                  : null,
            ),
      ],
    );
  }
}
