import '../application/period_close_service.dart';
import 'period_close_panel.dart';
import 'approval_policy_panel.dart';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import '../application/integration_service.dart';
import '../application/report20.dart';
import 'production_cost_panel.dart';
import '../application/production_cost_workflow_service.dart';
import '../domain/production_cost_workflow.dart';
import '../../trade/domain/trade.dart' show MoneyRounding, TradeMath;

/// Cross-ledger corrections remain explicit; historical sources are never
/// silently copied into cash or inventory when this screen opens.
class IntegrationWorkspaceScreen extends StatefulWidget {
  const IntegrationWorkspaceScreen({
    super.key,
    required this.service,
    this.periodClosing,
    this.controlledApprovals = false,
  });
  final IntegrationService service;
  final bool controlledApprovals;
  final PeriodCloseService? periodClosing;
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

  Future<void> costWorkflow(String action) async {
    final store = widget.service.productionCosts;
    if (store == null) return;
    final workflow = ProductionCostWorkflowService(store, widget.service);
    final proposal = action == 'propose';
    final values = await form(
      action == 'material'
          ? tr(
              'Duyệt xuất vật tư',
              'Approve material issue',
              'ອະນຸມັດເບີກວັດສະດຸ',
            )
          : proposal
          ? tr(
              'Đề xuất phân bổ chi phí',
              'Propose cost allocation',
              'ສະເໜີແບ່ງຕົ້ນທຶນ',
            )
          : tr(
              'Duyệt phân bổ chi phí',
              'Approve cost allocation',
              'ອະນຸມັດແບ່ງຕົ້ນທຶນ',
            ),
      {
        'id': tr('ID chứng từ nguồn', 'Source document ID', 'ID ເອກະສານ'),
        if (!proposal)
          'revision': tr(
            'Revision đề xuất đã xem',
            'Reviewed proposal revision',
            'Revision ທີ່ກວດແລ້ວ',
          ),
        if (proposal) ...{
          'driver': tr(
            'Tiêu thức (phải chọn)',
            'Allocation basis (choose explicitly)',
            'ເກນແບ່ງ (ຕ້ອງເລືອກ)',
          ),
          'base': tr(
            'Tổng đơn vị cơ sở, gồm phần chưa phân bổ',
            'Total basis units including unallocated',
            'ຈຳນວນຖານລວມ',
          ),
          'scale': tr(
            'Số chữ số thập phân tiền đã duyệt',
            'Approved money decimal places',
            'ຈຳນວນທົດສະນິຍົມເງິນ',
          ),
          'weights': tr(
            'Mỗi dòng: ID kế hoạch | đơn vị | căn cứ; ngăn bằng dấu ;',
            'Each: plan ID | units | evidence; separate by ;',
            'ID ແຜນ | ຫົວໜ່ວຍ | ຫຼັກຖານ; ແຍກດ້ວຍ ;',
          ),
        },
      },
      choices: proposal
          ? {
              'driver': {
                'direct': tr(
                  'Trực tiếp: một kế hoạch, cơ sở 1',
                  'Direct: one plan, base 1',
                  'ໂດຍກົງ: ແຜນດຽວ, ຖານ 1',
                ),
                'area': tr(
                  'Diện tích: đơn vị 0,000001 m²',
                  'Area: units of 0.000001 m²',
                  'ເນື້ອທີ່: 0.000001 m²',
                ),
                'machineMinutes': tr(
                  'Phút máy',
                  'Machine minutes',
                  'ນາທີເຄື່ອງຈັກ',
                ),
                'laborMinutes': tr(
                  'Phút nhân công',
                  'Labor minutes',
                  'ນາທີແຮງງານ',
                ),
                'approvedWeights': tr(
                  'Trọng số có căn cứ duyệt',
                  'Evidenced approved weights',
                  'ນ້ຳໜັກທີ່ອະນຸມັດ',
                ),
              },
            }
          : {},
    );
    if (values == null || !mounted) return;
    await run(() async {
      if (action == 'material') {
        await workflow.approveMaterial(
          values['id']!,
          int.parse(values['revision']!),
        );
      } else if (!proposal) {
        await workflow.approveExpense(
          values['id']!,
          int.parse(values['revision']!),
        );
      } else {
        final weights = values['weights']!.split(';').map((v) {
          final fields = v.split('|').map((s) => s.trim()).toList();
          if (fields.length != 3) {
            throw const FormatException('Plan, units and evidence required.');
          }
          return CostAllocationWeight(
            fields[0],
            int.parse(fields[1]),
            fields[2],
          );
        }).toList();
        await workflow.proposeExpense(
          ExpenseAllocationProposal(
            expenseId: values['id']!,
            driver: CostAllocationDriver.values.byName(values['driver']!),
            baseUnits: int.parse(values['base']!),
            moneyScale: int.parse(values['scale']!),
            weights: weights,
          ),
        );
      }
    });
  }

