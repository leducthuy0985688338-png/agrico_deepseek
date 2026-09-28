import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/parcel_land_history_service.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/parcel_land_history.dart';
import '../../domain/repositories/land_parcel_repository.dart';

class ParcelLandTimelineScreen extends StatefulWidget {
  const ParcelLandTimelineScreen({
    super.key, required this.subject, required this.parcelId,
    required this.service, required this.parcels,
  });

  final AuthorizationSubject subject;
  final String parcelId;
  final ParcelLandHistoryService service;
  final LandParcelRepository parcels;

  @override
  State<ParcelLandTimelineScreen> createState() => _ParcelLandTimelineScreenState();
}

class _ParcelLandTimelineScreenState extends State<ParcelLandTimelineScreen> {
  late Future<(LandParcel?, List<LandParcel>, List<ParcelStageSnapshot>,
      List<ParcelDerivation>)> data = load();

  Future<(LandParcel?, List<LandParcel>, List<ParcelStageSnapshot>,
      List<ParcelDerivation>)> load() async => (
    await widget.parcels.getById(farmId: widget.subject.farmId,
        id: widget.parcelId),
    await widget.parcels.listByFarm(widget.subject.farmId, includeInactive: true),
    await widget.service.snapshots(widget.subject, widget.parcelId),
    await widget.service.derivations(widget.subject, widget.parcelId),
  );

  void reload() => setState(() => data = load());

  Future<void> capture(LandParcel parcel) async {
    final l10n = AppLocalizations.of(context);
    var stage = ParcelLandStage.beforeClearing;
    var version = parcel.boundaryVersion;
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.text('timeline.capture')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<ParcelLandStage>(value: stage,
              items: [for (final value in ParcelLandStage.values)
                DropdownMenuItem(value: value,
                  child: Text(l10n.text('timeline.${value.name}')))],
              onChanged: (value) => update(() => stage = value!),
            ),
            DropdownButton<int>(value: version,
              items: [for (final boundary in parcel.boundaryHistory)
                DropdownMenuItem(value: boundary.version,
                  child: Text('R${boundary.version} · '
                      '${boundary.areaM2.toStringAsFixed(1)} m²'))],
              onChanged: (value) => update(() => version = value!),
            ),
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
    if (confirmed != true) return;
    try {
      await widget.service.capture(subject: widget.subject,
        parcelId: parcel.id, stage: stage, boundaryVersion: version);
      if (mounted) reload();
    } catch (_) {
      if (mounted) error();
    }
  }

  Future<void> derive(LandParcel target, List<LandParcel> parcels) async {
    final l10n = AppLocalizations.of(context);
    final options = parcels.where((p) => p.id != target.id).toList();
    if (options.isEmpty) return;
    var sourceId = options.first.id;
    var kind = ParcelDerivationKind.subdivision;
    final area = TextEditingController(text: target.areaM2.toStringAsFixed(1));
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.text('timeline.link')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(value: sourceId,
              items: [for (final parcel in options)
                DropdownMenuItem(value: parcel.id,
                  child: Text(parcel.parcelCode))],
              onChanged: (value) => update(() => sourceId = value!),
            ),
            DropdownButton<ParcelDerivationKind>(value: kind,
              items: [for (final value in ParcelDerivationKind.values)
                DropdownMenuItem(value: value,
                  child: Text(l10n.text('timeline.${value.name}')))],
              onChanged: (value) => update(() => kind = value!),
            ),
            TextField(controller: area,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.text('timeline.areaM2'))),
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
    if (confirmed == true) {
      try {
        await widget.service.link(subject: widget.subject,
          sourceParcelId: sourceId, targetParcelId: target.id,
          kind: kind, derivedAreaM2: double.parse(area.text.trim()));
        if (mounted) reload();
      } catch (_) {
        if (mounted) error();
      }
    }
    area.dispose();
  }

  void error() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(AppLocalizations.of(context).text('timeline.saveFailed')),
  ));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canEdit = widget.subject.permissionCodes.contains(
        PermissionCodes.fieldEdit) &&
        widget.subject.dataScopes.contains(DataScope.allFarm);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('timeline.title')),
        actions: [IconButton(onPressed: reload,
          tooltip: l10n.text('common.retry'), icon: const Icon(Icons.refresh))]),
      body: FutureBuilder<(LandParcel?, List<LandParcel>,
          List<ParcelStageSnapshot>, List<ParcelDerivation>)>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('timeline.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (parcel, parcels, stages, links) = snapshot.data!;
          if (parcel == null) {
            return Center(child: Text(l10n.text('timeline.loadFailed')));
          }
          final byId = {for (final p in parcels) p.id: p.parcelCode};
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (canEdit) Wrap(spacing: 8, children: [
              OutlinedButton.icon(key: const Key('timeline-capture'),
                onPressed: () => capture(parcel), icon: const Icon(Icons.add),
                label: Text(l10n.text('timeline.capture'))),
              FilledButton.icon(key: const Key('timeline-link'),
                onPressed: parcels.length > 1
                    ? () => derive(parcel, parcels) : null,
                icon: const Icon(Icons.account_tree),
                label: Text(l10n.text('timeline.link'))),
            ]),
            if (stages.isEmpty && links.isEmpty)
              Text(l10n.text('timeline.empty')),
            for (final stage in stages) ListTile(
              title: Text(l10n.text('timeline.${stage.stage.name}')),
              subtitle: Text('R${stage.boundaryVersion} · '
                  '${stage.areaM2.toStringAsFixed(1)} m² · '
                  '${stage.recordedAt.toLocal().toString().substring(0, 16)}'),
            ),
            for (final link in links) ListTile(
              title: Text('${byId[link.sourceParcelId] ?? link.sourceParcelId}'
                  ' → ${byId[link.targetParcelId] ?? link.targetParcelId}'),
              subtitle: Text('${l10n.text('timeline.${link.kind.name}')} · '
                  '${link.derivedAreaM2.toStringAsFixed(1)} m²'),
            ),
          ]);
        },
      ),
    );
  }
}
