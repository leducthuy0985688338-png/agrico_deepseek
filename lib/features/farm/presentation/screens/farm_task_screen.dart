import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_work_service.dart';
import '../../domain/entities/farm_task.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/parcel_work.dart';
import '../controllers/farm_task_controller.dart';

class FarmTaskScreen extends StatefulWidget {
  const FarmTaskScreen({
    super.key,
    required this.controller,
    required this.resources,
    required this.parcels,
    this.initialParcelId,
  });

  final FarmTaskController controller;
  final ParcelWorkService resources;
  final List<LandParcel> parcels;
  final String? initialParcelId;

  @override
  State<FarmTaskScreen> createState() => _FarmTaskScreenState();
}

class _FarmTaskScreenState extends State<FarmTaskScreen> {
  FarmTaskController get controller => widget.controller;
  ParcelWorkService get resources => widget.resources;
  List<LandParcel> get parcels => widget.parcels;
  late String? parcelFilter = widget.initialParcelId;
  FarmTaskStatus? statusFilter;
  bool overdueOnly = false;
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _add(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateTaskDialog(
        controller: controller,
        resources: resources,
        parcels: parcels,
        initialParcelId: parcelFilter,
      ),
    );
  }

  bool _canEdit(FarmTask task) =>
      controller.subject.dataScopes.contains(DataScope.allFarm) &&
      const AuthorizationService().can(
        subject: controller.subject,
        permission: PermissionCodes.taskEdit,
        resource: ResourceContext(farmId: task.farmId, fieldId: task.parcelId),
      );

  Future<void> _edit(BuildContext context, FarmTask task) async {
    await showDialog<void>(context: context, builder: (_) => _CreateTaskDialog(
      controller: controller, resources: resources, parcels: parcels, task: task,
    ));
  }

  Future<void> _details(BuildContext context, FarmTask task) async {
    final l10n = AppLocalizations.of(context);
    final available = resources.resources(controller.subject);
    final linkedParcels = parcels.where((p) => p.id == task.parcelId);
    final parcelLabel = linkedParcels.isEmpty
        ? task.parcelId ?? '—'
        : '${linkedParcels.first.parcelCode} · ${linkedParcels.first.name}';
    final action = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(task.title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.text('task.${task.status.name}')),
                if (task.isOverdueOn(DateTime.now()))
                  Text(l10n.text('task.overdue')),
                Text('${l10n.text('task.due')}: '
                    '${task.dueAt.year}-${task.dueAt.month}-${task.dueAt.day}'),
                Text('${l10n.text('work.description')}: ${task.description}'),
                Text('${l10n.text('task.parcel')}: $parcelLabel'),
                FutureBuilder<List<WorkResource>>(
                  future: available,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(l10n.text('work.loadFailed'));
                    }
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    String resourceLabel(String? id) {
                      if (id == null) return '—';
                      final matches = snapshot.data!.where((r) => r.id == id);
                      if (matches.isEmpty) return id;
                      final r = matches.first;
                      return '${r.code} · ${r.name}'
                          '${r.active ? '' : ' · ${l10n.text('catalog.inactive')}'}';
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l10n.text('work.machine')}: '
                            '${resourceLabel(task.machineResourceId)}'),
                        Text('${l10n.text('work.worker')}: '
                            '${resourceLabel(task.workerResourceId)}'),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_canEdit(task) && task.status != FarmTaskStatus.completed)
            for (final status in [FarmTaskStatus.inProgress, FarmTaskStatus.delayed])
              if (status != task.status)
                TextButton(
                  key: Key('farm-task-status-${status.name}'),
                  onPressed: () => Navigator.pop(dialogContext, status),
                  child: Text(l10n.text('task.${status.name}')),
                ),
          if (_canEdit(task))
            TextButton(
              key: const Key('farm-task-edit'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.text('common.edit')),
            ),
          TextButton(
            key: const Key('farm-task-close-details'),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == true) {
      await _edit(context, task);
    } else if (action is FarmTaskStatus) {
      await _changeStatus(context, task, action);
    }
  }

  Future<void> _changeStatus(BuildContext context, FarmTask task,
      FarmTaskStatus status) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.text('task.${status.name}')),
        content: Text(task.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.text('common.cancel'))),
          FilledButton(key: const Key('farm-task-confirm-status'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.text('common.save'))),
        ],
      ));
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.changeStatus(task.id, status);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.text('task.saveFailed'))));
      }
    }
  }

  Future<void> _complete(BuildContext context, String taskId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.text('task.completeConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.text('common.cancel')),
          ),
          FilledButton(
            key: const Key('farm-task-confirm-complete'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.text('task.completeAction')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await controller.complete(taskId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.text('task.completeFailed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canCreate =
        controller.subject.permissionCodes.contains(
          PermissionCodes.taskCreate,
        ) &&
        controller.subject.dataScopes.contains(DataScope.allFarm);
    final canComplete =
        controller.subject.permissionCodes.contains(
          PermissionCodes.taskComplete,
        ) &&
        controller.subject.dataScopes.contains(DataScope.allFarm);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final now = DateTime.now();
        final query = search.text.trim().toLowerCase();
        final visible = controller.items.where((task) =>
          (parcelFilter == null || task.parcelId == parcelFilter) &&
          (statusFilter == null || task.status == statusFilter) &&
          (!overdueOnly || task.isOverdueOn(now)) &&
          (query.isEmpty || task.title.toLowerCase().contains(query) ||
            task.description.toLowerCase().contains(query)),
        ).toList();
        final parcelIds = <String>{
          ?parcelFilter,
          for (final p in parcels) p.id,
          for (final task in controller.items) ?task.parcelId,
        };
        String parcelLabel(String id) {
          final matches = parcels.where((p) => p.id == id);
          return matches.isEmpty ? id
              : '${matches.first.parcelCode} · ${matches.first.name}';
        }
        return Scaffold(
        appBar: AppBar(
          title: Text(l10n.text('module.tasks')),
          actions: [
            IconButton(
              onPressed: controller.load,
              tooltip: l10n.text('common.retry'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: canCreate
            ? FloatingActionButton(
                key: const Key('farm-task-add'),
                onPressed: () => _add(context),
                child: const Icon(Icons.add),
              )
            : null,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    key: const Key('farm-task-search'),
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.text('task.search'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: search.text.isEmpty ? null : IconButton(
                        key: const Key('farm-task-clear-search'),
                        tooltip: l10n.text('task.clearSearch'),
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => search.clear()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('farm-task-filter-parcel'),
                    initialValue: parcelFilter,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.text('task.parcel'),
                    ),
                    items: [
                      DropdownMenuItem(value: null,
                        child: Text(l10n.text('common.all'))),
                      for (final id in parcelIds)
                        DropdownMenuItem(value: id,
                          child: Text(parcelLabel(id), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (value) => setState(() => parcelFilter = value),
                  ),
                  DropdownButtonFormField<FarmTaskStatus>(
                    key: const Key('farm-task-filter-status'),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.text('task.filterStatus'),
                    ),
                    items: [
                      DropdownMenuItem(value: null,
                        child: Text(l10n.text('common.all'))),
                      for (final value in FarmTaskStatus.values)
                        DropdownMenuItem(value: value,
                          child: Text(l10n.text('task.${value.name}'))),
                    ],
                    onChanged: (value) => setState(() => statusFilter = value),
                  ),
                  SwitchListTile(
                    key: const Key('farm-task-filter-overdue'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.text('task.overdueOnly')),
                    value: overdueOnly,
                    onChanged: (value) => setState(() => overdueOnly = value),
                  ),
                ],
              ),
            ),
            if (!controller.loading && !controller.hasError)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text('${l10n.text('task.total')}: ${visible.length}',
                      key: const Key('farm-task-count-total')),
                    for (final status in FarmTaskStatus.values)
                      Text('${l10n.text('task.${status.name}')}: '
                        '${visible.where((task) => task.status == status).length}',
                        key: Key('farm-task-count-${status.name}')),
                    Text('${l10n.text('task.overdue')}: '
                      '${visible.where((task) => task.isOverdueOn(now)).length}',
                      key: const Key('farm-task-count-overdue')),
                  ],
                ),
              ),
            Expanded(child: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : controller.hasError
            ? Center(child: Text(l10n.text('task.loadFailed')))
            : visible.isEmpty
            ? Center(child: Text(l10n.text('task.filterEmpty')))
            : ListView.builder(
                key: const Key('farm-task-list'),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final task = visible[index];
                  return ListTile(
                    key: Key('farm-task-details-${task.id}'),
                    onTap: () => _details(context, task),
                    title: Text(task.title),
                    subtitle: Text(
                      '${task.dueAt.year}-'
                      '${task.dueAt.month.toString().padLeft(2, '0')}-'
                      '${task.dueAt.day.toString().padLeft(2, '0')}'
                      '${task.isOverdueOn(now) ? ' · ${l10n.text('task.overdue')}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.text('task.${task.status.name}')),
                        if (canComplete &&
                            task.status != FarmTaskStatus.completed)
                          IconButton(
                            key: Key('farm-task-complete-${task.id}'),
                            tooltip: l10n.text('task.completeAction'),
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () => _complete(context, task.id),
                          ),
                      ],
                    ),
                  );
                },
              )),
          ],
        ),
      );
      },
    );
  }
}

