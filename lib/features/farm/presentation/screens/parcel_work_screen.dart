import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_work_service.dart';
import '../../application/task_work_service.dart';
import '../../domain/entities/farm_task.dart';
import '../../domain/entities/parcel_work.dart';

class ParcelWorkScreen extends StatefulWidget {
  const ParcelWorkScreen({
    super.key,
    required this.parcelId,
    required this.subject,
    required this.service,
    this.initialTask,
    this.taskWork,
    this.openEventOnLoad = false,
  });

  final String parcelId;
  final AuthorizationSubject subject;
  final ParcelWorkService service;
  final FarmTask? initialTask;
  final TaskWorkService? taskWork;
  final bool openEventOnLoad;

  @override
  State<ParcelWorkScreen> createState() => _ParcelWorkScreenState();
}

class _ParcelWorkScreenState extends State<ParcelWorkScreen> {
  late Future<(List<WorkResource>, List<ParcelWorkEvent>)> data = load();
  ParcelWorkPhase? phaseFilter;

  Future<(List<WorkResource>, List<ParcelWorkEvent>)> load() async {
    final task = widget.initialTask;
    if (task != null &&
        (widget.taskWork == null ||
            task.farmId != widget.subject.farmId ||
            task.parcelId != widget.parcelId)) {
      throw StateError('Invalid task work context.');
    }
    return (
      await widget.service.resources(widget.subject),
      task == null
          ? await widget.service.events(widget.subject, widget.parcelId)
          : await widget.taskWork!.events(widget.subject, task.id),
    );
  }

  bool get canRecord =>
      widget.subject.dataScopes.contains(DataScope.allFarm) &&
      (widget.initialTask == null ||
          (widget.taskWork != null &&
              widget.initialTask!.farmId == widget.subject.farmId &&
              widget.initialTask!.parcelId == widget.parcelId)) &&
      [
        PermissionCodes.fieldEdit,
        if (widget.initialTask != null) PermissionCodes.taskView,
      ].every(
        (permission) => const AuthorizationService().can(
          subject: widget.subject,
          permission: permission,
          resource: ResourceContext(
            farmId: widget.subject.farmId,
            fieldId: widget.parcelId,
          ),
        ),
      );

