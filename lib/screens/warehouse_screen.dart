import 'package:flutter/material.dart';

/// Legacy route retained temporarily while the old dashboard is retired.
/// Inventory writes are only available through the authorized V2 warehouse.
@Deprecated('Use InventoryCatalogScreen through the V2 composition.')
class WarehouseScreen extends StatelessWidget {
  const WarehouseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: _LegacyWarehouseAppBar(),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Kho cũ đã ngừng hoạt động. Vui lòng mở Kho trong AGRICO V2 '
            'để quản lý danh mục vật tư, nhập kho và xuất kho.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _LegacyWarehouseAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _LegacyWarehouseAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const Text('Kho'));
}
