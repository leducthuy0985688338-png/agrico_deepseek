import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import '../application/trade_service.dart';
import '../application/trade_report.dart';

class TradeWorkspaceScreen extends StatefulWidget {
  const TradeWorkspaceScreen({
    super.key,
    required this.service,
    required this.openCatalog,
    required this.openCash,
    this.openReports,
  });
  final TradeService service;
  final VoidCallback openCatalog;
  final VoidCallback? openCash;
  final VoidCallback? openReports;
  @override
  State<TradeWorkspaceScreen> createState() => _TradeWorkspaceState();
}

class _TradeData {
  const _TradeData(
    this.documents,
    this.lots,
    this.payments,
    this.cash,
    this.choices,
  );
  final List<TradeRecord> documents;
  final List<FinishedLot> lots;
  final List<TradePayment> payments;
  final List<Map<String, Object?>> cash;
  final Map<String, List<Map<String, Object?>>> choices;
}

class _TradeWorkspaceState extends State<TradeWorkspaceScreen> {
  late Future<_TradeData> data;
  final period = TextEditingController(text: TradeMath.day().substring(0, 7));
  bool busy = false;
  String t(String k) => AppLocalizations.of(context).text('trade.$k');
  bool can(String p) => widget.service.can(p);
  Future<_TradeData> load() async {
    final s = widget.service;
    return _TradeData(
      await s.documents(),
      await s.lots(),
      await s.payments(),
      can(PermissionCodes.cashView) ? await s.cashBook() : [],
      {
        for (final k in ['customer', 'supplier', 'plan', 'product', 'material'])
          k: await s.choices(k),
      },
    );
  }

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

  void reload() {
    final next = load();
    setState(() {
      data = next;
    });
  }

