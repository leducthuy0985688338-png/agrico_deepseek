import '../domain/entities/exact_decimal.dart';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../../../services/report_file_saver.dart';
import '../application/inventory_service.dart';
import '../application/production_plan_report.dart';
import '../domain/repositories/production_planning_repository.dart';
import '../domain/repositories/production_destination_repository.dart';

class ProductionPlansScreen extends StatefulWidget {
  const ProductionPlansScreen({
    super.key,
    required this.service,
    required this.subject,
    this.initialParcelId,
  });
  final InventoryService service;
  final AuthorizationSubject subject;
  final String? initialParcelId;
  @override
  State<ProductionPlansScreen> createState() => _ProductionPlansState();
}

class _ProductionPlansState extends State<ProductionPlansScreen> {
  late Future<
    (
      List<ProductionPlan>,
      List<ProductionPlanTask>,
      List<ProductionMaterialCost>,
    )
  >
  data;
  String? selectedPlan;
  DateTimeRange? period;
  bool busy = false;
  bool permission(String code) => const AuthorizationService().can(
    subject: widget.subject,
    permission: code,
    resource: ResourceContext(farmId: widget.subject.farmId),
  );
  bool get manage => permission(PermissionCodes.productionPlan);
  @override
  void initState() {
    super.initState();
    data = load();
  }

  Future<
    (
      List<ProductionPlan>,
      List<ProductionPlanTask>,
      List<ProductionMaterialCost>,
    )
  >
  load() async {
    final plans = await widget.service.productionPlans(widget.subject);
    final tasks = await widget.service.productionPlanTasks(widget.subject);
    final costs = await widget.service.productionCosts(widget.subject);
    return (plans, tasks, costs);
  }

