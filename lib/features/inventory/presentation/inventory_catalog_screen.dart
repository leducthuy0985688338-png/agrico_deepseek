import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../application/inventory_service.dart';
import '../domain/entities/inventory_item.dart';

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
            onPressed: reload,
            tooltip: l10n.text('common.retry'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: canManage
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
