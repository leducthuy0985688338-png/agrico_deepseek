import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/land_parcel_parent_service.dart';
import '../../domain/entities/land_parcel.dart';

class LandParcelParentScreen extends StatefulWidget {
  const LandParcelParentScreen({
    super.key,
    required this.subject,
    required this.plot,
    required this.service,
  });
  final AuthorizationSubject subject;
  final LandParcel plot;
  final LandParcelParentService service;

  @override
  State<LandParcelParentScreen> createState() => _LandParcelParentScreenState();
}

class _LandParcelParentScreenState extends State<LandParcelParentScreen> {
  late final Future<List<LandParcel>> blocks = widget.service.listBlocks(
    subject: widget.subject,
    plot: widget.plot,
  );
  late String? selectedId = widget.plot.parentBlockId;
  bool saving = false;
  String? errorKey;

  Future<void> _save(List<LandParcel> choices) async {
    if (saving || selectedId == widget.plot.parentBlockId) {
      return;
    }
    LandParcel? target;
    for (final block in choices) {
      if (block.id == selectedId) {
        target = block;
      }
    }
    if (selectedId != null && target == null) {
      return;
    }
    setState(() {
      saving = true;
      errorKey = null;
    });
    try {
      await widget.service.changeParent(
        subject: widget.subject,
        expectedPlot: widget.plot,
        expectedParent: target,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          errorKey = error is ParcelParentException
              ? 'parentRelation.error.${error.code}'
              : 'parentRelation.error.persistence';
        });
      }
    }
  }

  Widget _option(LandParcel? block, AppLocalizations l10n) {
    final selected = selectedId == block?.id;
    return Card(
      child: ListTile(
        key: Key('parent-option-${block?.id ?? 'independent'}'),
        title: Text(
          block == null
              ? l10n.text('parentRelation.independent')
              : '${block.parcelCode} · ${block.name}',
        ),
        selected: selected,
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        onTap: saving
            ? null
            : () => setState(() {
                selectedId = block?.id;
                errorKey = null;
              }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.text('parentRelation.title'))),
        body: FutureBuilder<List<LandParcel>>(
          future: blocks,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Center(
                child: Text(
                  l10n.text(
                    error is ParcelParentException
                        ? 'parentRelation.error.${error.code}'
                        : 'parentRelation.error.persistence',
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final choices = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${widget.plot.parcelCode} · ${widget.plot.name}'),
                const SizedBox(height: 8),
                Text(l10n.text('parentRelation.hint')),
                const SizedBox(height: 8),
                _option(null, l10n),
                ...choices.map((block) => _option(block, l10n)),
                if (choices.isEmpty) Text(l10n.text('parentRelation.noBlocks')),
                if (errorKey != null)
                  Text(
                    l10n.text(errorKey!),
                    key: const Key('parent-relation-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('parent-relation-save'),
                  onPressed: saving || selectedId == widget.plot.parentBlockId
                      ? null
                      : () => _save(choices),
                  child: Text(l10n.text('common.save')),
                ),
                if (saving) const LinearProgressIndicator(),
              ],
            );
          },
        ),
      ),
    );
  }
}
