import 'production_plans_screen.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../application/inventory_service.dart';
import '../domain/repositories/production_destination_repository.dart';

class ProductionWorkspaceScreen extends StatefulWidget {
  const ProductionWorkspaceScreen({
    super.key,
    required this.service,
    required this.subject,
    this.openFinanceCosts,
    this.initialParcelId,
  });
  final InventoryService service;
  final AuthorizationSubject subject;
  final VoidCallback? openFinanceCosts;
  final String? initialParcelId;
  @override
  State<ProductionWorkspaceScreen> createState() =>
      _ProductionWorkspaceScreenState();
}

class _ProductionWorkspaceScreenState extends State<ProductionWorkspaceScreen> {
  late Future<_ProductionView> data;
  bool updating = false;
  @override
  void initState() {
    super.initState();
    data = load();
  }

  Future<_ProductionView> load() async {
    final parcels = await widget.service.productionParcels(widget.subject);
    final seasons = await widget.service.productionSeasons(widget.subject);
    final costs = canViewCosts
        ? await widget.service.productionCosts(widget.subject)
        : <ProductionMaterialCost>[];
    final selected = widget.initialParcelId;
    return _ProductionView(
      parcels,
      seasons.where((s) => selected == null || s.parcelId == selected).toList(),
      costs.where((c) => selected == null || c.parcelId == selected).toList(),
    );
  }

  void reload() {
    final next = load();
    setState(() {
      data = next;
    });
  }

  bool get canManage =>
      widget.subject.dataScopes.contains(DataScope.allFarm) &&
      const AuthorizationService().can(
        subject: widget.subject,
        permission: PermissionCodes.productionPlan,
        resource: ResourceContext(farmId: widget.subject.farmId),
      );

  bool get canViewCosts =>
      widget.subject.dataScopes.contains(DataScope.allFarm) &&
      const AuthorizationService().can(
        subject: widget.subject,
        permission: PermissionCodes.financeView,
        resource: ResourceContext(farmId: widget.subject.farmId),
      );

