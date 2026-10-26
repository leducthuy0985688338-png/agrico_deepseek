import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import '../application/integration_service.dart';
import '../application/report20.dart';
import '../../trade/domain/trade.dart' show MoneyRounding, TradeMath;

/// Cross-ledger corrections remain explicit; historical sources are never
/// silently copied into cash or inventory when this screen opens.
class IntegrationWorkspaceScreen extends StatefulWidget {
  const IntegrationWorkspaceScreen({super.key, required this.service});
  final IntegrationService service;
  @override
  State<IntegrationWorkspaceScreen> createState() => _IntegrationState();
}

class _IntegrationState extends State<IntegrationWorkspaceScreen> {
  final period = TextEditingController(text: TradeMath.day().substring(0, 7));
  late Future<IntegrationSnapshot> data;
  bool busy = false;
  List<String>? reconciliation;
  String tr(String vi, String en, String lo) =>
      switch (AppLocalizations.of(context).locale.languageCode) {
        'vi' => vi,
        'lo' => lo,
        _ => en,
      };
  @override
  void initState() {
    super.initState();
    data = load();
  }

  @override
  void dispose() {
    period.dispose();
    super.dispose();
  }

  Future<IntegrationSnapshot> load() async {
    if (!widget.service.canView) {
      return IntegrationSnapshot(
        farm: widget.service.subject.farmId,
        period: period.text.trim(),
        tables: const {},
      );
    }
    return widget.service.snapshot(period.text.trim());
  }

  void reload() {
    setState(() => data = load());
  }

  Future<void> run(Future<void> Function() operation) async {
    if (!mounted || busy) return;
    setState(() => busy = true);
    try {
      await operation();
      if (mounted) {
        reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Đã hoàn tất', 'Completed', 'ສຳເລັດ'))),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Chưa thực hiện: kiểm tra quyền, nguồn, số tiền, ngày và trạng thái liên kết.',
                'Not applied: check permissions, source, amount, date and link status.',
                'ບໍ່ສຳເລັດ: ກວດສິດ, ແຫຼ່ງຂໍ້ມູນ, ຈຳນວນ, ວັນທີ ແລະ ສະຖານະ.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, String>?> form(
    String title,
    Map<String, String> labels, {
    Map<String, String> initial = const {},
    Set<String> optional = const {},
    Map<String, Map<String, String>> choices = const {},
  }) async {
    final controllers = {
      for (final k in labels.keys)
        k: TextEditingController(text: initial[k] ?? ''),
    };
    final key = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: choices.containsKey(e.key)
                        ? DropdownButtonFormField<String>(
                            initialValue: controllers[e.key]!.text.isEmpty
                                ? null
                                : controllers[e.key]!.text,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: e.value),
                            items: [
                              if (optional.contains(e.key))
                                DropdownMenuItem(
                                  value: '',
                                  child: Text(
                                    tr('Tạo mới', 'Create new', 'ສ້າງໃໝ່'),
                                  ),
                                ),
                              for (final option in choices[e.key]!.entries)
                                DropdownMenuItem(
                                  value: option.key,
                                  child: Text(
                                    option.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                controllers[e.key]!.text = v ?? '',
                            validator: (v) =>
                                !optional.contains(e.key) && (v ?? '').isEmpty
                                ? tr('Bắt buộc', 'Required', 'ຈຳເປັນ')
                                : null,
                          )
                        : TextFormField(
                            controller: controllers[e.key],
                            decoration: InputDecoration(labelText: e.value),
                            validator: (v) =>
                                !optional.contains(e.key) &&
                                    (v ?? '').trim().isEmpty
                                ? tr('Bắt buộc', 'Required', 'ຈຳເປັນ')
                                : null,
                          ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Hủy', 'Cancel', 'ຍົກເລີກ')),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate())
                Navigator.pop(ctx, {
                  for (final e in controllers.entries)
                    e.key: e.value.text.trim(),
                });
            },
            child: Text(tr('Xác nhận', 'Confirm', 'ຢືນຢັນ')),
          ),
        ],
      ),
    );
    // Defer disposal until dialog route animations have released its fields.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (final c in controllers.values) c.dispose();
    return result;
  }

