import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import '../application/machine_service.dart';
import '../application/machine_report.dart';

class MachineWorkspaceScreen extends StatefulWidget {
  const MachineWorkspaceScreen({
    super.key,
    required this.service,
    required this.subject,
    required this.openCatalog,
  });
  final MachineService service;
  final AuthorizationSubject subject;
  final VoidCallback openCatalog;
  @override
  State<MachineWorkspaceScreen> createState() => _MachineWorkspaceState();
}

class _MachineData {
  const _MachineData(
    this.machines,
    this.rates,
    this.runs,
    this.expenses,
    this.plans,
    this.workers,
    this.costs,
  );
  final List<MachineCard> machines;
  final List<MachineRate> rates;
  final List<MachineRecord<MachineRun>> runs;
  final List<MachineRecord<MachineExpense>> expenses;
  final List<Map<String, Object?>> plans, workers;
  final List<ProductionMachineCost> costs;
}

class _MachineWorkspaceState extends State<MachineWorkspaceScreen> {
  late Future<_MachineData> data;
  final month = TextEditingController(
    text: MachineRules.day(DateTime.now()).substring(0, 7),
  );
  String? machine;
  bool busy = false;
  String t(String key) => AppLocalizations.of(context).text('machine.$key');
  bool can(String permission) => widget.service.can(widget.subject, permission);
  bool machineAccess(String id, String permission) => widget.service.access.can(
    widget.subject,
    permission,
    resource: ResourceContext(farmId: widget.subject.farmId, machineId: id),
  );
  bool get money => can(PermissionCodes.financeView);
  Future<_MachineData> load({bool exporting = false}) async {
    final stamp = widget.service.access.stamp(widget.subject);
    final s = exporting
        ? widget.service.exporting(widget.subject)
        : widget.service;
    final u = widget.subject;
    final result = _MachineData(
      await s.machines(u),
      money ? await s.rates(u) : [],
      await s.runs(u),
      money ? await s.expenses(u) : [],
      await s.plans(u),
      await s.workers(u),
      money ? await s.costs(u) : [],
    );
    widget.service.access.requireStamp(widget.subject, stamp);
    return result;
  }

  @override
  void initState() {
    super.initState();
    data = load();
    data.ignore();
  }

  @override
  void dispose() {
    month.dispose();
    super.dispose();
  }

  void reload() {
    final next = load();
    setState(() {
      data = next;
    });
  }

