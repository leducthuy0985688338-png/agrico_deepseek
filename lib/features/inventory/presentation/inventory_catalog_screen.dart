import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../application/inventory_service.dart';
import '../domain/entities/inventory_item.dart';
import 'inventory_history_screen.dart';

class InventoryCatalogScreen extends StatefulWidget {
  const InventoryCatalogScreen({
    super.key,
    required this.subject,
    required this.service,
  });

  final AuthorizationSubject subject;
  final InventoryService service;

  @override
  State<InventoryCatalogScreen> createState() => _InventoryCatalogScreenState();
}

class _InventoryCatalogScreenState extends State<InventoryCatalogScreen> {
  late Future<List<InventoryItem>> items;

  @override
  void initState() {
    super.initState();
    items = widget.service.list(widget.subject);
  }

  void reload() {
    setState(() {
      items = widget.service.list(widget.subject);
    });
  }

  Future<void> add() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _AddItemDialog(subject: widget.subject, service: widget.service),
    );
    if (saved == true && mounted) {
      reload();
    }
  }

  Future<void> record(InventoryItem item, InventoryMovementKind kind) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MovementDialog(
        subject: widget.subject,
        service: widget.service,
        item: item,
        kind: kind,
      ),
    );
    if (saved == true && mounted) {
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canManage =
        widget.subject.active &&
        widget.subject.permissionCodes.contains(
          PermissionCodes.inventoryManage,
        ) &&
        widget.subject.dataScopes.contains(DataScope.allFarm);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.warehouse')),
        actions: [
          IconButton(
            key: const Key('inventory-history-open'),
            tooltip: l10n.text('inventory.history'),
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InventoryHistoryScreen(
                  subject: widget.subject,
                  service: widget.service,
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
            return Center(child: Text(l10n.text('common.empty')));
          }
          return ListView.builder(
            key: const Key('inventory-list'),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final item = snapshot.data![index];
              return ListTile(
                title: Text('${item.code} · ${item.name}'),
                trailing: canManage
                    ? PopupMenuButton<InventoryMovementKind>(
                        key: Key('inventory-actions-${item.id}'),
                        onSelected: (kind) => record(item, kind),
                        itemBuilder: (_) => [
                          for (final kind in InventoryMovementKind.values)
                            PopupMenuItem(
                              key: Key('inventory-${kind.name}-${item.id}'),
                              value: kind,
                              child: Text(l10n.text('inventory.${kind.name}')),
                            ),
                        ],
                      )
                    : null,
                subtitle: Text(
                  '${l10n.text('inventory.stock')}: '
                  '${item.stock} ${item.unit}',
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
  const _AddItemDialog({required this.subject, required this.service});

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
    setState(() {
      saving = true;
      failed = false;
    });
    try {
      await widget.service.register(
        widget.subject,
        InventoryItem(
          id:
              'inventory-${DateTime.now().microsecondsSinceEpoch}-'
              '${Random.secure().nextInt(1 << 32)}',
          farmId: widget.subject.farmId,
          code: code.text.trim(),
          name: name.text.trim(),
          unit: unit.text.trim(),
          unitPrice: double.parse(price.text.trim()),
          supplier: supplier.text.trim(),
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
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
      title: Text(l10n.text('inventory.add')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('inventory-code'),
                controller: code,
                decoration: InputDecoration(
                  labelText: l10n.text('inventory.code'),
                ),
              ),
              TextField(
                key: const Key('inventory-name'),
                controller: name,
                decoration: InputDecoration(
                  labelText: l10n.text('inventory.name'),
                ),
              ),
              TextField(
                key: const Key('inventory-unit'),
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
              if (failed) Text(l10n.text('inventory.saveFailed')),
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
  });

  final AuthorizationSubject subject;
  final InventoryService service;
  final InventoryItem item;
  final InventoryMovementKind kind;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final quantity = TextEditingController();
  bool saving = false;
  String? errorKey;

  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) {
      return;
    }
    final amount = int.tryParse(quantity.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        errorKey = 'inventory.invalidQuantity';
      });
      return;
    }
    setState(() {
      saving = true;
      errorKey = null;
    });
    try {
      await widget.service.record(
        widget.subject,
        InventoryMovement(
          id:
              'inventory-movement-${DateTime.now().microsecondsSinceEpoch}-'
              '${Random.secure().nextInt(1 << 32)}',
          farmId: widget.subject.farmId,
          itemId: widget.item.id,
          kind: widget.kind,
          quantity: amount,
          occurredAt: DateTime.now().toUtc(),
        ),
      );
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
        title: Text(l10n.text('inventory.${widget.kind.name}')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.item.code} · ${widget.item.name}'),
            Text(
              '${l10n.text('inventory.stock')}: ${widget.item.stock} ${widget.item.unit}',
            ),
            TextField(
              key: const Key('inventory-movement-quantity'),
              controller: quantity,
              enabled: !saving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    '${l10n.text('inventory.quantity')} (${widget.item.unit})',
              ),
            ),
            if (errorKey != null)
              Text(
                l10n.text(errorKey!),
                key: const Key('inventory-movement-error'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l10n.text('common.cancel')),
          ),
          FilledButton(
            key: const Key('inventory-movement-save'),
            onPressed: saving ? null : save,
            child: Text(l10n.text('common.save')),
          ),
        ],
      ),
    );
  }
}