  @override
  void initState() {
    super.initState();
    if (widget.openEventOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final (resources, _) = await data;
          if (mounted && canRecord) await addEvent(resources);
        } catch (_) {
          // The load error is displayed by FutureBuilder.
        }
      });
    }
  }

  void reload() {
    final refreshed = load();
    setState(() {
      data = refreshed;
    });
  }

  Future<void> addResource() async {
    final l10n = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    var kind = WorkResourceKind.machine;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.text('work.addResource')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<WorkResourceKind>(
                isExpanded: true,
                value: kind,
                items: [
                  for (final value in WorkResourceKind.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        l10n.text('work.${value.name}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => update(() => kind = value!),
              ),
              TextField(
                controller: code,
                decoration: InputDecoration(labelText: l10n.text('work.code')),
              ),
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: l10n.text('work.name')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.text('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.text('common.save')),
            ),
          ],
        ),
      ),
    );
    final submitted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    await route.completed;
    if (submitted == true) {
      try {
        await widget.service.register(
          widget.subject,
          WorkResource(
            id: 'resource-${DateTime.now().microsecondsSinceEpoch}',
            farmId: widget.subject.farmId,
            kind: kind,
            code: code.text.trim(),
            name: name.text.trim(),
          ),
        );
        if (mounted) reload();
      } catch (_) {
        if (mounted) _error();
      }
    }
    code.dispose();
    name.dispose();
  }

  Future<void> addEvent(List<WorkResource> resources) async {
    final l10n = AppLocalizations.of(context);
    if (!canRecord) return;
    final task = widget.initialTask;
    final description = TextEditingController(
      text: task == null
          ? ''
          : (task.description.trim().isEmpty ? task.title : task.description),
    );
    final area = TextEditingController();
    var phase = ParcelWorkPhase.clearing;
    final selected = <String>{
      for (final resource in resources)
        if (resource.active &&
            ((resource.kind == WorkResourceKind.machine &&
                    resource.id == task?.machineResourceId) ||
                (resource.kind == WorkResourceKind.worker &&
                    resource.id == task?.workerResourceId)))
          resource.id,
    };
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.text('work.addEvent')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (task != null) ...[
                  Text(
                    '${l10n.text('task.source')}: ${task.title}',
                    key: const Key('work-source-task'),
                  ),
                  Text(l10n.text('task.workPrefillHint')),
                ],
                DropdownButton<ParcelWorkPhase>(
                  isExpanded: true,
                  value: phase,
                  items: [
                    for (final value in ParcelWorkPhase.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          l10n.text('work.${value.name}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => update(() => phase = value!),
                ),
                TextField(
                  controller: description,
                  onChanged: (_) => update(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.text('work.description'),
                  ),
                ),
                TextField(
                  controller: area,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.text('work.areaM2'),
                  ),
                ),
                for (final resource in resources.where((r) => r.active))
                  CheckboxListTile(
                    title: Text('${resource.code} · ${resource.name}'),
                    subtitle: Text(l10n.text('work.${resource.kind.name}')),
                    value: selected.contains(resource.id),
                    onChanged: (value) => update(() {
                      if (value == true) {
                        selected.add(resource.id);
                      } else {
                        selected.remove(resource.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('work-cancel-event'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.text('common.cancel')),
            ),
            FilledButton(
              key: const Key('work-save-event'),
              onPressed:
                  selected.isNotEmpty && description.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(l10n.text('common.save')),
            ),
          ],
        ),
      ),
    );
    final submitted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    await route.completed;
    if (submitted == true && mounted) {
      try {
        final parsedArea = area.text.trim().isEmpty
            ? null
            : double.parse(area.text.trim());
        final event = ParcelWorkEvent(
          id: 'work-${DateTime.now().microsecondsSinceEpoch}',
          farmId: widget.subject.farmId,
          parcelId: widget.parcelId,
          phase: phase,
          description: description.text.trim(),
          occurredAt: DateTime.now().toUtc(),
          actorMembershipId: widget.subject.membershipId,
          machineIds: resources
              .where(
                (r) =>
                    selected.contains(r.id) &&
                    r.kind == WorkResourceKind.machine,
              )
              .map((r) => r.id)
              .toList(),
          workerIds: resources
              .where(
                (r) =>
                    selected.contains(r.id) &&
                    r.kind == WorkResourceKind.worker,
              )
              .map((r) => r.id)
              .toList(),
          areaM2: parsedArea,
        );
        if (task == null) {
          await widget.service.record(widget.subject, event);
        } else {
          await widget.taskWork!.record(widget.subject, task.id, event);
        }
        if (mounted) reload();
      } catch (_) {
        if (mounted) _error();
      }
    }
    description.dispose();
    area.dispose();
  }

  void _error() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(AppLocalizations.of(context).text('work.saveFailed')),
    ),
  );

  Future<void> showEventDetails(
    ParcelWorkEvent event,
    Map<String, WorkResource> byId,
  ) async {
    if (event.farmId != widget.subject.farmId ||
        event.parcelId != widget.parcelId ||
        !widget.subject.dataScopes.contains(DataScope.allFarm) ||
        ![
          PermissionCodes.fieldView,
          if (widget.initialTask != null) PermissionCodes.taskView,
        ].every(
          (permission) => const AuthorizationService().can(
            subject: widget.subject,
            permission: permission,
            resource: ResourceContext(
              farmId: event.farmId,
              fieldId: event.parcelId,
            ),
          ),
        )) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    String resourceLabel(String id) {
      final resource = byId[id];
      if (resource == null) return id;
      return '${resource.code} · ${resource.name}'
          '${resource.active ? '' : ' · ${l10n.text('catalog.inactive')}'}';
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('work-event-details'),
        title: Text(l10n.text('work.details')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.initialTask != null)
                  Text(
                    '${l10n.text('task.source')}: ${widget.initialTask!.title}',
                  ),
                Text(
                  '${l10n.text('work.phase')}: ${l10n.text('work.${event.phase.name}')}',
                ),
                Text('${l10n.text('work.description')}: ${event.description}'),
                Text(
                  '${l10n.text('work.occurredAt')}: ${event.occurredAt.toLocal().toString().substring(0, 16)}',
                ),
                Text(
                  '${l10n.text('work.machine')}: ${event.machineIds.isEmpty ? '—' : event.machineIds.map(resourceLabel).join('; ')}',
                ),
                Text(
                  '${l10n.text('work.worker')}: ${event.workerIds.isEmpty ? '—' : event.workerIds.map(resourceLabel).join('; ')}',
                ),
                Text('${l10n.text('work.areaM2')}: ${event.areaM2 ?? '—'}'),
                Text('${l10n.text('work.notes')}: ${event.notes ?? '—'}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('work-close-event-details'),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              MaterialLocalizations.of(dialogContext).closeButtonLabel,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canCatalog = const AuthorizationService().can(
      subject: widget.subject,
      permission: PermissionCodes.catalogManage,
      resource: ResourceContext(farmId: widget.subject.farmId),
    );
    final canEdit = canRecord;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('work.title')),
        actions: [
          IconButton(
            onPressed: reload,
            tooltip: l10n.text('common.retry'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<(List<WorkResource>, List<ParcelWorkEvent>)>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('work.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (resources, events) = snapshot.data!;
          final byId = {for (final r in resources) r.id: r};
          final visibleEvents = events
              .where(
                (event) => phaseFilter == null || event.phase == phaseFilter,
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (canEdit)
                Wrap(
                  spacing: 8,
                  children: [
                    if (canCatalog)
                      OutlinedButton.icon(
                        key: const Key('work-add-resource'),
                        onPressed: addResource,
                        icon: const Icon(Icons.add),
                        label: Text(l10n.text('work.addResource')),
                      ),
                    FilledButton.icon(
                      key: const Key('work-add-event'),
                      onPressed: resources.any((r) => r.active)
                          ? () => addEvent(resources)
                          : null,
                      icon: const Icon(Icons.construction),
                      label: Text(l10n.text('work.addEvent')),
                    ),
                  ],
                ),
              if (widget.initialTask != null)
                Text(
                  '${l10n.text('task.source')}: ${widget.initialTask!.title}',
                ),
              InputDecorator(
                decoration: InputDecoration(labelText: l10n.text('work.phase')),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ParcelWorkPhase>(
                    key: const Key('work-phase-filter'),
                    value: phaseFilter,
                    isExpanded: true,
                    hint: Text(
                      l10n.text('common.all'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: [
                      DropdownMenuItem<ParcelWorkPhase>(
                        value: null,
                        child: Text(
                          l10n.text('common.all'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final phase in ParcelWorkPhase.values)
                        DropdownMenuItem<ParcelWorkPhase>(
                          value: phase,
                          child: Text(
                            l10n.text('work.${phase.name}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => phaseFilter = value),
                  ),
                ),
              ),
              if (visibleEvents.isEmpty)
                Text(
                  l10n.text(
                    events.isEmpty ? 'work.empty' : 'work.noFilterResults',
                  ),
                ),
              for (final event in visibleEvents)
                Card(
                  child: ListTile(
                    key: Key('work-event-${event.id}'),
                    onTap: () => showEventDetails(event, byId),
                    trailing: const Icon(Icons.chevron_right),
                    title: Text(
                      '${l10n.text('work.${event.phase.name}')} · '
                      '${event.description}',
                    ),
                    subtitle: Text(
                      [
                        event.occurredAt.toLocal().toString().substring(0, 16),
                        if (event.areaM2 != null) '${event.areaM2} m²',
                        for (final id in [
                          ...event.machineIds,
                          ...event.workerIds,
                        ])
                          if (byId[id] != null) byId[id]!.name,
                      ].join(' · '),
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