  void reload() {
    final next = load();
    setState(() => data = next);
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('planning.saveFailed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addPlan() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlanDialog(
        service: widget.service,
        subject: widget.subject,
        parcelId: widget.initialParcelId,
      ),
    );
    if (mounted && saved == true) reload();
  }

  Future<void> addTask(ProductionPlan p) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskDialog(
        service: widget.service,
        subject: widget.subject,
        plan: p,
      ),
    );
    if (mounted && saved == true) reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.text('planning.title')),
        actions: [
          IconButton(
            onPressed: busy ? null : reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: manage
          ? FloatingActionButton.extended(
              key: const Key('planning-add'),
              onPressed: busy ? null : addPlan,
              icon: const Icon(Icons.add),
              label: Text(l.text('planning.add')),
            )
          : null,
      body:
          FutureBuilder<
            (
              List<ProductionPlan>,
              List<ProductionPlanTask>,
              List<ProductionMaterialCost>,
            )
          >(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(l.text('planning.loadFailed')));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (plans, tasks, costs) = snapshot.data!;
              final available = plans
                  .where(
                    (p) =>
                        widget.initialParcelId == null ||
                        p.parcelId == widget.initialParcelId,
                  )
                  .toList();
              final report = ProductionPlanReport(
                farmId: widget.subject.farmId,
                plans: plans,
                tasks: tasks,
                costs: costs,
                parcelId: widget.initialParcelId,
                planId: selectedPlan,
                from: period?.start,
                to: period?.end,
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Text(l.text('planning.notice')),
                  DropdownButtonFormField<String>(
                    key: const Key('planning-filter'),
                    initialValue: selectedPlan ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l.text('planning.plan'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(l.text('planning.all')),
                      ),
                      for (final p in available)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.code} · ${p.name}'),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => selectedPlan = v == '' ? null : v),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          period == null
                              ? l.text('planning.period')
                              : '${period!.start.toIso8601String().substring(0, 10)} – ${period!.end.toIso8601String().substring(0, 10)}',
                        ),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDateRange: period,
                          );
                          if (mounted && range != null) {
                            setState(() => period = range);
                          }
                        },
                      ),
                      if (period != null)
                        TextButton(
                          onPressed: () => setState(() => period = null),
                          child: Text(l.text('planning.all')),
                        ),
                      if (permission(PermissionCodes.dataExport))
                        FilledButton.icon(
                          key: const Key('planning-export'),
                          icon: const Icon(Icons.download),
                          label: const Text('Excel'),
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  // Recheck live session permissions before building the financial export.
                                  if (!permission(
                                        PermissionCodes.financeView,
                                      ) ||
                                      !permission(PermissionCodes.dataExport)) {
                                    throw StateError('Export denied.');
                                  }
                                  await saveExcelBytes(
                                    report.bytes(),
                                    'AGRICO-Production-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.xlsx',
                                  );
                                }),
                        ),
                    ],
                  ),
                  if (report.selectedPlans.isEmpty)
                    Text(l.text('planning.empty')),
                  for (final p in report.selectedPlans)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${p.code} · ${p.name}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${p.parcelCode ?? p.parcelId} · ${p.seasonName ?? p.seasonId}',
                            ),
                            Text(
                              '${p.crop} · ${p.startsOn} → ${p.endsOn} · ${l.text('planning.status.${p.status.name}')}',
                            ),
                            Text(
                              '${l.text('planning.materialBudget')}: ${p.materialBudget} ${p.currency}',
                            ),
                            Text(
                              '${l.text('planning.materialActual')}: ${report.materialActual(p.id)} ${p.currency}',
                            ),
                            Text(
                              '${l.text('planning.laborBudget')}: ${p.laborBudget} ${p.currency} · ${p.laborHours} h',
                            ),
                            Text(
                              '${l.text('planning.machineBudget')}: ${p.machineBudget} ${p.currency} · ${p.machineShifts} ${l.text('planning.shifts')}',
                            ),
                            Text(
                              '${l.text('planning.variance')}: ${report.materialActual(p.id) - ExactDecimal.parse(p.materialBudget)} ${p.currency}',
                            ),
                            Text(l.text('planning.actualPending')),
                            if (manage)
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (p.status == ProductionPlanStatus.draft ||
                                      p.status == ProductionPlanStatus.paused)
                                    TextButton(
                                      key: Key('planning-start-${p.id}'),
                                      onPressed: busy
                                          ? null
                                          : () => run(
                                              () => widget.service
                                                  .changeProductionPlanStatus(
                                                    widget.subject,
                                                    p,
                                                    ProductionPlanStatus.active,
                                                  ),
                                            ),
                                      child: Text(l.text('planning.start')),
                                    ),
                                  if (p.status ==
                                      ProductionPlanStatus.active) ...[
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => run(
                                              () => widget.service
                                                  .changeProductionPlanStatus(
                                                    widget.subject,
                                                    p,
                                                    ProductionPlanStatus.paused,
                                                  ),
                                            ),
                                      child: Text(l.text('planning.pause')),
                                    ),
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => run(
                                              () => widget.service
                                                  .changeProductionPlanStatus(
                                                    widget.subject,
                                                    p,
                                                    ProductionPlanStatus
                                                        .completed,
                                                  ),
                                            ),
                                      child: Text(l.text('planning.finish')),
                                    ),
                                  ],
                                  if (p.status == ProductionPlanStatus.draft ||
                                      p.status == ProductionPlanStatus.paused)
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => run(
                                              () => widget.service
                                                  .changeProductionPlanStatus(
                                                    widget.subject,
                                                    p,
                                                    ProductionPlanStatus
                                                        .cancelled,
                                                  ),
                                            ),
                                      child: Text(l.text('planning.cancel')),
                                    ),
                                  if (p.status == ProductionPlanStatus.draft ||
                                      p.status == ProductionPlanStatus.active)
                                    TextButton(
                                      key: Key('planning-task-add-${p.id}'),
                                      onPressed:
                                          busy ||
                                              !permission(
                                                PermissionCodes.taskCreate,
                                              )
                                          ? null
                                          : () => addTask(p),
                                      child: Text(l.text('planning.addTask')),
                                    ),
                                ],
                              ),
                            for (final t in tasks.where(
                              (t) => t.planId == p.id,
                            ))
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: t.completed,
                                title: Text(t.title),
                                subtitle: Text(
                                  '${t.stage} · ${t.quantity} ${t.unit}',
                                ),
                                onChanged:
                                    !manage ||
                                        !permission(
                                          t.completed
                                              ? PermissionCodes.taskEdit
                                              : PermissionCodes.taskComplete,
                                        ) ||
                                        busy ||
                                        p.status != ProductionPlanStatus.active
                                    ? null
                                    : (v) => run(
                                        () => widget.service
                                            .completeProductionPlanTask(
                                              widget.subject,
                                              t,
                                              v ?? false,
                                            ),
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}

