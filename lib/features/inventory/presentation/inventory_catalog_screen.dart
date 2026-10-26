import '../domain/repositories/warehouse_repository.dart';
import '../domain/repositories/production_planning_repository.dart';
import '../domain/entities/exact_decimal.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/catalog/company_catalog.dart';
import '../../../core/catalog/company_catalog_screen.dart';
import '../../../core/permissions/authorization.dart';
import '../application/inventory_service.dart';
import '../domain/entities/inventory_item.dart';
import 'inventory_history_screen.dart';
import 'production_workspace_screen.dart';
import '../domain/repositories/production_destination_repository.dart';

class InventoryCatalogScreen extends StatefulWidget {
  const InventoryCatalogScreen({
    super.key,
    required this.subject,
    required this.service,
    this.catalog,
    this.productionIssuesEnabled = false,
  });

  final bool productionIssuesEnabled;
  final CompanyCatalogService? catalog;
  final AuthorizationSubject subject;
  final InventoryService service;

  @override
  State<InventoryCatalogScreen> createState() => _InventoryCatalogScreenState();
}

class _InventoryCatalogScreenState extends State<InventoryCatalogScreen> {
  late Future<List<InventoryItem>> items;
  String? selectedWarehouse;
  List<InventoryWarehouse> warehouseOptions = [];
  Future<List<InventoryItem>> loadItems() async {
    final stamp = widget.service.access.stamp(widget.subject);
    warehouseOptions = await widget.service.warehouses(widget.subject);
    if (warehouseOptions.isNotEmpty &&
        !warehouseOptions.any((w) => w.id == selectedWarehouse))
      selectedWarehouse = warehouseOptions.first.id;
    final rows = await widget.service.list(
      widget.subject,
      warehouseId: selectedWarehouse,
    );
    widget.service.access.requireStamp(widget.subject, stamp);
    if (mounted) setState(() {});
    return rows;
  }

