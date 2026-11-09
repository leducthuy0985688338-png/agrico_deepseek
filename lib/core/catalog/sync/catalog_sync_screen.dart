import 'dart:convert';

import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../company_catalog.dart';
import 'catalog_conflict_decisions.dart';
import 'catalog_restore_reconciliation.dart';
import 'catalog_sync_workspace.dart';

class CatalogSyncScreen extends StatefulWidget {
  const CatalogSyncScreen({super.key, required this.actions});
  final CatalogSyncActions actions;
  @override
  State<CatalogSyncScreen> createState() => _CatalogSyncScreenState();
}

class _CatalogSyncScreenState extends State<CatalogSyncScreen> {
  CatalogSyncStatus? status;
  CatalogRestoreReview? restoreReview;
  final selected = <String>{};
  bool busy = false;
  String? message;
  String t(String key) => AppLocalizations.of(context).text('catalogSync.$key');
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    widget.actions.dispose();
    super.dispose();
  }

  Future<void> reload() => act(() async {}, invalidate: true, success: null);
  Future<void> act(
    Future<void> Function() action, {
    bool invalidate = true,
    String? success = 'saved',
  }) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
      if (invalidate) {
        restoreReview = null;
        selected.clear();
      }
    });
    try {
      await action();
      final fresh = await widget.actions.load();
      if (!mounted) {
        return;
      }
      setState(() {
        status = fresh;
        if (success != null) {
          message = t(success);
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      final key = e is CatalogFailure ? e.code : '';
      final localized = AppLocalizations.of(context).text(key);
      setState(() {
        message = key.isNotEmpty && localized != key ? localized : t('failed');
      });
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<String?> reason(String title) => showDialog<String>(
    context: context,
    builder: (_) => _CatalogSyncReasonDialog(title: title),
  );

  Future<void> reviewed(
    String title,
    Future<void> Function(String) action,
  ) async {
    if (busy) {
      return;
    }
    final value = await reason(title);
    if (!mounted || value == null) {
      return;
    }
    await act(() => action(value));
  }

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
  String label(String key) {
    final local = status?.labels[key];
    if (local != null) {
      return local;
    }
    final r = restoreReview;
    if (r != null) {
      final manifest = jsonDecode(r.remoteJson) as Map;
      final item = manifest[key] as Map?;
      final payload = item?['payload'] as Map?;
      if (payload != null) {
        return '${payload['code']} · ${payload['name']}';
      }
    }
    return key;
  }

  String recordType(String key) => AppLocalizations.of(context).text(
    key.startsWith('entry/') ? 'catalog.entries' : 'catalog.requests',
  );

  Widget restoreRecord(String key) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label(key)),
    subtitle: Text('${recordType(key)}\n$key'),
    isThreeLine: true,
  );

  Widget preview(String title, String? json) {
    final data = json == null
        ? null
        : (jsonDecode(json) as Map).cast<String, Object?>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            if (data == null)
              Text(t('absent'))
            else ...[
              Text('${data['code']} · ${data['name']}'),
              Text(
                AppLocalizations.of(
                  context,
                ).text('catalog.kind.${data['kind']}'),
              ),
              if (data['active'] != null)
                Text(t(data['active'] == 1 ? 'active' : 'inactive')),
              if (data['unit_id'] != null)
                Text(label('entry/${data['unit_id']}')),
              if (data['status'] != null)
                Text(
                  AppLocalizations.of(
                    context,
                  ).text('catalog.status.${data['status']}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget conflict(CatalogConflictReview r) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label('${r.entity}/${r.targetId}')),
          preview(t('local'), r.localJson),
          preview(t('remote'), r.remoteJson),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => reviewed(
                        t('acceptRemote'),
                        (why) => widget.actions.decide(
                          r,
                          CatalogConflictChoice.acceptRemote,
                          why,
                        ),
                      ),
                child: Text(t('acceptRemote')),
              ),
              if (r.entity == 'entry' &&
                  r.localJson != null &&
                  !status!.restoreBlocked)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => reviewed(
                          t('keepLocal'),
                          (why) => widget.actions.decide(
                            r,
                            CatalogConflictChoice.keepLocal,
                            why,
                          ),
                        ),
                  child: Text(t('keepLocal')),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  List<Widget> restoreWidgets(CatalogSyncStatus s) {
    final r = restoreReview;
    return [
      heading(t('restoreBlocked')),
      Text('${t('farmUnresolved')}: ${s.farmUnresolved}'),
      OutlinedButton(
        key: const Key('catalog-sync-review-restore'),
        onPressed: busy
            ? null
            : () => act(() async {
                restoreReview = null;
                selected.clear();
                final review = await widget.actions.reviewRestore();
                if (mounted) {
                  restoreReview = review;
                  selected.clear();
                }
              }, invalidate: false),
        child: Text(t('reviewRestore')),
      ),
      if (r != null) ...[
        Text('${t('matched')}: ${r.matched}'),
        heading('${t('divergent')}: ${r.divergent.length}'),
        ...r.divergent.map(restoreRecord),
        heading('${t('remoteOnly')}: ${r.remoteOnly.length}'),
        ...r.remoteOnly.map(restoreRecord),
        heading(t('localOnly')),
        ...r.localOnly.map(
          (k) => CheckboxListTile(
            key: Key('catalog-sync-retain-$k'),
            subtitle: Text('${recordType(k)}\n$k'),
            isThreeLine: true,
            contentPadding: EdgeInsets.zero,
            title: Text(label(k)),
            value: selected.contains(k),
            onChanged: busy
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      selected.add(k);
                    } else {
                      selected.remove(k);
                    }
                  }),
          ),
        ),
        OutlinedButton(
          key: const Key('catalog-sync-release-restore'),
          onPressed:
              busy ||
                  r.divergent.isNotEmpty ||
                  r.remoteOnly.isNotEmpty ||
                  selected.length != r.localOnly.length ||
                  s.farmUnresolved != 0 ||
                  s.conflicts.isNotEmpty
              ? null
              : () {
                  final keep = Set<String>.of(selected);
                  reviewed(
                    t('releaseRestore'),
                    (why) => widget.actions.releaseRestore(r, why, keep),
                  );
                },
          child: Text(t('releaseRestore')),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('title')),
        actions: [
          IconButton(
            tooltip: t('refresh'),
            onPressed: busy ? null : reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('notice')),
          if (busy) const LinearProgressIndicator(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(message!, key: const Key('catalog-sync-message')),
            ),
          if (s != null) ...[
            ...['pending', 'acked', 'blocked', 'conflict'].map(
              (key) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${t(key)}: ${s.counts[key] ?? 0}'),
              ),
            ),
            ElevatedButton(
              key: const Key('catalog-sync-run'),
              onPressed: busy
                  ? null
                  : () => act(() async {
                      final complete = await widget.actions.synchronize();
                      if (mounted) {
                        message = t(complete ? 'complete' : 'incomplete');
                      }
                    }, success: null),
              child: Text(t('synchronize')),
            ),
            if (s.restoreBlocked) ...[
              if (s.canManage)
                ...restoreWidgets(s)
              else
                Text(t('restoreBlocked')),
            ],
            if (s.canManage) ...[
              heading(t('conflicts')),
              if (s.conflicts.isEmpty) Text(t('empty')),
              ...s.conflicts.map(conflict),
              if (!s.restoreBlocked) ...[
                heading(t('unpublished')),
                Text(t('prepareNotice')),
                if (s.unpublished.isEmpty) Text(t('empty')),
                ...s.unpublished.map(
                  (r) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          preview(t('local'), r.payloadJson),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => reviewed(
                                    '${t('prepare')}: ${label('entry/${r.targetId}')}',
                                    (why) => widget.actions.prepare(r, why),
                                  ),
                            child: Text(t('prepare')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// Owns the controller until the dialog route has finished its closing animation.
class _CatalogSyncReasonDialog extends StatefulWidget {
  const _CatalogSyncReasonDialog({required this.title});
  final String title;
  @override
  State<_CatalogSyncReasonDialog> createState() =>
      _CatalogSyncReasonDialogState();
}

class _CatalogSyncReasonDialogState extends State<_CatalogSyncReasonDialog> {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  String t(String key) => AppLocalizations.of(context).text('catalogSync.$key');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: TextFormField(
          key: const Key('catalog-sync-reason'),
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          decoration: InputDecoration(labelText: t('reason')),
          validator: (v) =>
              (v ?? '').trim().isEmpty || (v ?? '').trim().length > 500
              ? t('reasonRequired')
              : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('cancel')),
      ),
      TextButton(
        key: const Key('catalog-sync-confirm'),
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: Text(t('confirm')),
      ),
    ],
  );
}