  String id() =>
      'machine-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      await fn();
      if (mounted) reload();
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).failure(failure, 'machine.error'),
            ),
          ),
        );
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
    List<_Input> inputs,
    Future<void> Function(Map<String, String>) save,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MachineForm(title: title, inputs: inputs, save: save),
    );
    if (changed == true && mounted) reload();
  }

  Map<String, String> machineChoices(_MachineData d) => {
    for (final m in d.machines.where((m) => m.active))
      m.id: '${m.code} · ${m.name}',
  };
  _Input input(
    String name, {
    String value = '',
    bool required = true,
    Map<String, String>? choices,
  }) =>
      _Input(name, t(name), value: value, required: required, choices: choices);
  void profile(MachineCard m) => form(t('profile'), [
    for (final k in ['model', 'serial', 'plate', 'owner', 'fuelType', 'notes'])
      input(k, value: m.profile[k] ?? '', required: false),
    input(
      'meterUnit',
      value: m.profile['meterUnit'] ?? '',
      choices: {'hour': t('hour'), 'km': t('km')},
    ),
  ], (v) => widget.service.profile(widget.subject, m, v));
  void addRate(_MachineData d) {
    final request = id();
    form(
      t('rates'),
      [
        input('machine', choices: machineChoices(d)),
        input('effective', value: MachineRules.day(DateTime.now())),
        input('amount'),
        input('currency', choices: {'VND': 'VND', 'LAK': 'LAK'}),
        input('shiftMinutes'),
        input('scale', choices: {for (var i = 0; i <= 6; i++) '$i': '$i'}),
        input('rounding', choices: {'halfUp': t('halfUp'), 'down': t('down')}),
      ],
      (v) => widget.service.addRate(
        widget.subject,
        MachineRate(
          id: request,
          machineId: v['machine']!,
          effectiveOn: v['effective']!,
          amount: v['amount']!,
          currency: v['currency']!,
          shiftMinutes: int.parse(v['shiftMinutes']!),
          scale: int.parse(v['scale']!),
          rounding: MoneyRounding.values.byName(v['rounding']!),
        ),
      ),
    );
  }

  DateTime instant(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid date time.');
    }
    MachineRules.date(value.substring(0, 10));
    final hour = int.parse(value.substring(11, 13)),
        minute = int.parse(value.substring(14, 16));
    if (hour > 23 || minute > 59) throw const FormatException('Invalid time.');
    return DateTime.parse('${value.replaceFirst(' ', 'T')}:00+07:00').toUtc();
  }

  void addRun(_MachineData d) {
    final request = id();
    final day = MachineRules.day(DateTime.now());
    final plans = {
      '': t('all'),
      for (final p in d.plans)
        p['id'] as String: '${p['code']} · ${p['name']} · ${p['currency']}',
    };
    form(
      t('runs'),
      [
        input('machine', choices: machineChoices(d)),
        input(
          'operator',
          choices: {
            for (final w in d.workers)
              w['id'] as String: '${w['code']} · ${w['name']}',
          },
        ),
        input('starts', value: '$day 08:00'),
        input('ends', value: '$day 17:00'),
        input('idle', value: '60'),
        input('meterStart'),
        input('meterEnd'),
        input('plan1', required: false, choices: plans),
        input('minutes1', required: false),
        input('plan2', required: false, choices: plans),
        input('minutes2', required: false),
        input('output', required: false),
        input('unit', required: false),
        input('notes', required: false),
      ],
      (v) {
        final allocations = <MachineAllocation>[];
        for (final n in [1, 2]) {
          if (v['plan$n']!.isNotEmpty) {
            allocations.add(
              MachineAllocation(v['plan$n']!, int.parse(v['minutes$n']!)),
            );
          } else if (v['minutes$n']!.isNotEmpty) {
            throw const FormatException('Plan required.');
          }
        }
        return widget.service.addRun(
          widget.subject,
          MachineRun(
            id: request,
            machineId: v['machine']!,
            operatorId: v['operator']!,
            startsAt: instant(v['starts']!),
            endsAt: instant(v['ends']!),
            idleMinutes: int.parse(v['idle']!),
            meterStart: v['meterStart']!,
            meterEnd: v['meterEnd']!,
            allocations: allocations,
            outputQuantity: v['output']!.isEmpty ? null : v['output'],
            outputUnit: v['unit']!.isEmpty ? null : v['unit'],
            note: v['notes']!,
          ),
        );
      },
    );
  }

  void addExpense(_MachineData d, String kind) {
    final request = id();
    form(
      t(kind),
      [
        input('machine', choices: machineChoices(d)),
        input('day', value: MachineRules.day(DateTime.now())),
        if (kind == 'fuel') input('litres'),
        input('meter', required: false),
        input('amount'),
        input('currency', choices: {'VND': 'VND', 'LAK': 'LAK'}),
        input('reference'),
        input('description'),
        if (kind == 'maintenance') ...[
          input('nextOn', required: false),
          input('nextMeter', required: false),
        ],
      ],
      (v) => widget.service.addExpense(
        widget.subject,
        MachineExpense(
          id: request,
          machineId: v['machine']!,
          kind: kind,
          day: v['day']!,
          amount: v['amount']!,
          currency: v['currency']!,
          reference: v['reference']!,
          note: v['description']!,
          litres: v['litres'],
          meter: v['meter']!.isEmpty ? null : v['meter'],
          nextOn: (v['nextOn'] ?? '').isEmpty ? null : v['nextOn'],
          nextMeter: (v['nextMeter'] ?? '').isEmpty ? null : v['nextMeter'],
        ),
      ),
    );
  }

  void reason(Future<void> Function(String) save) =>
      form(t('void'), [input('description')], (v) => save(v['description']!));
  String status(String value) => t(value == 'void' ? 'voided' : value);
  bool selected(String id, String day) =>
      (machine == null || machine == id) && day.startsWith('${month.text}-');
  Widget list(List<Widget> rows) => ListView(
    padding: const EdgeInsets.all(12),
    children: rows.isEmpty ? [Text(t('empty'))] : rows,
  );
  Widget card(List<Widget> rows) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!widget.service.can(widget.subject, PermissionCodes.machineView))
      return Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context).text('error.permissionDenied'),
          ),
        ),
      );
    final tabs = [
      'machines',
      'runs',
      if (money) ...['rates', 'fuel', 'maintenance'],
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('title')),
          actions: [
            IconButton(
              tooltip: t('catalog'),
              onPressed: widget.openCatalog,
              icon: const Icon(Icons.list_alt),
            ),
            IconButton(
              tooltip: t('reload'),
              onPressed: busy ? null : reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final key in tabs) Tab(text: t(key))],
          ),
        ),
        body: FutureBuilder<_MachineData>(
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
            final names = {
              for (final m in d.machines) m.id: '${m.code} · ${m.name}',
            };
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(t('rule')),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: month,
                              decoration: InputDecoration(
                                labelText: t('period'),
                              ),
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: machine ?? '',
                              isExpanded: true,
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: Text(t('all')),
                                ),
                                for (final m in d.machines)
                                  DropdownMenuItem(
                                    value: m.id,
                                    child: Text(
                                      '${m.code} · ${m.name}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  machine = v == '' ? null : v;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      if (money &&
                          can(PermissionCodes.reportOperations) &&
                          can(PermissionCodes.dataExport))
                        TextButton.icon(
                          icon: const Icon(Icons.download),
                          label: Text(t('export')),
                          onPressed: busy
                              ? null
                              : () => action(() async {
                                  final requestedPeriod = month.text;
                                  final stamp = widget.service.access.stamp(
                                    widget.subject,
                                  );
                                  final fresh = await load(exporting: true);
                                  widget.service.access.requireStamp(
                                    widget.subject,
                                    stamp,
                                  );
                                  widget.service.exportPermission(
                                    widget.subject,
                                  );
                                  await saveExcelBytes(
                                    MachineReport(
                                      farm: widget.subject.farmId,
                                      period: requestedPeriod,
                                      machineId: machine,
                                      machines: fresh.machines,
                                      runs: fresh.runs,
                                      expenses: fresh.expenses,
                                      costs: fresh.costs,
                                    ).export(),
                                    'AGRICO-machines-${requestedPeriod}-${DateTime.now().millisecondsSinceEpoch}.xlsx',
                                  );
                                }),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      list([
                        for (final m in d.machines.where(
                          (m) => machine == null || m.id == machine,
                        ))
                          card([
                            Text('${m.code} · ${m.name}'),
                            Text(
                              '${m.profile['model'] ?? ''} · ${m.profile['plate'] ?? ''} · ${m.profile['meterUnit'] ?? ''}',
                            ),
                            ..._due(d, m),
                            if (machineAccess(
                              m.id,
                              PermissionCodes.machineMaintain,
                            ))
                              TextButton(
                                onPressed: busy ? null : () => profile(m),
                                child: Text(t('profile')),
                              ),
                          ]),
                      ]),
                      list([
                        if (can(PermissionCodes.machineLog))
                          FilledButton(
                            onPressed: busy ? null : () => addRun(d),
                            child: Text(t('add')),
                          ),
                        for (final r in d.runs.where(
                          (r) =>
                              selected(r.value.machineId, r.value.businessDay),
                        ))
                          card([
                            Text(
                              '${names[r.value.machineId]} · ${r.value.businessDay} · ${status(r.status)}',
                            ),
                            Text(
                              '${r.value.minutes} min · ${r.value.meterStart} → ${r.value.meterEnd}',
                            ),
                            if (r.amount != null)
                              Text('${r.amount} ${r.currency}'),
                            for (final a in r.value.allocations)
                              Text(
                                '${d.plans.where((p) => p['id'] == a.planId).firstOrNull?['code'] ?? a.planId}: ${a.minutes} min',
                              ),
                            if (machineAccess(
                              r.value.machineId,
                              PermissionCodes.machineVerify,
                            ))
                              Wrap(
                                children: [
                                  if (r.status == 'draft' &&
                                      machineAccess(
                                        r.value.machineId,
                                        PermissionCodes.financeView,
                                      ))
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => action(
                                              () => widget.service.approveRun(
                                                widget.subject,
                                                r,
                                              ),
                                            ),
                                      child: Text(t('approve')),
                                    ),
                                  if (r.status != 'void')
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => reason(
                                              (v) => widget.service.voidRun(
                                                widget.subject,
                                                r,
                                                v,
                                              ),
                                            ),
                                      child: Text(t('void')),
                                    ),
                                ],
                              ),
                          ]),
                      ]),
                      if (money) ...[
                        list([
                          if (can(PermissionCodes.machineAssign) &&
                              can(PermissionCodes.financeApprove))
                            FilledButton(
                              onPressed: busy ? null : () => addRate(d),
                              child: Text(t('add')),
                            ),
                          for (final r in d.rates.where(
                            (r) => machine == null || r.machineId == machine,
                          ))
                            card([
                              Text(
                                '${names[r.machineId]} · ${r.effectiveOn} · v${r.revision}',
                              ),
                              Text(
                                '${r.amount} ${r.currency} / ${r.shiftMinutes} min · ${t(r.rounding.name)} (${r.scale})',
                              ),
                            ]),
                        ]),
                        for (final kind in ['fuel', 'maintenance'])
                          list([
                            if (can(
                              kind == 'fuel'
                                  ? PermissionCodes.machineLog
                                  : PermissionCodes.machineMaintain,
                            ))
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => addExpense(d, kind),
                                child: Text(t('add')),
                              ),
                            for (final r in d.expenses.where(
                              (r) =>
                                  r.value.kind == kind &&
                                  selected(r.value.machineId, r.value.day),
                            ))
                              card([
                                Text(
                                  '${names[r.value.machineId]} · ${r.value.day} · ${status(r.status)}',
                                ),
                                Text(
                                  '${r.value.litres ?? ''} ${kind == 'fuel' ? 'L' : ''} · ${r.value.amount} ${r.value.currency}',
                                ),
                                Text('${r.value.reference} · ${r.value.note}'),
                                if (r.value.nextOn != null ||
                                    r.value.nextMeter != null)
                                  Text(
                                    '${r.value.nextOn ?? ''} · ${r.value.nextMeter ?? ''}',
                                  ),
                                if (machineAccess(
                                  r.value.machineId,
                                  PermissionCodes.machineVerify,
                                ))
                                  Wrap(
                                    children: [
                                      if (r.status == 'draft')
                                        TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => action(
                                                  () => widget.service
                                                      .approveExpense(
                                                        widget.subject,
                                                        r,
                                                      ),
                                                ),
                                          child: Text(t('approve')),
                                        ),
                                      if (r.status != 'void')
                                        TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => reason(
                                                  (v) => widget.service
                                                      .voidExpense(
                                                        widget.subject,
                                                        r,
                                                        v,
                                                      ),
                                                ),
                                          child: Text(t('void')),
                                        ),
                                    ],
                                  ),
                              ]),
                          ]),
                      ],
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

  List<Widget> _due(_MachineData d, MachineCard m) {
    final history =
        d.expenses
            .where(
              (r) =>
                  r.status == 'approved' &&
                  r.value.machineId == m.id &&
                  r.value.kind == 'maintenance',
            )
            .toList()
          ..sort((a, b) => b.value.day.compareTo(a.value.day));
    if (history.isEmpty) return [];
    final last = history.first.value;
    final runs =
        d.runs
            .where((r) => r.status == 'approved' && r.value.machineId == m.id)
            .toList()
          ..sort((a, b) => b.value.endsAt.compareTo(a.value.endsAt));
    final meter = runs.isEmpty ? last.meter : runs.first.value.meterEnd;
    final due =
        (last.nextOn != null &&
            MachineRules.day(DateTime.now()).compareTo(last.nextOn!) >= 0) ||
        (last.nextMeter != null &&
            meter != null &&
            ExactDecimal.parse(
                  meter,
                ).compareTo(ExactDecimal.parse(last.nextMeter!)) >=
                0);
    return [
      if (due)
        Text(
          t('due'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Text('${last.nextOn ?? ''} · ${last.nextMeter ?? ''}'),
    ];
  }
}

class _Input {
  const _Input(
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

class _MachineForm extends StatefulWidget {
  const _MachineForm({
    required this.title,
    required this.inputs,
    required this.save,
  });
  final String title;
  final List<_Input> inputs;
  final Future<void> Function(Map<String, String>) save;
  @override
  State<_MachineForm> createState() => _MachineFormState();
}

class _MachineFormState extends State<_MachineForm> {
  final key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  late final Map<String, String> values;
  bool busy = false;
  String? error;
  String t(String k) => AppLocalizations.of(context).text('machine.$k');
  @override
  void initState() {
    super.initState();
    controllers = {
      for (final f in widget.inputs)
        if (f.choices == null) f.id: TextEditingController(text: f.value),
    };
    values = {for (final f in widget.inputs) f.id: f.value};
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
        for (final f in widget.inputs)
          f.id: controllers[f.id]?.text.trim() ?? values[f.id]!,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = AppLocalizations.of(
            context,
          ).failure(failure, 'machine.error');
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
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in widget.inputs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: f.choices == null
                        ? TextFormField(
                            key: Key('machine-${f.id}'),
                            controller: controllers[f.id],
                            enabled: !busy,
                            decoration: InputDecoration(labelText: f.label),
                            validator: (v) =>
                                f.required && (v ?? '').trim().isEmpty
                                ? t('pick')
                                : null,
                          )
                        : DropdownButtonFormField<String>(
                            key: Key('machine-${f.id}'),
                            initialValue:
                                f.value.isEmpty && !f.choices!.containsKey('')
                                ? null
                                : f.value,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: [
                              for (final e in f.choices!.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
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
                                ? t('pick')
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
          child: Text(t('cancel')),
        ),
        FilledButton(onPressed: busy ? null : save, child: Text(t('save'))),
      ],
    ),
  );
}