  bool allowed(String p) => selectedWarehouse == null
      ? widget.service.can(widget.subject, p)
      : widget.service.canAtWarehouse(widget.subject, p, selectedWarehouse!);
  Future<void> createWarehouse() async {
    final name = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(AppLocalizations.of(c).text('warehouse.create')),
        content: TextField(controller: name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c).text('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, name.text.trim()),
            child: Text(AppLocalizations.of(c).text('common.save')),
          ),
        ],
      ),
    );
    name.dispose();
    if (result == null || result.isEmpty) return;
    try {
      await widget.service.createWarehouse(
        widget.subject,
        'warehouse-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
        result,
      );
      if (mounted) reload();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('inventory.movementFailed'),
            ),
          ),
        );
    }
  }

  Future<void> transfer(InventoryItem item) async {
    final source = selectedWarehouse;
    if (source == null) return;
    final destinations = warehouseOptions
        .where(
          (w) =>
              w.active &&
              w.id != source &&
              widget.service.canAtWarehouse(
                widget.subject,
                PermissionCodes.inventoryTransfer,
                w.id,
              ) &&
              widget.service.canAtWarehouse(
                widget.subject,
                PermissionCodes.inventoryView,
                w.id,
              ),
        )
        .toList();
    if (destinations.isEmpty) return;
    String destination = destinations.first.id;
    final quantity = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(AppLocalizations.of(c).text('warehouse.transfer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: destination,
              items: [
                for (final w in destinations)
                  DropdownMenuItem(
                    value: w.id,
                    child: Text('${w.code} · ${w.name}'),
                  ),
              ],
              onChanged: (v) => destination = v!,
            ),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: AppLocalizations.of(c).text('inventory.quantity'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c).text('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(AppLocalizations.of(c).text('common.save')),
          ),
        ],
      ),
    );
    final text = quantity.text.trim().replaceAll(',', '.');
    quantity.dispose();
    if (result != true) return;
    try {
      await widget.service.transfer(
        widget.subject,
        id: 'transfer-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
        itemId: item.id,
        sourceId: source,
        destinationId: destination,
        quantity: num.parse(text),
        at: DateTime.now(),
      );
      if (mounted) reload();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('inventory.movementFailed'),
            ),
          ),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    items = Future<List<InventoryItem>>.sync(loadItems);
    items.ignore();
  }

  void reload() {
    setState(() {
      items = Future<List<InventoryItem>>.sync(loadItems);
      items.ignore();
    });
  }

  Future<void> add() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddItemDialog(
        subject: widget.subject,
        service: widget.service,
        catalog: widget.catalog,
      ),
    );
    if (saved == true && mounted) {
      reload();
    }
  }

  Future<void> record(
    InventoryItem item,
    InventoryMovementKind kind, {
    bool production = false,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MovementDialog(
        subject: widget.subject,
        service: widget.service,
        item: item,
        kind: kind,
        warehouseId: selectedWarehouse,
        production: production,
      ),
    );
    if (saved == true && mounted) {
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canReceipt =
        allowed(PermissionCodes.inventoryManage) ||
        allowed(PermissionCodes.inventoryReceive);
    final canIssue =
        (allowed(PermissionCodes.inventoryManage) ||
            allowed(PermissionCodes.inventoryIssue)) &&
        widget.service.can(widget.subject, PermissionCodes.inventoryPrice);
    final canManage = canReceipt || canIssue;
    if (!widget.service.canOpenWarehouse(widget.subject))
      return Scaffold(
        body: Center(child: Text(l10n.text('error.permissionDenied'))),
      );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.warehouse')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: FutureBuilder<List<InventoryItem>>(
            future: items,
            builder: (context, snapshot) => warehouseOptions.isEmpty
                ? const SizedBox.shrink()
                : DropdownButton<String>(
                    key: const Key('warehouse-selector'),
                    value: selectedWarehouse,
                    items: [
                      for (final w in warehouseOptions)
                        DropdownMenuItem(
                          value: w.id,
                          child: Text('${w.code} · ${w.name}'),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      selectedWarehouse = v;
                      items = Future.sync(
                        () =>
                            widget.service.list(widget.subject, warehouseId: v),
                      );
                      items.ignore();
                    }),
                  ),
          ),
        ),
        actions: [
          if (widget.service.can(widget.subject, PermissionCodes.catalogManage))
            IconButton(
              key: const Key('warehouse-create'),
              tooltip: l10n.text('warehouse.create'),
              onPressed: createWarehouse,
              icon: const Icon(Icons.add_business),
            ),
          if (widget.productionIssuesEnabled)
            IconButton(
              key: const Key('inventory-production-workspace'),
              tooltip: l10n.text('production.title'),
              icon: const Icon(Icons.grass),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProductionWorkspaceScreen(
                    service: widget.service,
                    subject: widget.subject,
                  ),
                ),
              ),
            ),
          IconButton(
            key: const Key('inventory-history-open'),
            tooltip: l10n.text('inventory.history'),
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InventoryHistoryScreen(
                  subject: widget.subject,
                  service: widget.service,
                  warehouseId: selectedWarehouse,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: reload,
            tooltip: l10n.text('common.retry'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton:
          const AuthorizationService().can(
            subject: widget.subject,
            permission: PermissionCodes.catalogManage,
            resource: ResourceContext(farmId: widget.subject.farmId),
          )
          ? FloatingActionButton(
              key: const Key('inventory-add'),
              onPressed: add,
              child: const Icon(Icons.add),
            )
          : null,
      body: FutureBuilder<List<InventoryItem>>(
        future: items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('inventory.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                '${l10n.text('common.empty')}\n${l10n.text('inventory.add')}',
              ),
            );
          }
          return ListView.builder(
            key: const Key('inventory-list'),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final item = snapshot.data![index];
              return ListTile(
                title: Text('${item.code} · ${item.name}'),
                trailing: canManage && !item.finishedGoods
                    ? PopupMenuButton<InventoryMovementKind>(
                        key: Key('inventory-actions-${item.id}'),
                        onSelected: (kind) => record(item, kind),
                        itemBuilder: (_) => [
                          for (final kind in InventoryMovementKind.values.where(
                            (k) => k == InventoryMovementKind.receipt
                                ? canReceipt
                                : canIssue,
                          ))
                            PopupMenuItem(
                              key: Key('inventory-${kind.name}-${item.id}'),
                              value: kind,
                              child: Text(l10n.text('inventory.${kind.name}')),
                            ),
                        ],
                      )
                    : null,
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.text('inventory.stock')}: ${item.stock} ${item.unit}',
                    ),
                    if (item.finishedGoods)
                      Text(l10n.text('trade.productWorkflow')),
                    if (!item.finishedGoods &&
                        allowed(PermissionCodes.inventoryTransfer))
                      TextButton(
                        key: Key('warehouse-transfer-${item.id}'),
                        onPressed: () => transfer(item),
                        child: Text(l10n.text('warehouse.transfer')),
                      ),
                    if (canManage && !item.finishedGoods)
                      Wrap(
                        spacing: 8,
                        children: [
                          if (canReceipt)
                            TextButton(
                              key: Key('inventory-direct-receipt-${item.id}'),
                              onPressed: () =>
                                  record(item, InventoryMovementKind.receipt),
                              child: Text(l10n.text('inventory.receipt')),
                            ),
                          if (widget.productionIssuesEnabled && canIssue)
                            TextButton(
                              key: Key('inventory-production-issue-${item.id}'),
                              onPressed: () => record(
                                item,
                                InventoryMovementKind.issue,
                                production: true,
                              ),
                              child: Text(
                                l10n.text('inventory.productionIssue'),
                              ),
                            ),
                          if (canIssue)
                            TextButton(
                              key: Key('inventory-direct-issue-${item.id}'),
                              onPressed: () =>
                                  record(item, InventoryMovementKind.issue),
                              child: Text(l10n.text('inventory.issue')),
                            ),
                        ],
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({
    required this.subject,
    required this.service,
    this.catalog,
  });

  final CompanyCatalogService? catalog;

  final AuthorizationSubject subject;
  final InventoryService service;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final code = TextEditingController();
  final name = TextEditingController();
  final unit = TextEditingController();
  final price = TextEditingController();
  final supplier = TextEditingController();
  bool saving = false;
  bool failed = false;
  String? errorDetail;
  CatalogEntry? selectedMaterial;
  late Future<List<CatalogEntry>>? catalogEntries = widget.catalog?.entries();

  Future<void> manageCatalog() async {
    final catalog = widget.catalog;
    if (catalog == null || !catalog.canManage) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompanyCatalogScreen(
          service: catalog,
          initialKind: CatalogKind.material,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        catalogEntries = catalog.entries();
        selectedMaterial = null;
        code.clear();
        name.clear();
        unit.clear();
      });
    }
  }

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    unit.dispose();
    price.dispose();
    supplier.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) {
      return;
    }
    if (widget.catalog != null && selectedMaterial == null) {
      setState(() {
        failed = true;
        errorDetail = 'Select a material from the shared catalog.';
      });
      return;
    }
    final parsedPrice = double.tryParse(price.text.trim().replaceAll(',', '.'));
    if (parsedPrice == null || !parsedPrice.isFinite || parsedPrice < 0) {
      setState(() {
        failed = true;
        errorDetail = 'Invalid unit price.';
      });
      return;
    }
    setState(() {
      saving = true;
      failed = false;
      errorDetail = null;
    });
    try {
      await widget.service.register(
        widget.subject,
        InventoryItem(
          id:
              selectedMaterial?.id ??
              'inventory-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
          farmId: widget.subject.farmId,
          code: code.text.trim(),
          name: name.text.trim(),
          unit: unit.text.trim(),
          unitPrice: parsedPrice,
          supplier: supplier.text.trim(),
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
          errorDetail = error is CatalogFailure ? error.code : error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.text('inventory.add')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.catalog?.canManage == true)
                TextButton.icon(
                  key: const Key('inventory-manage-shared-catalog'),
                  onPressed: saving ? null : manageCatalog,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.text('catalog.title')),
                ),
              if (catalogEntries != null)
                FutureBuilder<List<CatalogEntry>>(
                  future: catalogEntries,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(l10n.text('catalog.loadFailed'));
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final entries = snapshot.data!;
                    final materials = entries
                        .where(
                          (e) => e.kind == CatalogKind.material && e.active,
                        )
                        .toList();
                    if (materials.isEmpty) {
                      return Text(l10n.text('catalog.empty'));
                    }
                    return DropdownButtonFormField<String>(
                      key: const Key('inventory-material-picker'),
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.text('inventory.name'),
                      ),
                      initialValue: selectedMaterial?.id,
                      items: [
                        for (final material in materials)
                          DropdownMenuItem(
                            value: material.id,
                            child: Text(
                              '${material.code} · ${material.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (id) {
                              final material = materials.firstWhere(
                                (e) => e.id == id,
                              );
                              final units = entries.where(
                                (e) =>
                                    e.kind == CatalogKind.unit &&
                                    e.active &&
                                    e.id == material.unitId,
                              );
                              if (units.isEmpty) {
                                setState(() {
                                  failed = true;
                                  errorDetail = 'catalog.unitRequired';
                                });
                                return;
                              }
                              setState(() {
                                selectedMaterial = material;
                                code.text = material.code;
                                name.text = material.name;
                                unit.text = units.first.name;
                                failed = false;
                              });
                            },
                    );
                  },
                ),
              TextField(
                key: const Key('inventory-code'),
                readOnly: widget.catalog != null,
                controller: code,
                decoration: InputDecoration(
                  labelText: l10n.text('inventory.code'),
                ),
              ),
              TextField(
                key: const Key('inventory-name'),
                readOnly: widget.catalog != null,
                controller: name,
                decoration: InputDecoration(
                  labelText: l10n.text('inventory.name'),
                ),
              ),
              TextField(
                key: const Key('inventory-unit'),
                readOnly: widget.catalog != null,
                controller: unit,
                decoration: InputDecoration(
                  labelText: l10n.text('inventory.unit'),
                ),
              ),
              TextField(
                key: const Key('inventory-price'),
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.text('inventory.price'),
                ),
              ),
              TextField(
                key: const Key('inventory-supplier'),
                controller: supplier,
                decoration: InputDecoration(
                  labelText: l10n.text('inventory.supplier'),
                ),
              ),
              if (failed)
                Text(
                  '${l10n.text('inventory.saveFailed')} ${errorDetail ?? ''}',
                  key: const Key('inventory-save-error'),
                ),
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
          key: const Key('inventory-save'),
          onPressed: saving ? null : save,
          child: Text(l10n.text('common.save')),
        ),
      ],
    );
  }
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.subject,
    required this.service,
    required this.item,
    required this.kind,
    this.warehouseId,
    this.production = false,
  });

  final bool production;
  final AuthorizationSubject subject;
  final InventoryService service;
  final InventoryItem item;
  final InventoryMovementKind kind;
  final String? warehouseId;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final quantity = TextEditingController();
  final issuePrice = TextEditingController();
  String? currency;
  String? planId;
  bool confirmZero = false;
  late final movementId =
      'inventory-movement-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  late final occurredAt = DateTime.now().toUtc();
  late final Future<List<ProductionPlan>> plans = widget.production
      ? widget.service.productionPlans(widget.subject)
      : Future.value([]);
  bool get canPrice => const AuthorizationService().can(
    subject: widget.subject,
    permission: PermissionCodes.inventoryPrice,
    resource: ResourceContext(farmId: widget.subject.farmId),
  );
  bool saving = false;
  String? errorKey;
  ProductionDestination? destination;
  String? selectedParcel;
  late final Future<List<ProductionDestination>>? destinations =
      widget.production
      ? widget.service.productionDestinations(widget.subject)
      : null;

  @override
  void dispose() {
    quantity.dispose();
    issuePrice.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) {
      return;
    }
    if (widget.production && (destination == null || planId == null)) {
      setState(() => errorKey = 'inventory.destinationRequired');
      return;
    }
    final amount = num.tryParse(quantity.text.trim().replaceAll(',', '.'));
    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() {
        errorKey = 'inventory.invalidQuantity';
      });
      return;
    }
    try {
      ExactDecimal.quantityUnits(amount);
      if (widget.kind == InventoryMovementKind.issue ||
          issuePrice.text.trim().isNotEmpty) {
        if (!canPrice) throw StateError('Admin price required.');
        ExactDecimal.validatePrice(
          issuePrice.text.trim().replaceAll(',', '.'),
          currency ?? '',
        );
        if (ExactDecimal.parse(
                  issuePrice.text.trim().replaceAll(',', '.'),
                ).coefficient ==
                BigInt.zero &&
            !confirmZero) {
          throw StateError('Confirm zero price.');
        }
      }
    } catch (_) {
      setState(() => errorKey = 'planning.priceRequired');
      return;
    }
    setState(() {
      saving = true;
      errorKey = null;
    });
    try {
      final movement = InventoryMovement(
        id: movementId,
        farmId: widget.subject.farmId,
        itemId: widget.item.id,
        warehouseId: widget.warehouseId,
        kind: widget.kind,
        quantity: amount,
        occurredAt: occurredAt,
        zeroPriceConfirmed: confirmZero,
        unitPriceText: issuePrice.text.trim().isEmpty
            ? null
            : issuePrice.text.trim().replaceAll(',', '.'),
        currency: issuePrice.text.trim().isEmpty ? null : currency,
      );
      if (widget.production) {
        await widget.service.recordProductionIssue(
          widget.subject,
          movement,
          parcelId: destination!.parcelId,
          seasonId: destination!.seasonId,
          planId: planId,
        );
      } else {
        await widget.service.record(widget.subject, movement);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          errorKey = 'inventory.movementFailed';
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
        title: Text(
          l10n.text(
            widget.production
                ? 'inventory.productionIssue'
                : 'inventory.${widget.kind.name}',
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.item.code} · ${widget.item.name}'),
                Text(
                  '${l10n.text('inventory.stock')}: ${widget.item.stock} ${widget.item.unit}',
                ),
                if (destinations != null)
                  FutureBuilder<List<ProductionDestination>>(
                    future: destinations,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(l10n.text('inventory.destinationFailed'));
                      }
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      final rows = snapshot.data!;
                      if (rows.isEmpty) {
                        return Text(l10n.text('inventory.noDestinations'));
                      }
                      final parcels = {
                        for (final r in rows) r.parcelId: r.parcelCode,
                      };
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            key: const Key('inventory-production-parcel'),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.text('inventory.parcel'),
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
                                : (id) => setState(() {
                                    selectedParcel = id;
                                    destination = null;
                                    planId = null;
                                  }),
                          ),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'inventory-production-season-$selectedParcel',
                            ),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.text('inventory.season'),
                            ),
                            items: [
                              for (final r in rows.where(
                                (r) => r.parcelId == selectedParcel,
                              ))
                                DropdownMenuItem(
                                  value: r.seasonId,
                                  child: Text(r.seasonName),
                                ),
                            ],
                            onChanged: saving
                                ? null
                                : (id) => setState(() {
                                    planId = null;
                                    destination = rows.firstWhere(
                                      (r) =>
                                          r.parcelId == selectedParcel &&
                                          r.seasonId == id,
                                    );
                                  }),
                          ),
                        ],
                      );
                    },
                  ),
                if (widget.production)
                  FutureBuilder<List<ProductionPlan>>(
                    future: plans,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(l10n.text('planning.loadFailed'));
                      }
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      final available = snapshot.data!.where(
                        (p) =>
                            p.parcelId == selectedParcel &&
                            p.seasonId == destination?.seasonId &&
                            p.status == ProductionPlanStatus.active,
                      );
                      return DropdownButtonFormField<String>(
                        key: ValueKey(
                          'inventory-production-plan-${destination?.seasonId}',
                        ),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.text('planning.plan'),
                        ),
                        items: [
                          for (final p in available)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                '${p.code} · ${p.name} (${p.currency})',
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (id) => setState(() {
                                planId = id;
                                currency = snapshot.data!
                                    .firstWhere((p) => p.id == id)
                                    .currency;
                              }),
                      );
                    },
                  ),
                TextField(
                  key: const Key('inventory-movement-quantity'),
                  controller: quantity,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '${l10n.text('inventory.quantity')} (${widget.item.unit})',
                  ),
                ),
                if (canPrice) ...[
                  TextField(
                    key: const Key('inventory-movement-price'),
                    controller: issuePrice,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.text('planning.adminPrice'),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('inventory-currency-$planId'),
                    initialValue: currency,
                    decoration: InputDecoration(
                      labelText: l10n.text('planning.currency'),
                    ),
                    items: [
                      for (final c in ['VND', 'LAK'])
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: saving || (widget.production && planId != null)
                        ? null
                        : (c) => setState(() => currency = c),
                  ),
                  CheckboxListTile(
                    value: confirmZero,
                    onChanged: saving
                        ? null
                        : (v) => setState(() => confirmZero = v ?? false),
                    title: Text(l10n.text('planning.confirmZero')),
                  ),
                ] else if (widget.kind == InventoryMovementKind.issue)
                  Text(l10n.text('planning.adminOnly')),
                if (errorKey != null)
                  Text(
                    l10n.text(errorKey!),
                    key: const Key('inventory-movement-error'),
                  ),
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
            key: const Key('inventory-movement-save'),
            onPressed:
                saving ||
                    (widget.kind == InventoryMovementKind.issue && !canPrice)
                ? null
                : save,
            child: Text(l10n.text('common.save')),
          ),
        ],
      ),
    );
  }
}