class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog({
    required this.controller,
    required this.resources,
    required this.parcels,
    this.initialParcelId,
    this.task,
  });

  final FarmTaskController controller;
  final ParcelWorkService resources;
  final List<LandParcel> parcels;
  final String? initialParcelId;
  final FarmTask? task;

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  final title = TextEditingController();
  final description = TextEditingController();
  late final Future<List<WorkResource>> available;
  DateTime dueAt = DateTime.now().add(const Duration(days: 1));
  String? workerId;
  String? parcelId;
  String? machineId;
  bool saving = false;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.parcels.any(
      (p) => p.active && p.id == widget.initialParcelId,
    )) {
      parcelId = widget.initialParcelId;
    }
    final task = widget.task;
    if (task != null) {
      title.text = task.title;
      description.text = task.description;
      dueAt = task.dueAt;
      parcelId = task.parcelId;
      machineId = task.machineResourceId;
      workerId = task.workerResourceId;
    }
    available = widget.resources.resources(widget.controller.subject);
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || title.text.trim().isEmpty) {
      setState(() => failed = true);
      return;
    }
    setState(() {
      saving = true;
      failed = false;
    });
    try {
      final task = FarmTask(
          id: widget.task?.id ??
              'task-${DateTime.now().microsecondsSinceEpoch}-'
              '${Random.secure().nextInt(1 << 32)}',
          farmId: widget.controller.subject.farmId,
          title: title.text.trim(),
          description: description.text.trim(),
          status: widget.task?.status ?? FarmTaskStatus.pending,
          dueAt: dueAt,
          createdAt: widget.task?.createdAt ?? DateTime.now(),
          parcelId: parcelId,
          workerResourceId: workerId,
          machineResourceId: machineId,
        );
      if (widget.task == null) {
        await widget.controller.create(task);
      } else {
        await widget.controller.update(task);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
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
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.text(widget.task == null ? 'task.add' : 'common.edit')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('farm-task-title'),
                controller: title,
                decoration: InputDecoration(labelText: l10n.text('task.title')),
              ),
              TextField(
                controller: description,
                decoration: InputDecoration(
                  labelText: l10n.text('work.description'),
                ),
              ),
              TextButton(
                key: const Key('farm-task-due'),
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: dueAt,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null && mounted) {
                    setState(() => dueAt = selected);
                  }
                },
                child: Text(
                  '${l10n.text('task.due')}: '
                  '${dueAt.year}-${dueAt.month}-${dueAt.day}',
                ),
              ),
              DropdownButtonFormField<String>(
                key: const Key('farm-task-parcel'),
                initialValue: parcelId,
                decoration: InputDecoration(
                  labelText: l10n.text('task.parcel'),
                ),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('—')),
                  if (parcelId != null && !widget.parcels.any((p) => p.id == parcelId))
                    DropdownMenuItem(value: parcelId, child: Text(parcelId!)),
                  for (final parcel in widget.parcels.where((p) => p.active || p.id == widget.task?.parcelId))
                    DropdownMenuItem(
                      value: parcel.id,
                      child: Text('${parcel.parcelCode} · ${parcel.name}'),
                    ),
                ],
                onChanged: (value) => setState(() => parcelId = value),
              ),
              FutureBuilder<List<WorkResource>>(
                future: available,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(l10n.text('work.loadFailed'));
                  }
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final machines = snapshot.data!
                      .where(
                        (r) => r.kind == WorkResourceKind.machine &&
                            (r.active || r.id == widget.task?.machineResourceId),
                      )
                      .toList();
                  final workers = snapshot.data!
                      .where(
                        (r) => r.kind == WorkResourceKind.worker &&
                            (r.active || r.id == widget.task?.workerResourceId),
                      )
                      .toList();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        key: const Key('farm-task-machine'),
                        initialValue: machineId,
                        decoration: InputDecoration(
                          labelText: l10n.text('work.machine'),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('—'),
                          ),
                          if (machineId != null && !machines.any((r) => r.id == machineId))
                            DropdownMenuItem(value: machineId, child: Text(machineId!)),
                          for (final r in machines)
                            DropdownMenuItem(
                              value: r.id,
                              child: Text('${r.code} · ${r.name}'
                                '${r.active ? '' : ' · ${l10n.text('catalog.inactive')}'}'),
                            ),
                        ],
                        onChanged: (value) => setState(() => machineId = value),
                      ),
                      DropdownButtonFormField<String>(
                        key: const Key('farm-task-worker'),
                        initialValue: workerId,
                        decoration: InputDecoration(
                          labelText: l10n.text('work.worker'),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('—'),
                          ),
                          if (workerId != null && !workers.any((r) => r.id == workerId))
                            DropdownMenuItem(value: workerId, child: Text(workerId!)),
                          for (final r in workers)
                            DropdownMenuItem(
                              value: r.id,
                              child: Text('${r.code} · ${r.name}'
                                '${r.active ? '' : ' · ${l10n.text('catalog.inactive')}'}'),
                            ),
                        ],
                        onChanged: (value) => setState(() => workerId = value),
                      ),
                    ],
                  );
                },
              ),
              if (failed) Text(l10n.text('task.saveFailed')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text(l10n.text('common.cancel')),
        ),
        FilledButton(
          key: const Key('farm-task-save'),
          onPressed: saving ? null : save,
          child: Text(l10n.text('common.save')),
        ),
      ],
    );
  }
}