  Future<void> add() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SeasonDialog(service: widget.service, subject: widget.subject),
    );
    if (mounted && saved == true) reload();
  }

  Future<void> toggle(ProductionSeason season) async {
    if (updating) return;
    setState(() => updating = true);
    try {
      await widget.service.setProductionSeasonActive(
        widget.subject,
        season.id,
        !season.active,
      );
      if (mounted) reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('production.saveFailed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('production.title')),
        actions: [
          if (canViewCosts)
            IconButton(
              key: const Key('production-open-plans'),
              icon: const Icon(Icons.assignment),
              tooltip: l10n.text('planning.title'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProductionPlansScreen(
                    service: widget.service,
                    subject: widget.subject,
                    initialParcelId: widget.initialParcelId,
                  ),
                ),
              ),
            ),
          if (widget.openFinanceCosts != null)
            IconButton(
              icon: const Icon(Icons.account_balance_wallet),
              tooltip: l10n.text('production.financeCosts'),
              onPressed: widget.openFinanceCosts,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: reload),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              key: const Key('production-add-season'),
              onPressed: add,
              icon: const Icon(Icons.add),
              label: Text(l10n.text('production.addSeason')),
            )
          : null,
      body: FutureBuilder<_ProductionView>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('production.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final view = snapshot.data!;
          final names = {
            for (final c in view.costs) c.parcelId: c.parcelCode,
            for (final p in view.parcels) p.id: p.label,
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Text(l10n.text('production.nativeNotice')),
              const SizedBox(height: 16),
              Text(
                l10n.text('production.seasons'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (view.seasons.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.text('production.emptySeasons')),
                ),
              for (final season in view.seasons)
                Card(
                  child: ListTile(
                    title: Text(season.name),
                    subtitle: Text(
                      '${names[season.parcelId] ?? season.parcelId} · ${season.startsOn}\n'
                      '${l10n.text(season.active ? 'production.active' : 'production.closed')}',
                    ),
                    trailing: canManage
                        ? IconButton(
                            key: Key('production-toggle-${season.id}'),
                            tooltip: l10n.text(
                              season.active
                                  ? 'production.close'
                                  : 'production.reopen',
                            ),
                            icon: Icon(
                              season.active
                                  ? Icons.check_circle_outline
                                  : Icons.replay,
                            ),
                            onPressed: updating ? null : () => toggle(season),
                          )
                        : null,
                  ),
                ),
              const SizedBox(height: 16),
              if (canViewCosts)
                Text(
                  l10n.text('production.materialCosts'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (canViewCosts) Text(l10n.text('production.costNotice')),
              if (canViewCosts && view.costs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.text('production.emptyCosts')),
                ),
              // Group by explicit parcel + season. Do not combine with finance
              // expense documents or suggest a currency absent from source items.
              for (final season in view.seasons)
                if (view.costs.any((c) => c.seasonId == season.id))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${names[season.parcelId] ?? season.parcelId} · ${season.name}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final c in view.costs.where(
                            (c) => c.seasonId == season.id,
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${c.itemName}: ${c.quantity} ${c.unit} × ${c.unitPriceText ?? c.unitPrice.toString()} = ${c.amountText ?? c.amount.toString()} ${c.currency ?? '?'}',
                              ),
                              subtitle: Text(
                                '${c.occurredAt.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10)} · ${c.movementId}',
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

class _ProductionView {
  const _ProductionView(this.parcels, this.seasons, this.costs);
  final List<ProductionIdentityChoice> parcels;
  final List<ProductionSeason> seasons;
  final List<ProductionMaterialCost> costs;
}

class _SeasonDialog extends StatefulWidget {
  const _SeasonDialog({required this.service, required this.subject});
  final InventoryService service;
  final AuthorizationSubject subject;
  @override
  State<_SeasonDialog> createState() => _SeasonDialogState();
}

class _SeasonDialogState extends State<_SeasonDialog> {
  final name = TextEditingController();
  late final parcels = widget.service.productionParcels(widget.subject);
  String? parcelId;
  DateTime date = DateTime.now().toUtc().add(const Duration(hours: 7));
  bool saving = false;
  bool failed = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (parcelId == null || name.text.trim().isEmpty) {
      setState(() => failed = true);
      return;
    }
    setState(() {
      saving = true;
      failed = false;
    });
    try {
      await widget.service.createProductionSeason(
        widget.subject,
        ProductionSeason(
          id: 'season-v2-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
          farmId: widget.subject.farmId,
          parcelId: parcelId!,
          name: name.text.trim(),
          startsOn: date.toIso8601String().substring(0, 10),
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
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(l10n.text('production.addSeason')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<List<ProductionIdentityChoice>>(
                  future: parcels,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(l10n.text('production.loadFailed'));
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.data!.isEmpty) {
                      return Text(l10n.text('production.noPlots'));
                    }
                    return DropdownButtonFormField<String>(
                      key: const Key('production-season-parcel'),
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.text('inventory.parcel'),
                      ),
                      items: [
                        for (final p in snapshot.data!)
                          DropdownMenuItem(value: p.id, child: Text(p.label)),
                      ],
                      onChanged: saving
                          ? null
                          : (id) => setState(() => parcelId = id),
                    );
                  },
                ),
                TextField(
                  key: const Key('production-season-name'),
                  controller: name,
                  enabled: !saving,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: l10n.text('production.seasonName'),
                  ),
                ),
                TextButton(
                  key: const Key('production-season-date'),
                  onPressed: saving
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (mounted && selected != null) {
                            setState(() => date = selected);
                          }
                        },
                  child: Text(
                    '${l10n.text('production.startsOn')}: ${date.toIso8601String().substring(0, 10)}',
                  ),
                ),
                if (failed) Text(l10n.text('production.saveFailed')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l10n.text('common.cancel')),
          ),
          FilledButton(
            key: const Key('production-season-save'),
            onPressed: saving ? null : save,
            child: Text(l10n.text('common.save')),
          ),
        ],
      ),
    );
  }
}