  Widget costReview(IntegrationSnapshot snapshot) {
    final versions = snapshot.rows('production_source_versions_v2');
    final policies = snapshot.rows('production_expense_policies_v2');
    return ExpansionTile(
      key: const ValueKey('production-cost-approval-review'),
      title: Text(
        tr(
          'Chứng từ và cấu hình cần duyệt',
          'Source and allocation approval review',
          'ກວດເອກະສານ ແລະ ເກນແບ່ງ',
        ),
      ),
      children: [
        for (final v in versions)
          ListTile(
            title: SelectableText(
              '${v['source_type']} · ${v['source_id']} · revision ${v['revision']} · ${v['status']}',
            ),
            subtitle: SelectableText(
              '${tr('Người tạo / duyệt', 'Created / approved by', 'ຜູ້ສ້າງ / ອະນຸມັດ')}: ${v['creator']} / ${v['approver'] ?? '—'}\n${v['created_at']} / ${v['approved_at'] ?? '—'}\n${v['payload_digest']}',
            ),
          ),
        for (final p in policies)
          ListTile(
            title: SelectableText(
              '${p['source_id']} · ${p['driver']} · ${tr('Tổng cơ sở', 'Total basis', 'ຖານລວມ')}: ${p['base_units']} · ${p['currency']} · ${tr('Số lẻ', 'Decimal places', 'ທົດສະນິຍົມ')}: ${p['money_scale']}',
            ),
            subtitle: SelectableText(allocationReview(snapshot, p)),
          ),
      ],
    );
  }

