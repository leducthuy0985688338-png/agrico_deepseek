import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_work_service.dart';
import '../../domain/entities/parcel_work.dart';

class ParcelWorkScreen extends StatefulWidget {
  const ParcelWorkScreen({
    super.key, required this.parcelId, required this.subject,
    required this.service,
  });

  final String parcelId;
  final AuthorizationSubject subject;
  final ParcelWorkService service;

  @override
  State<ParcelWorkScreen> createState() => _ParcelWorkScreenState();
}

class _ParcelWorkScreenState extends State<ParcelWorkScreen> {
  late Future<(List<WorkResource>, List<ParcelWorkEvent>)> data = load();

  Future<(List<WorkResource>, List<ParcelWorkEvent>)> load() async => (
    await widget.service.resources(widget.subject),
    await widget.service.events(widget.subject, widget.parcelId),
  );

  void reload() => setState(() => data = load());

  Future<void> addResource() async {
    final l10n = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    var kind = WorkResourceKind.machine;
    final submitted = await showDialog<bool>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.text('work.addResource')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<WorkResourceKind>(
              value: kind,
              items: [for (final value in WorkResourceKind.values)
                DropdownMenuItem(value: value,
                  child: Text(l10n.text('work.${value.name}')))],
              onChanged: (value) => update(() => kind = value!),
            ),
            TextField(controller: code, decoration: InputDecoration(
              labelText: l10n.text('work.code'))),
            TextField(controller: name, decoration: InputDecoration(
              labelText: l10n.text('work.name'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.text('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.text('common.save'))),
          ],
        ),
      ),
    );
    if (submitted == true) {
      try {
        await widget.service.register(widget.subject, WorkResource(
          id: 'resource-${DateTime.now().microsecondsSinceEpoch}',
          farmId: widget.subject.farmId, kind: kind,
          code: code.text.trim(), name: name.text.trim(),
        ));
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
    final description = TextEditingController();
    final area = TextEditingController();
    var phase = ParcelWorkPhase.clearing;
    final selected = <String>{};
    final submitted = await showDialog<bool>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.text('work.addEvent')),
          content: SizedBox(width: double.maxFinite, child: ListView(
            shrinkWrap: true, children: [
              DropdownButton<ParcelWorkPhase>(
                value: phase,
                items: [for (final value in ParcelWorkPhase.values)
                  DropdownMenuItem(value: value,
                    child: Text(l10n.text('work.${value.name}')))],
                onChanged: (value) => update(() => phase = value!),
              ),
              TextField(controller: description, decoration: InputDecoration(
                labelText: l10n.text('work.description'))),
              TextField(controller: area,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l10n.text('work.areaM2'))),
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
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.text('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.text('common.save'))),
          ],
        ),
      ),
    );
    if (submitted == true) {
      try {
        final parsedArea = area.text.trim().isEmpty
            ? null : double.parse(area.text.trim());
        await widget.service.record(widget.subject, ParcelWorkEvent(
          id: 'work-${DateTime.now().microsecondsSinceEpoch}',
          farmId: widget.subject.farmId, parcelId: widget.parcelId,
          phase: phase, description: description.text.trim(),
          occurredAt: DateTime.now().toUtc(),
          actorMembershipId: widget.subject.membershipId,
          machineIds: resources.where((r) => selected.contains(r.id) &&
              r.kind == WorkResourceKind.machine).map((r) => r.id).toList(),
          workerIds: resources.where((r) => selected.contains(r.id) &&
              r.kind == WorkResourceKind.worker).map((r) => r.id).toList(),
          areaM2: parsedArea,
        ));
        if (mounted) reload();
      } catch (_) {
        if (mounted) _error();
      }
    }
    description.dispose();
    area.dispose();
  }

  void _error() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(AppLocalizations.of(context).text('work.saveFailed')),
  ));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canEdit = widget.subject.permissionCodes.contains(
        PermissionCodes.fieldEdit) &&
        widget.subject.dataScopes.contains(DataScope.allFarm);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('work.title')),
        actions: [IconButton(onPressed: reload,
          tooltip: l10n.text('common.retry'), icon: const Icon(Icons.refresh))]),
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
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (canEdit) Wrap(spacing: 8, children: [
              OutlinedButton.icon(key: const Key('work-add-resource'),
                onPressed: addResource, icon: const Icon(Icons.add),
                label: Text(l10n.text('work.addResource'))),
              FilledButton.icon(key: const Key('work-add-event'),
                onPressed: resources.any((r) => r.active)
                    ? () => addEvent(resources) : null,
                icon: const Icon(Icons.construction),
                label: Text(l10n.text('work.addEvent'))),
            ]),
            if (events.isEmpty) Text(l10n.text('work.empty')),
            for (final event in events) Card(child: ListTile(
              title: Text('${l10n.text('work.${event.phase.name}')} · '
                  '${event.description}'),
              subtitle: Text([
                event.occurredAt.toLocal().toString().substring(0, 16),
                if (event.areaM2 != null) '${event.areaM2} m²',
                for (final id in [...event.machineIds, ...event.workerIds])
                  if (byId[id] != null) byId[id]!.name,
              ].join(' · ')),
            )),
          ]);
        },
      ),
    );
  }
}