String _newId(String type) =>
    '$type-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({
    required this.service,
    required this.subject,
    this.parcelId,
  });
  final InventoryService service;
  final AuthorizationSubject subject;
  final String? parcelId;
  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final controllers = {
    for (final k in [
      'name',
      'crop',
      'start',
      'end',
      'material',
      'labor',
      'machine',
      'hours',
      'shifts',
    ])
      k: TextEditingController(),
  };
  late final String id = _newId('plan');
  late final Future<List<ProductionDestination>> choices = widget.service
      .productionDestinations(widget.subject);
  ProductionDestination? destination;
  String? parcel;
  String? currency;
  bool saving = false, failed = false;
  @override
  void initState() {
    super.initState();
    parcel = widget.parcelId;
    final today = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 7))
        .toIso8601String()
        .substring(0, 10);
    controllers['start']!.text = today;
    controllers['end']!.text = today;
    for (final k in ['material', 'labor', 'machine', 'hours', 'shifts']) {
      controllers[k]!.text = '0';
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      String v(String k) => controllers[k]!.text.trim().replaceAll(',', '.');
      final d = destination;
      if (d == null || currency == null) {
        throw const FormatException('Destination/currency required.');
      }
      await widget.service.createProductionPlan(
        widget.subject,
        ProductionPlan(
          id: id,
          farmId: widget.subject.farmId,
          parcelId: d.parcelId,
          seasonId: d.seasonId,
          name: controllers['name']!.text.trim(),
          crop: controllers['crop']!.text.trim(),
          startsOn: v('start'),
          endsOn: v('end'),
          currency: currency!,
          materialBudget: v('material'),
          laborBudget: v('labor'),
          machineBudget: v('machine'),
          laborHours: v('hours'),
          machineShifts: v('shifts'),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(l.text('planning.add')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<List<ProductionDestination>>(
                  future: choices,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(l.text('planning.loadFailed'));
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final rows = snapshot.data!;
                    final parcels = {
                      for (final d in rows) d.parcelId: d.parcelCode,
                    };
                    return Column(
                      children: [
                        DropdownButtonFormField<String>(
                          key: const Key('planning-parcel'),
                          initialValue: parcel,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l.text('inventory.parcel'),
                          ),
                          items: [
                            for (final p in parcels.entries)
                              DropdownMenuItem(
                                value: p.key,
                                child: Text(p.value),
                              ),
                          ],
                          onChanged: saving
                              ? null
                              : (v) => setState(() {
                                  parcel = v;
                                  destination = null;
                                }),
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('planning-season-$parcel'),
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l.text('inventory.season'),
                          ),
                          items: [
                            for (final d in rows.where(
                              (d) => d.parcelId == parcel,
                            ))
                              DropdownMenuItem(
                                value: d.seasonId,
                                child: Text(d.seasonName),
                              ),
                          ],
                          onChanged: saving
                              ? null
                              : (v) => setState(
                                  () => destination = rows.firstWhere(
                                    (d) =>
                                        d.seasonId == v && d.parcelId == parcel,
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                ),
                for (final k in controllers.keys)
                  TextField(
                    key: Key('planning-$k'),
                    controller: controllers[k],
                    enabled: !saving,
                    keyboardType: ['name', 'crop', 'start', 'end'].contains(k)
                        ? TextInputType.text
                        : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l.text('planning.field.$k'),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  key: const Key('planning-currency'),
                  decoration: InputDecoration(
                    labelText: l.text('planning.currency'),
                  ),
                  items: [
                    for (final c in ['VND', 'LAK'])
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: saving
                      ? null
                      : (v) => setState(() => currency = v),
                ),
                if (failed) Text(l.text('planning.saveFailed')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l.text('common.cancel')),
          ),
          FilledButton(
            key: const Key('planning-save'),
            onPressed: saving ? null : save,
            child: Text(l.text('common.save')),
          ),
        ],
      ),
    );
  }
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({
    required this.service,
    required this.subject,
    required this.plan,
  });
  final InventoryService service;
  final AuthorizationSubject subject;
  final ProductionPlan plan;
  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final due = TextEditingController();
  final title = TextEditingController(),
      stage = TextEditingController(),
      quantity = TextEditingController(),
      unit = TextEditingController();
  late final id = _newId('plan-task');
  bool saving = false, failed = false;
  @override
  void dispose() {
    due.dispose();
    for (final c in [title, stage, quantity, unit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.service.createProductionPlanTask(
        widget.subject,
        ProductionPlanTask(
          id: id,
          farmId: widget.subject.farmId,
          planId: widget.plan.id,
          dueOn: due.text.trim().isEmpty ? null : due.text.trim(),
          title: title.text.trim(),
          stage: stage.text.trim(),
          quantity: quantity.text.trim().replaceAll(',', '.'),
          unit: unit.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(l.text('planning.addTask')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in [
                (title, 'task'),
                (stage, 'stage'),
                (quantity, 'quantity'),
                (unit, 'unit'),
                (due, 'due'),
              ])
                TextField(
                  controller: field.$1,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: l.text('planning.field.${field.$2}'),
                  ),
                ),
              if (failed) Text(l.text('planning.saveFailed')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l.text('common.cancel')),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(l.text('common.save')),
          ),
        ],
      ),
    );
  }
}