  String id() =>
      'integration-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
  Future<void> salary(
    IntegrationSnapshot s,
    Map<String, Object?> p,
    bool linked,
  ) async {
    final reversalId = id();
    final title = tr(
      'Trả lương → sổ tiền',
      'Payroll → cash',
      'ເງິນເດືອນ → ບັນຊີເງິນ',
    );
    final values = await form(
      title,
      linked
          ? {
              'day': tr(
                'Ngày hoàn tiền YYYY-MM-DD',
                'Refund date YYYY-MM-DD',
                'ວັນທີຄືນເງິນ YYYY-MM-DD',
              ),
              'reason': tr(
                'Lý do đảo khoản trả',
                'Reversal reason',
                'ເຫດຜົນກັບລາຍການ',
              ),
            }
          : {
              'cash': tr(
                'Phiếu chi đã có (để trống để tạo mới)',
                'Existing cash payment (blank = create)',
                'ໃບຈ່າຍເດີມ (ວ່າງ = ສ້າງໃໝ່)',
              ),
            },
      initial: linked ? {'day': TradeMath.day()} : const {},
      optional: const {'cash'},
      choices: linked
          ? const {}
          : {
              'cash': {
                for (final cash
                    in s
                        .rows('finance_documents_v2')
                        .where(
                          (cash) =>
                              cash['kind'] == 'CHI' &&
                              cash['currency'] == p['currency'] &&
                              IntegrationSnapshot.cashAmount(cash) ==
                                  p['amount'] &&
                              (cash['occurred_at'] as String).substring(
                                    0,
                                    10,
                                  ) ==
                                  p['business_day'],
                        ))
                  cash['id'] as String:
                      '${cash['code']} · ${IntegrationSnapshot.cashAmount(cash)} ${cash['currency']}',
              },
            },
    );
    if (values == null) return;
    await run(
      () => linked
          ? widget.service.reverseSalary(
              p['id'] as String,
              reversalId,
              values['day']!,
              values['reason']!,
            )
          : widget.service.linkSalary(
              p['id'] as String,
              cashId: values['cash']!.isEmpty ? null : values['cash'],
            ),
    );
  }