  String allocationReview(
    IntegrationSnapshot snapshot,
    Map<String, Object?> policy,
  ) {
    try {
      final weights = jsonDecode(policy['weights_json'] as String) as List;
      return weights
          .map((raw) {
            final w = raw as Map;
            final plan = snapshot.index('production_plans_v1')[w['planId']];
            return '${snapshot.planCode(w['planId'])} · ${snapshot.parcelCode(plan?['parcel_id'])}: ${w['units']} · ${w['evidence']}';
          })
          .join('\n');
    } catch (_) {
      return tr(
        'Cấu hình không hợp lệ',
        'Invalid configuration',
        'ເກນບໍ່ຖືກຕ້ອງ',
      );
    }
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
                                    e.key == 'capitalKind'
                                        ? tr(
                                            'Không phân loại vốn',
                                            'Not owner capital',
                                            'ບໍ່ຈັດເປັນທຶນ',
                                          )
                                        : tr(
                                            'Tạo mới',
                                            'Create new',
                                            'ສ້າງໃໝ່',
                                          ),
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
                                (!optional.contains(e.key) ||
                                        (e.key == 'reason' &&
                                            choices.containsKey(
                                              'capitalKind',
                                            ) &&
                                            controllers['capitalKind']!
                                                .text
                                                .isNotEmpty)) &&
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
    'stock': {
      'minimumQuantity': [
        'Tồn tối thiểu (đơn vị vật tư)',
        'Minimum stock (item unit)',
        'ສະຕັອກຕ່ຳສຸດ (ຫົວໜ່ວຍວັດສະດຸ)',
      ],
    },
    'capital': {
      'capitalKind': [
        'Phân loại vốn chủ sở hữu',
        'Owner capital classification',
        'ປະເພດທຶນເຈົ້າຂອງ',
      ],
      'reason': [
        'Lý do phân loại vốn',
        'Capital classification reason',
        'ເຫດຜົນຈັດປະເພດທຶນ',
      ],
    },
    'run': {
      'conditionBefore': [
        'Tình trạng máy trước ca',
        'Machine condition before shift',
        'ສະພາບເຄື່ອງຈັກກ່ອນກະ',
      ],
      'conditionAfter': [
        'Tình trạng máy sau ca',
        'Machine condition after shift',
        'ສະພາບເຄື່ອງຈັກຫຼັງກະ',
      ],
      'fuelConsumedLitres': [
        'Nhiên liệu tiêu thụ đo thực tế (lít)',
        'Measured fuel consumption (litres)',
        'ນ້ຳມັນໃຊ້ຈິງທີ່ວັດແທກ (ລິດ)',
      ],
      'incident': [
        'Sự cố / bảo dưỡng trong ca',
        'Incident / maintenance during shift',
        'ບັນຫາ / ບຳລຸງໃນກະ',
      ],
    },

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
      choices: kind == 'capital'
          ? {
              'capitalKind': {
                if (entity['kind'] == 'THU')
                  'contribution': tr(
                    'Góp vốn chủ sở hữu',
                    'Owner capital contribution',
                    'ເຈົ້າຂອງປະກອບທຶນ',
                  ),
                if (entity['kind'] == 'CHI')
                  'return': tr(
                    'Hoàn vốn chủ sở hữu',
                    'Owner capital returned',
                    'ຄືນທຶນເຈົ້າຂອງ',
                  ),
              },
            }
          : const {},
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

  Widget button(String text, VoidCallback? onPressed) =>
      TextButton(onPressed: busy ? null : onPressed, child: Text(text));
  @override
  Widget build(BuildContext context) {
    if (!widget.service.canView && widget.service.canAdministerApproval) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            tr('Chính sách phê duyệt', 'Approval policy', 'ນະໂຍບາຍອະນຸມັດ'),
          ),
        ),
        body: ListView(
          children: [
            ApprovalPolicyPanel(
              store: widget.service.approvalPolicies!,
              can: widget.service.can,
              farm: widget.service.subject.farmId,
              actor: widget.service.subject.userId,
            ),
          ],
        ),
      );
    }
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
                          if (widget.periodClosing != null)
                            PeriodClosePanel(
                              service: widget.periodClosing!,
                              period: s.period,
                              onChanged: reload,
                            ),
                          ProductionCostPanel(
                            snapshot: s,
                            canView: () => widget.service.canView,
                          ),
                          if (widget.service.approvalPolicies != null)
                            ApprovalPolicyPanel(
                              store: widget.service.approvalPolicies!,
                              can: widget.service.can,
                              farm: widget.service.subject.farmId,
                              actor: widget.service.subject.userId,
                            ),
                          if (widget.service.productionCosts != null)
                            costReview(s),
                          if (widget.service.productionCosts != null)
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed:
                                      busy ||
                                          !widget.service.can(
                                            PermissionCodes.inventoryPrice,
                                          ) ||
                                          !widget.service.can(
                                            PermissionCodes.financeApprove,
                                          )
                                      ? null
                                      : widget.controlledApprovals
                                      ? null
                                      : () => costWorkflow('material'),
                                  child: Text(
                                    tr(
                                      'Duyệt vật tư',
                                      'Approve material',
                                      'ອະນຸມັດວັດສະດຸ',
                                    ),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      busy ||
                                          !widget.service.can(
                                            PermissionCodes.financeCreate,
                                          )
                                      ? null
                                      : () => costWorkflow('propose'),
                                  child: Text(
                                    tr(
                                      'Đề xuất phân bổ',
                                      'Propose allocation',
                                      'ສະເໜີແບ່ງຕົ້ນທຶນ',
                                    ),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      busy ||
                                          !widget.service.can(
                                            PermissionCodes.financeApprove,
                                          )
                                      ? null
                                      : widget.controlledApprovals
                                      ? null
                                      : () => costWorkflow('approve'),
                                  child: Text(
                                    tr(
                                      'Duyệt phân bổ',
                                      'Approve allocation',
                                      'ອະນຸມັດແບ່ງຕົ້ນທຶນ',
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                                'Xuất Excel và giá thành theo nguồn',
                                'Export Excel and source production costs',
                                'ສົ່ງອອກ Excel ແລະ ຕົ້ນທຶນຕາມແຫຼ່ງ',
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
                                  'AGRICO-production-${fresh.period}.xlsx',
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
                                      widget.controlledApprovals
                                          ? null
                                          : () => salary(
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
                                                widget.controlledApprovals
                                                    ? null
                                                    : () => machine(
                                                        s,
                                                        r,
                                                        'reverse',
                                                      ),
                                              ))
                                      : PopupMenuButton<String>(
                                          enabled:
                                              !busy &&
                                              !widget.controlledApprovals,
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
                                    'stock': 'Tồn tối thiểu',
                                    'capital': 'Vốn chủ sở hữu',
                                    'run': 'Tình trạng / tiêu thụ ca máy',
                                    'parcel': 'Thửa',
                                    'harvest': 'Thu hoạch',
                                    'machine': 'Máy',
                                    'maintenance': 'Bảo trì',
                                    'worker': 'Nhân viên',
                                    'payroll': 'Bảng lương',
                                  }[kind]!,
                                  {
                                    'stock': 'Minimum stock',
                                    'capital': 'Owner capital',
                                    'run': 'Shift condition / consumption',
                                    'parcel': 'Parcels',
                                    'harvest': 'Harvest',
                                    'machine': 'Machines',
                                    'maintenance': 'Maintenance',
                                    'worker': 'Workers',
                                    'payroll': 'Payroll',
                                  }[kind]!,
                                  {
                                    'stock': 'ສະຕັອກຕ່ຳສຸດ',
                                    'capital': 'ທຶນເຈົ້າຂອງ',
                                    'run': 'ສະພາບ / ນ້ຳມັນໃນກະ',
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
                                            'stock': 'inventory_items_v2',
                                            'capital': 'finance_documents_v2',
                                            'run': 'machine_runs_v1',
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
                                              : kind == 'capital'
                                              ? !s.controlledCash(r['id'])
                                              : true,
                                        ))
                                  ListTile(
                                    title: Text(
                                      '${entity['code'] ?? entity['parcel_code'] ?? (kind == 'run' ? s.name(entity['machine_id']) : entity['id'])} ${entity['name'] ?? ''} ${kind == 'stock'
                                          ? entity['unit'] ?? ''
                                          : kind == 'run'
                                          ? entity['day'] ?? ''
                                          : kind == 'capital'
                                          ? '${IntegrationSnapshot.cashAmount(entity)} ${entity['currency']}'
                                          : ''}',
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