  String id() =>
      'trade-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      await fn();
      if (mounted) reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('error'))));
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> form(
    String title,
    List<_Field> fields,
    Future<void> Function(Map<String, String>) save,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TradeForm(title: title, fields: fields, save: save),
    );
    if (changed == true && mounted) reload();
  }

  _Field field(
    String key, {
    String value = '',
    bool required = true,
    Map<String, String>? choices,
  }) => _Field(key, t(key), value: value, required: required, choices: choices);
  Map<String, String> choices(_TradeData d, String type) => {
    for (final v in d.choices[type]!)
      v['id'] as String: '${v['code']} · ${v['name']} ${v['currency'] ?? ''}',
  };
  void add(_TradeData d, TradeKind kind) {
    final request = id();
    final harvest = kind == TradeKind.harvest,
        expense = kind == TradeKind.expense;
    final refs = kind == TradeKind.sale
        ? {
            for (final l in d.lots.where((l) => l.stockUnits > 0))
              l.id:
                  '${l.code} · ${l.itemName} · ${l.quantity} ${l.unit} · ${l.currency}',
          }
        : choices(d, harvest ? 'product' : 'material');
    form(
      t(kind.name),
      [
        field('day', value: TradeMath.day()),
        field('currency', choices: {'VND': 'VND', 'LAK': 'LAK'}),
        if (harvest)
          field('plan', choices: choices(d, 'plan'))
        else ...[
          field(
            'party',
            choices: choices(
              d,
              kind == TradeKind.sale ? 'customer' : 'supplier',
            ),
          ),
          field('due', value: TradeMath.day()),
        ],
        field('rounding', choices: {'halfUp': t('halfUp'), 'down': t('down')}),
        if (expense) ...[
          field(
            'treatment',
            choices: {
              'periodExpense': t('periodExpense'),
              'includedInProduction': t('includedInProduction'),
            },
          ),
          field('note'),
        ] else
          field('ref1', choices: refs),
        field('qty1', value: expense ? '1' : ''),
        field('price1'),
        if (kind == TradeKind.sale) field('cost1'),
        field('zero1', value: 'no', choices: {'no': t('no'), 'yes': t('yes')}),
        if (!expense) ...[
          field('ref2', required: false, choices: {'': '—', ...refs}),
          field('qty2', required: false),
          field('price2', required: false),
          if (kind == TradeKind.sale) field('cost2', required: false),
          field(
            'zero2',
            value: 'no',
            choices: {'no': t('no'), 'yes': t('yes')},
          ),
        ],
        field('reference', required: kind == TradeKind.purchase || expense),
        if (!expense) field('note', required: false),
      ],
      (v) {
        final lines = [
          TradeLine(
            ref: expense ? '' : v['ref1']!,
            quantity: v['qty1']!,
            price: v['price1']!,
            issuePrice: kind == TradeKind.sale ? v['cost1'] : null,
            label: expense ? v['note']! : '',
            zeroConfirmed: v['zero1'] == 'yes',
          ),
        ];
        if ((v['ref2'] ?? '').isNotEmpty) {
          lines.add(
            TradeLine(
              ref: v['ref2']!,
              quantity: v['qty2']!,
              price: v['price2']!,
              issuePrice: kind == TradeKind.sale ? v['cost2'] : null,
              zeroConfirmed: v['zero2'] == 'yes',
            ),
          );
        } else if ((v['qty2'] ?? '').isNotEmpty ||
            (v['price2'] ?? '').isNotEmpty ||
            (v['cost2'] ?? '').isNotEmpty) {
          throw const FormatException('Choose line 2 source.');
        }
        return widget.service.create(
          TradeDraft(
            id: request,
            kind: kind,
            day: v['day']!,
            currency: v['currency']!,
            rounding: MoneyRounding.values.byName(v['rounding']!),
            lines: lines,
            partyId: harvest ? null : v['party'],
            planId: harvest ? v['plan'] : null,
            dueOn: harvest ? null : v['due'],
            reference: v['reference']!,
            note: v['note']!,
            expenseTreatment: expense ? v['treatment'] : null,
          ),
        );
      },
    );
  }

  void pay(TradeRecord r) {
    final request = id();
    form(
      t('pay'),
      [
        field('day', value: TradeMath.day()),
        field('amount', value: r.balance),
        field('reference'),
      ],
      (v) => widget.service.settle(
        id: request,
        documentId: r.draft.id,
        amount: v['amount']!,
        currency: r.draft.currency,
        day: v['day']!,
        reference: v['reference']!,
      ),
    );
  }

  void voidDocument(TradeRecord r) => form(t('void'), [
    field('day', value: TradeMath.day()),
    field('note'),
  ], (v) => widget.service.voidDocument(r, v['day']!, v['note']!));
  void reverse(TradePayment p) {
    final request = id();
    form(t('reverse'), [
      field('day', value: TradeMath.day()),
      field('note'),
    ], (v) => widget.service.reversePayment(p, request, v['day']!, v['note']!));
  }

  Widget list(List<Widget> values) => ListView(
    padding: const EdgeInsets.all(12),
    children: values.isEmpty ? [Text(t('empty'))] : values,
  );
  Widget card(List<Widget> values) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: values,
      ),
    ),
  );
  String status(String value) => t(value == 'void' ? 'voided' : value);
  bool canPost(TradeRecord r) =>
      can(PermissionCodes.financePost) &&
      can(PermissionCodes.financeApprove) &&
      (r.draft.kind == TradeKind.expense ||
          (can(PermissionCodes.inventoryPrice) &&
              can(
                r.draft.kind == TradeKind.sale
                    ? PermissionCodes.inventoryIssue
                    : PermissionCodes.inventoryReceive,
              )));
  Widget document(TradeRecord r) {
    final d = r.draft;
    return card([
      Text(
        '${r.code} · ${d.day} · ${status(r.status)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (d.partyId != null)
        Text(r.snapshots['partyName'] as String? ?? d.partyId!),
      Text('${d.billed} ${d.currency}'),
      if (d.dueOn != null) Text('${t('due')}: ${d.dueOn}'),
      for (var i = 0; i < d.lines.length; i++)
        Text(
          '${d.lines[i].quantity} × ${d.lines[i].price} · ${(r.snapshots['lines'] as List?)?[i]['name'] ?? (d.lines[i].label.isNotEmpty ? d.lines[i].label : d.lines[i].ref)}',
        ),
      if (d.kind != TradeKind.harvest && r.status == 'posted')
        Text(
          '${t('paid')}: ${r.paid} · ${t('remaining')}: ${r.balance} ${d.currency}',
        ),
      Wrap(
        children: [
          if (r.status == 'draft' && canPost(r))
            TextButton(
              onPressed: busy
                  ? null
                  : () => action(() => widget.service.post(r)),
              child: Text(t('post')),
            ),
          if (r.status == 'posted' &&
              d.kind != TradeKind.harvest &&
              r.balance != '0' &&
              can(PermissionCodes.cashRecord) &&
              can(PermissionCodes.financeCreate))
            TextButton(
              onPressed: busy ? null : () => pay(r),
              child: Text(t('pay')),
            ),
          if (r.status != 'void' && can(PermissionCodes.financeCorrect))
            TextButton(
              onPressed: busy ? null : () => voidDocument(r),
              child: Text(t('void')),
            ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      'harvest',
      'sale',
      'purchase',
      'expense',
      'lots',
      'debt',
      if (can(PermissionCodes.cashView)) 'cash',
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('title')),
          actions: [
            if (widget.openReports != null)
              IconButton(
                tooltip:
                    AppLocalizations.of(context).locale.languageCode == 'vi'
                    ? 'Báo cáo tổng hợp / liên kết sổ'
                    : AppLocalizations.of(context).locale.languageCode == 'lo'
                    ? 'ລາຍງານລວມ / ເຊື່ອມບັນຊີ'
                    : 'Integrated reports / ledgers',
                onPressed: widget.openReports,
                icon: const Icon(Icons.table_chart),
              ),
            IconButton(
              tooltip: t('catalog'),
              onPressed: widget.openCatalog,
              icon: const Icon(Icons.list_alt),
            ),
            if (widget.openCash != null && can(PermissionCodes.cashView))
              IconButton(
                tooltip: t('legacyCash'),
                onPressed: widget.openCash,
                icon: const Icon(Icons.account_balance_wallet),
              ),
            IconButton(
              tooltip: t('reload'),
              onPressed: busy ? null : reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final tab in tabs) Tab(text: t(tab))],
          ),
        ),
        body: FutureBuilder<_TradeData>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(onPressed: reload, child: Text(t('error'))),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(t('rules')),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: period,
                              decoration: InputDecoration(
                                labelText: t('period'),
                              ),
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                          ),
                          if (can(PermissionCodes.cashView) &&
                              can(PermissionCodes.reportFinance) &&
                              can(PermissionCodes.dataExport))
                            TextButton.icon(
                              icon: const Icon(Icons.download),
                              label: Text(t('export')),
                              onPressed: busy
                                  ? null
                                  : () => action(() async {
                                      final requestedPeriod = period.text;
                                      final fresh = await load();
                                      widget.service.exportPermission();
                                      await saveExcelBytes(
                                        TradeReport(
                                          farm: widget.service.subject.farmId,
                                          period: requestedPeriod,
                                          documents: fresh.documents,
                                          lots: fresh.lots,
                                          payments: fresh.payments,
                                          cash: fresh.cash,
                                        ).bytes(),
                                        'AGRICO-Trade-${requestedPeriod}-${DateTime.now().microsecondsSinceEpoch}.xlsx',
                                      );
                                    }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final kind in TradeKind.values)
                        list([
                          if (can(PermissionCodes.financeCreate))
                            FilledButton(
                              onPressed: busy ? null : () => add(d, kind),
                              child: Text(t('add')),
                            ),
                          for (final r in d.documents.where(
                            (r) =>
                                r.draft.kind == kind &&
                                r.draft.day.startsWith('${period.text}-'),
                          ))
                            document(r),
                        ]),
                      list([
                        for (final l in d.lots)
                          card([
                            Text('${l.code} · ${l.itemName}'),
                            Text(
                              '${l.quantity} ${l.unit} · ${l.price} ${l.currency}',
                            ),
                            Text(
                              '${t('plan')}: ${d.documents.where((h) => h.draft.id == l.harvestId).firstOrNull?.snapshots['planCode'] ?? ''}',
                            ),
                          ]),
                      ]),
                      list([
                        for (final r in d.documents.where(
                          (r) =>
                              r.status == 'posted' &&
                              r.draft.kind != TradeKind.harvest,
                        ))
                          document(r),
                        for (final p in d.payments)
                          card([
                            Text(
                              '${p.financeCode} · ${p.day} · ${p.amount} ${p.currency}',
                            ),
                            Text(
                              '${p.reference} · ${p.reversed ? t('voided') : t('posted')}',
                            ),
                            if (!p.reversed &&
                                can(PermissionCodes.financeCorrect) &&
                                can(PermissionCodes.cashRecord))
                              TextButton(
                                onPressed: busy ? null : () => reverse(p),
                                child: Text(t('reverse')),
                              ),
                          ]),
                      ]),
                      if (can(PermissionCodes.cashView))
                        list([
                          for (final f in d.cash.where(
                            (f) => (f['occurred_at'] as String).startsWith(
                              '${period.text}-',
                            ),
                          ))
                            card([
                              Text('${f['code']} · ${f['occurred_at']}'),
                              Text(
                                '${f['amount_text'] ?? f['amount_minor']} ${f['currency']} · ${f['description'] ?? ''}',
                              ),
                            ]),
                        ]),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Field {
  const _Field(
    this.id,
    this.label, {
    this.value = '',
    this.required = true,
    this.choices,
  });
  final String id, label, value;
  final bool required;
  final Map<String, String>? choices;
}

class _TradeForm extends StatefulWidget {
  const _TradeForm({
    required this.title,
    required this.fields,
    required this.save,
  });
  final String title;
  final List<_Field> fields;
  final Future<void> Function(Map<String, String>) save;
  @override
  State<_TradeForm> createState() => _TradeFormState();
}

class _TradeFormState extends State<_TradeForm> {
  final key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  late final Map<String, String> values;
  bool busy = false;
  String? error;
  String t(String k) => AppLocalizations.of(context).text('trade.$k');
  @override
  void initState() {
    super.initState();
    controllers = {
      for (final f in widget.fields)
        if (f.choices == null) f.id: TextEditingController(text: f.value),
    };
    values = {for (final f in widget.fields) f.id: f.value};
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        for (final f in widget.fields)
          f.id: controllers[f.id]?.text.trim() ?? values[f.id]!,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = t('error');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: f.choices == null
                        ? TextFormField(
                            key: Key('trade-${f.id}'),
                            controller: controllers[f.id],
                            enabled: !busy,
                            decoration: InputDecoration(labelText: f.label),
                            validator: (v) =>
                                f.required && (v ?? '').trim().isEmpty
                                ? t('choose')
                                : null,
                          )
                        : DropdownButtonFormField<String>(
                            key: Key('trade-${f.id}'),
                            initialValue:
                                f.value.isEmpty && !f.choices!.containsKey('')
                                ? null
                                : f.value,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: [
                              for (final c in f.choices!.entries)
                                DropdownMenuItem(
                                  value: c.key,
                                  child: Text(
                                    c.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    values[f.id] = v ?? '';
                                  },
                            validator: (v) => f.required && (v ?? '').isEmpty
                                ? t('choose')
                                : null,
                          ),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: Text(t('close')),
        ),
        FilledButton(onPressed: busy ? null : save, child: Text(t('save'))),
      ],
    ),
  );
}