  Future<void> machine(
    IntegrationSnapshot s,
    Map<String, Object?> r,
    String action,
  ) async {
    if (action == 'reverse') {
      final v = await form(
        tr(
          'Hoàn nhiên liệu vào kho',
          'Return fuel to inventory',
          'ຄືນນ້ຳມັນເຂົ້າສາງ',
        ),
        {
          'day': tr('Ngày YYYY-MM-DD', 'Date YYYY-MM-DD', 'ວັນທີ YYYY-MM-DD'),
          'reason': tr('Lý do', 'Reason', 'ເຫດຜົນ'),
        },
        initial: {'day': TradeMath.day()},
      );
      if (v != null)
        await run(
          () => widget.service.reverseFuel(
            r['id'] as String,
            v['day']!,
            v['reason']!,
          ),
        );
      return;
    }
    final fuel = action == 'fuel';
    final v = await form(
      fuel
          ? tr(
              'Xuất nhiên liệu nội bộ',
              'Internal fuel issue',
              'ເບີກນ້ຳມັນພາຍໃນ',
            )
          : tr(
              'Chi phí máy → phải trả',
              'Machine expense → payable',
              'ຄ່າເຄື່ອງຈັກ → ໜີ້ຕ້ອງຈ່າຍ',
            ),
      fuel
          ? {
              'item': tr(
                'Vật tư nhiên liệu (đơn vị lít)',
                'Fuel material (litres)',
                'ວັດສະດຸນ້ຳມັນ (ລິດ)',
              ),
              'price': tr(
                'Đơn giá xuất Admin (> 0)',
                'Admin issue price (> 0)',
                'ລາຄາເບີກໂດຍ Admin (> 0)',
              ),
              'existing': tr(
                'Phiếu xuất đã có (tùy chọn)',
                'Existing issue (optional)',
                'ໃບເບີກເດີມ (ທາງເລືອກ)',
              ),
            }
          : {
              'supplier': tr('Nhà cung cấp', 'Supplier', 'ຜູ້ສະໜອງ'),
              'reference': tr(
                'Tham chiếu hóa đơn',
                'Invoice reference',
                'ເລກອ້າງອີງໃບແຈ້ງໜີ້',
              ),
              'rounding': tr(
                'Quy tắc làm tròn',
                'Rounding policy',
                'ປັດເສດ: halfUp ຫຼື down',
              ),
              'existing': tr(
                'Chứng từ CP đã có (tùy chọn)',
                'Existing expense document (optional)',
                'ເອກະສານຄ່າໃຊ້ຈ່າຍເດີມ (ທາງເລືອກ)',
              ),
            },
      initial: fuel ? const {} : const {'rounding': 'halfUp'},
      optional: const {'existing'},
      choices: fuel
          ? {
              'item': {
                for (final item
                    in s
                        .rows('inventory_items_v2')
                        .where(
                          (item) =>
                              {
                                'l',
                                'lít',
                                'liter',
                                'litre',
                                'litres',
                                'liters',
                                'ລິດ',
                              }.contains(
                                (item['unit'] as String).toLowerCase().trim(),
                              ),
                        ))
                  item['id'] as String:
                      '${item['code']} · ${item['name']} (${item['unit']})',
              },
              'existing': {
                for (final movement
                    in s
                        .rows('inventory_movements_v2')
                        .where(
                          (m) => m['kind'] == 'issue' && m['plan_id'] == null,
                        ))
                  movement['id'] as String:
                      '${movement['code']} · ${s.name(movement['item_id'])} · ${movement['amount_text']} ${movement['currency']}',
              },
            }
          : {
              'supplier': {
                for (final supplier
                    in s
                        .rows('company_catalog_entries_v1')
                        .where(
                          (r) => r['kind'] == 'supplier' && r['active'] == 1,
                        ))
                  supplier['id'] as String:
                      '${supplier['code']} · ${supplier['name']}',
              },
              'rounding': {
                'halfUp': tr(
                  'Làm tròn gần nhất',
                  'Round half up',
                  'ປັດເສດໃກ້ສຸດ',
                ),
                'down': tr('Bỏ phần lẻ', 'Round down', 'ຕັດສ່ວນເສດ'),
              },
              'existing': {
                for (final doc
                    in s
                        .rows('trade_documents_v1')
                        .where(
                          (d) =>
                              d['kind'] == 'expense' && d['status'] == 'posted',
                        ))
                  doc['id'] as String:
                      '${doc['code']} · ${s.name(doc['party_id'])} · ${doc['total']} ${doc['currency']}',
              },
            },
    );
    if (v == null) return;
    await run(() async {
      if (fuel) {
        await widget.service.fuelIssue(
          r['id'] as String,
          v['item']!,
          v['price']!,
          false,
          movement: v['existing']!.isEmpty ? null : v['existing'],
        );
      } else {
        if (!{'halfUp', 'down'}.contains(v['rounding']))
          throw const FormatException();
        await widget.service.machinePayable(
          r['id'] as String,
          v['supplier']!,
          v['reference']!,
          v['rounding'] == 'down' ? MoneyRounding.down : MoneyRounding.halfUp,
          document: v['existing']!.isEmpty ? null : v['existing'],
        );
      }
    });
  }

