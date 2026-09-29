import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_work_service.dart';
import '../../domain/entities/farm_task.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/parcel_work.dart';
import '../controllers/farm_task_controller.dart';

class FarmTaskScreen extends StatelessWidget {
  const FarmTaskScreen({
    super.key,
    required this.controller,
    required this.resources,
    required this.parcels,
  });

  final FarmTaskController controller;
  final ParcelWorkService resources;
  final List<LandParcel> parcels;

  Future<void> _add(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateTaskDialog(
        controller: controller,
        resources: resources,
        parcels: parcels,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canCreate =
        controller.subject.permissionCodes.contains(
          PermissionCodes.taskCreate,
        ) &&
        controller.subject.dataScopes.contains(DataScope.allFarm);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
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
        body: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : controller.hasError
            ? Center(child: Text(l10n.text('task.loadFailed')))
            : controller.items.isEmpty
            ? Center(child: Text(l10n.text('common.empty')))
            : ListView.builder(
                key: const Key('farm-task-list'),
                itemCount: controller.items.length,
                itemBuilder: (context, index) {
                  final task = controller.items[index];
                  return ListTile(
                    title: Text(task.title),
                    subtitle: Text(
                      '${task.dueAt.year}-'
                      '${task.dueAt.month.toString().padLeft(2, '0')}-'
                      '${task.dueAt.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: Text(l10n.text('task.${task.status.name}')),
                  );
                },
              ),
      ),
    );
  }
}

class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog({
    required this.controller,
    required this.resources,
    required this.parcels,
  });

  final FarmTaskController controller;
  final ParcelWorkService resources;
  final List<LandParcel> parcels;

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
      await widget.controller.create(
        FarmTask(
          id:
              'task-${DateTime.now().microsecondsSinceEpoch}-'
              '${Random.secure().nextInt(1 << 32)}',
          farmId: widget.controller.subject.farmId,
          title: title.text.trim(),
          description: description.text.trim(),
          status: FarmTaskStatus.pending,
          dueAt: dueAt,
          createdAt: DateTime.now(),
          parcelId: parcelId,
          workerResourceId: workerId,
          machineResourceId: machineId,
        ),
      );
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
      title: Text(l10n.text('task.add')),
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
                  for (final parcel in widget.parcels.where((p) => p.active))
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
                        (r) => r.kind == WorkResourceKind.machine && r.active,
                      )
                      .toList();
                  final workers = snapshot.data!
                      .where(
                        (r) => r.kind == WorkResourceKind.worker && r.active,
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
                          for (final r in machines)
                            DropdownMenuItem(
                              value: r.id,
                              child: Text('${r.code} · ${r.name}'),
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
                          for (final r in workers)
                            DropdownMenuItem(
                              value: r.id,
                              child: Text('${r.code} · ${r.name}'),
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
