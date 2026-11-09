import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';
import 'company_catalog.dart';

/// Select a canonical value; a historical snapshot may only be retained unchanged.
class CatalogValuePicker extends StatefulWidget {
  const CatalogValuePicker({
    super.key,
    required this.service,
    required this.kind,
    required this.controller,
    required this.label,
    this.originalValue,
    this.allowEmpty = false,
    this.onSelected,
  });
  final CompanyCatalogService service;
  final CatalogKind kind;
  final TextEditingController controller;
  final String label;
  final String? originalValue;
  final bool allowEmpty;
  final VoidCallback? onSelected;
  @override
  State<CatalogValuePicker> createState() => _CatalogValuePickerState();
}

class _CatalogValuePickerState extends State<CatalogValuePicker> {
  late final Future<List<CatalogEntry>> entries = widget.service.entries();
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<List<CatalogEntry>>(
      future: entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(l.text('catalog.loadFailed'));
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final choices = {
          for (final e in snapshot.data!.where(
            (e) => e.kind == widget.kind && e.active,
          ))
            e.name: '${e.name} (${e.code})',
        };
        final original = widget.originalValue;
        if (original != null &&
            original.isNotEmpty &&
            !choices.containsKey(original)) {
          choices[original] = '$original · ${l.text('catalog.historical')}';
        }
        final selected = choices.containsKey(widget.controller.text)
            ? widget.controller.text
            : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('${widget.kind.name}-$selected'),
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(labelText: widget.label),
              items: [
                if (widget.allowEmpty)
                  DropdownMenuItem(
                    value: '',
                    child: Text(l.text('catalog.none')),
                  ),
                for (final e in choices.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                setState(() => widget.controller.text = v ?? '');
                widget.onSelected?.call();
              },
            ),
            if (choices.isEmpty) Text(l.text('catalog.empty')),
          ],
        );
      },
    );
  }
}