  static const fields = {
    'parcel': {
      'soilType': ['Loại đất', 'Soil type', 'ຊະນິດດິນ'],
      'pH': ['pH', 'pH', 'pH'],
      'preparedOn': [
        'Ngày làm đất YYYY-MM-DD',
        'Preparation date YYYY-MM-DD',
        'ວັນກຽມດິນ YYYY-MM-DD',
      ],
      'evaluation': ['Nhận xét', 'Assessment', 'ຄຳເຫັນ'],
    },
    'harvest': {
      'freshKg': ['Khối lượng tươi kg', 'Fresh weight kg', 'ນ້ຳໜັກສົດ kg'],
      'dryKg': ['Khối lượng khô kg', 'Dry weight kg', 'ນ້ຳໜັກແຫ້ງ kg'],
      'quality': ['Chất lượng', 'Quality', 'ຄຸນນະພາບ'],
    },
    'machine': {
      'type': ['Loại máy', 'Machine type', 'ປະເພດເຄື່ອງຈັກ'],
      'manufacturer': ['Nhà sản xuất', 'Manufacturer', 'ຜູ້ຜະລິດ'],
      'year': ['Năm sản xuất', 'Manufacturing year', 'ປີຜະລິດ'],
      'purchasedOn': [
        'Ngày nhập YYYY-MM-DD',
        'Purchase date YYYY-MM-DD',
        'ວັນຊື້ YYYY-MM-DD',
      ],
      'warrantyUntil': [
        'Hết bảo hành YYYY-MM-DD',
        'Warranty end YYYY-MM-DD',
        'ໝົດປະກັນ YYYY-MM-DD',
      ],
    },
    'maintenance': {
      'parts': ['Phụ tùng', 'Parts', 'ອາໄຫຼ່'],
      'quantity': ['Số lượng', 'Quantity', 'ຈຳນວນ'],
      'unitPrice': ['Đơn giá', 'Unit price', 'ລາຄາຕໍ່ໜ່ວຍ'],
      'performer': ['Người thực hiện', 'Performed by', 'ຜູ້ດຳເນີນ'],
    },
    'worker': {
      'title': ['Chức danh', 'Title', 'ຕຳແໜ່ງ'],
    },
    'payroll': {
      'insurance': [
        'Bảo hiểm trong khoản khấu trừ đã ghi',
        'Insurance within recorded deductions',
        'ປະກັນໃນຍອດຫັກທີ່ບັນທຶກແລ້ວ',
      ],
    },
  };
  Future<void> metadata(
    IntegrationSnapshot s,
    String kind,
    Map<String, Object?> entity,
  ) async {
    final old = s.metadata(kind, entity['id']);
    final row = s
        .rows('integration_report_metadata_v1')
        .where((r) => r['kind'] == kind && r['entity_id'] == entity['id'])
        .firstOrNull;
    final labels = {
      for (final e in fields[kind]!.entries)
        e.key: tr(e.value[0], e.value[1], e.value[2]),
    };
    final v = await form(
      tr('Thông tin báo cáo', 'Report details', 'ຂໍ້ມູນລາຍງານ'),
      labels,
      initial: {for (final e in old.entries) e.key: '${e.value}'},
      optional: labels.keys.toSet(),
    );
    if (v != null)
      await run(
        () => widget.service.metadata(
          kind,
          entity['id'] as String,
          (row?['revision'] as int?) ?? 0,
          v,
        ),
      );
  }

  Widget button(String text, VoidCallback onPressed) =>
      TextButton(onPressed: busy ? null : onPressed, child: Text(text));
  @override
  Widget build(BuildContext context) {
    if (!widget.service.canView)
      return Scaffold(
        body: Center(
          child: Text(
            tr('Không có quyền xem', 'Access denied', 'ບໍ່ມີສິດເບິ່ງ'),
          ),
        ),
      );
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            tr(
              'Báo cáo và đối soát',
              'Reports and reconciliation',
              'ລາຍງານ ແລະ ກວດບັນຊີ',
            ),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: tr('Tổng hợp', 'Overview', 'ພາບລວມ')),
              Tab(
                text: tr(
                  'Lương / sổ tiền',
                  'Payroll / cash',
                  'ເງິນເດືອນ / ເງິນ',
                ),
              ),
              Tab(
                text: tr(
                  'Máy / kho / nợ',
                  'Machines / stock / debt',
                  'ເຄື່ອງຈັກ / ສາງ / ໜີ້',
                ),
              ),
              Tab(
                text: tr('Thông tin báo cáo', 'Report details', 'ຂໍ້ມູນລາຍງານ'),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: period,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Kỳ YYYY-MM',
                          'Period YYYY-MM',
                          'ເດືອນ YYYY-MM',
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: busy ? null : reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: FutureBuilder<IntegrationSnapshot>(
                future: data,
                builder: (ctx, result) {
                  if (result.hasError)
                    return Center(
                      child: Text(
                        tr(
                          'Không tải được. Kiểm tra kỳ và quyền truy cập.',
                          'Unable to load. Check period and access.',
                          'ໂຫຼດບໍ່ໄດ້. ກວດເດືອນ ແລະ ສິດ.',
                        ),
                      ),
                    );
                  if (!result.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final s = result.data!;
                  final linked = s
                      .rows('integration_cash_links_v1')
                      .map((r) => r['source_id'])
                      .toSet();
                  final reversed = s.salaryReversed;
                  return TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Text(
                            tr(
                              'Giữ riêng VND và LAK. Giá ca máy trọn gói; chi tiền không cộng lại vào chi phí sản xuất.',
                              'VND and LAK stay separate. Machine prices include all costs; cash payments do not add production costs.',
                              'ແຍກ VND ແລະ LAK. ລາຄາເຄື່ອງຈັກລວມທຸກຄ່າ; ການຈ່າຍເງິນບໍ່ເພີ່ມຕົ້ນທຶນຜະລິດ.',
                            ),
                          ),
                          button(
                            tr(
                              'Kiểm tra đối soát',
                              'Reconcile ledgers',
                              'ກວດທຽບບັນຊີ',
                            ),
                            () => run(() async {
                              final issues = await widget.service.reconcile();
                              if (mounted)
                                setState(() => reconciliation = issues);
                            }),
                          ),
                          if (reconciliation != null)
                            ListTile(
                              leading: Icon(
                                reconciliation!.isEmpty
                                    ? Icons.check_circle
                                    : Icons.error_outline,
                              ),
                              title: Text(
                                reconciliation!.isEmpty
                                    ? tr(
                                        'Các sổ khớp nhau',
                                        'Ledgers reconcile',
                                        'ບັນຊີກົງກັນ',
                                      )
                                    : reconciliation!.join('\n'),
                              ),
                            ),
                          if (widget.service.can(PermissionCodes.dataExport))
                            button(
                              tr(
                                'Xuất Excel đủ 20 trang',
                                'Export 20-sheet Excel',
                                'ສົ່ງອອກ Excel 20 ໜ້າ',
                              ),
                              () => run(() async {
                                widget.service.exportAccess();
                                final fresh = await widget.service.snapshot(
                                  period.text.trim(),
                                );
                                final bytes = Report20(fresh).bytes();
                                widget.service.exportAccess();
                                await saveExcelBytes(
                                  bytes,
                                  'AGRICO-20-${fresh.period}.xlsx',
                                );
                              }),
                            ),
                          for (final warning in s.warnings)
                            ListTile(
                              leading: const Icon(Icons.warning_amber),
                              title: Text(warning),
                            ),
                        ],
                      ),
                      ListView(
                        children: [
                          for (final p in s.rows('personnel_payments_v1'))
                            ListTile(
                              title: Text(
                                '${p['id']} · ${p['amount']} ${p['currency']}',
                              ),
                              subtitle: Text(
                                '${p['business_day']} · ${p['id']}',
                              ),
                              trailing: reversed.contains(p['id'])
                                  ? Text(
                                      tr('Đã đảo', 'Reversed', 'ກັບລາຍການແລ້ວ'),
                                    )
                                  : button(
                                      linked.contains(p['id'])
                                          ? tr(
                                              'Đảo trả lương',
                                              'Reverse payment',
                                              'ກັບລາຍການຈ່າຍ',
                                            )
                                          : tr(
                                              'Nối sổ tiền',
                                              'Link cash',
                                              'ເຊື່ອມບັນຊີເງິນ',
                                            ),
                                      () => salary(
                                        s,
                                        p,
                                        linked.contains(p['id']),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                      ListView(
                        children: [
                          for (final r
                              in s
                                  .rows('machine_expenses_v1')
                                  .where((r) => r['status'] == 'approved'))
                            Builder(
                              builder: (ctx) {
                                final ap = s
                                    .rows('integration_machine_links_v1')
                                    .where((l) => l['expense_id'] == r['id'])
                                    .firstOrNull;
                                final fuel = s
                                    .rows('integration_fuel_issues_v1')
                                    .where((l) => l['expense_id'] == r['id'])
                                    .firstOrNull;
                                return ListTile(
                                  title: Text(
                                    '${s.name(r['machine_id'])} · ${r['day']} · ${r['kind']}',
                                  ),
                                  subtitle: Text('${r['id']}'),
                                  trailing: ap != null
                                      ? Text(
                                          tr(
                                            'Đã nối phải trả',
                                            'Payable linked',
                                            'ເຊື່ອມໜີ້ແລ້ວ',
                                          ),
                                        )
                                      : fuel != null
                                      ? (fuel['reversal_movement_id'] != null
                                            ? Text(
                                                tr(
                                                  'Đã hoàn kho',
                                                  'Returned',
                                                  'ຄືນແລ້ວ',
                                                ),
                                              )
                                            : button(
                                                tr(
                                                  'Hoàn kho',
                                                  'Return fuel',
                                                  'ຄືນສາງ',
                                                ),
                                                () => machine(s, r, 'reverse'),
                                              ))
                                      : PopupMenuButton<String>(
                                          enabled: !busy,
                                          onSelected: (v) => machine(s, r, v),
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'ap',
                                              child: Text(
                                                tr(
                                                  'Nối phải trả',
                                                  'Link payable',
                                                  'ເຊື່ອມໜີ້',
                                                ),
                                              ),
                                            ),
                                            if (r['kind'] == 'fuel')
                                              PopupMenuItem(
                                                value: 'fuel',
                                                child: Text(
                                                  tr(
                                                    'Xuất nhiên liệu nội bộ',
                                                    'Internal fuel issue',
                                                    'ເບີກນ້ຳມັນພາຍໃນ',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                );
                              },
                            ),
                        ],
                      ),
                      ListView(
                        children: [
                          for (final kind in fields.keys)
                            ExpansionTile(
                              title: Text(
                                tr(
                                  {
                                    'parcel': 'Thửa',
                                    'harvest': 'Thu hoạch',
                                    'machine': 'Máy',
                                    'maintenance': 'Bảo trì',
                                    'worker': 'Nhân viên',
                                    'payroll': 'Bảng lương',
                                  }[kind]!,
                                  {
                                    'parcel': 'Parcels',
                                    'harvest': 'Harvest',
                                    'machine': 'Machines',
                                    'maintenance': 'Maintenance',
                                    'worker': 'Workers',
                                    'payroll': 'Payroll',
                                  }[kind]!,
                                  {
                                    'parcel': 'ຕອນດິນ',
                                    'harvest': 'ເກັບກ່ຽວ',
                                    'machine': 'ເຄື່ອງຈັກ',
                                    'maintenance': 'ບຳລຸງ',
                                    'worker': 'ພະນັກງານ',
                                    'payroll': 'ບັນຊີເງິນເດືອນ',
                                  }[kind]!,
                                ),
                              ),
                              children: [
                                for (final entity
                                    in s
                                        .rows(
                                          {
                                            'parcel': 'land_parcels',
                                            'harvest': 'trade_documents_v1',
                                            'machine':
                                                'company_catalog_entries_v1',
                                            'maintenance':
                                                'machine_expenses_v1',
                                            'worker':
                                                'company_catalog_entries_v1',
                                            'payroll': 'personnel_payrolls_v1',
                                          }[kind]!,
                                        )
                                        .where(
                                          (r) =>
                                              kind == 'worker' ||
                                                  kind == 'machine'
                                              ? r['kind'] == kind
                                              : kind == 'harvest' ||
                                                    kind == 'maintenance'
                                              ? r['kind'] == kind
                                              : true,
                                        ))
                                  ListTile(
                                    title: Text(
                                      '${entity['code'] ?? entity['parcel_code'] ?? entity['id']} ${entity['name'] ?? ''}',
                                    ),
                                    onTap: busy
                                        ? null
                                        : () => metadata(s, kind, entity),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
