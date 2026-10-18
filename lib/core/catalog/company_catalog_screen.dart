import 'dart:math';
import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';
import 'company_catalog.dart';

String _id() =>
    'catalog-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

class CompanyCatalogScreen extends StatefulWidget {
  const CompanyCatalogScreen({
    super.key,
    required this.service,
    this.initialKind = CatalogKind.unit,
  });
  final CatalogKind initialKind;
  final CompanyCatalogService service;
  @override
  State<CompanyCatalogScreen> createState() => _CompanyCatalogScreenState();
}

class _CompanyCatalogScreenState extends State<CompanyCatalogScreen> {
  late CatalogKind kind = widget.initialKind;
  late Future<(List<CatalogEntry>, List<CatalogRequest>)> data = load();
  Future<(List<CatalogEntry>, List<CatalogRequest>)> load() async => (
    await widget.service.entries(),
    widget.service.canManage || widget.service.canRequest
        ? await widget.service.requests()
        : <CatalogRequest>[],
  );
  void reload() {
    final next = load();
    setState(() {
      data = next;
    });
  }

  Future<void> edit(
    List<CatalogEntry> entries, {
    CatalogEntry? entry,
    bool request = false,
  }) async {
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => _CatalogEditor(
        service: widget.service,
        entries: entries,
        kind: kind,
        entry: entry,
        request: request,
      ),
    );
    final saved = await Navigator.of(context).push(route);
    await route.completed;
    if (saved == true && mounted) reload();
  }

  Future<void> resolve(
    CatalogRequest request,
    List<CatalogEntry> entries,
  ) async {
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => _ResolveRequest(
        service: widget.service,
        request: request,
        entries: entries,
      ),
    );
    final saved = await Navigator.of(context).push(route);
    await route.completed;
    if (saved == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.text('catalog.title')),
          actions: [
            IconButton(
              key: const Key('company-catalog-refresh'),
              onPressed: reload,
              icon: const Icon(Icons.refresh),
              tooltip: l.text('common.retry'),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l.text('catalog.entries')),
              Tab(text: l.text('catalog.requests')),
            ],
          ),
        ),
        body: FutureBuilder<(List<CatalogEntry>, List<CatalogRequest>)>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(l.text('catalog.loadFailed')));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (entries, requests) = snapshot.data!;
            final matching = entries.where((e) => e.kind == kind).toList();
            return TabBarView(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<CatalogKind>(
                        isExpanded: true,
                        key: const Key('company-catalog-kind'),
                        initialValue: kind,
                        decoration: InputDecoration(
                          labelText: l.text('catalog.kind'),
                        ),
                        items: [
                          for (final k in CatalogKind.values)
                            DropdownMenuItem(
                              value: k,
                              child: Text(
                                l.text('catalog.kind.${k.name}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => kind = v);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(l.text('catalog.offlineNotice')),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (widget.service.canManage)
                          FilledButton.icon(
                            key: const Key('company-catalog-add'),
                            onPressed: () => edit(entries),
                            icon: const Icon(Icons.add),
                            label: Text(l.text('catalog.add')),
                          ),
                        if (widget.service.canRequest)
                          OutlinedButton.icon(
                            key: const Key('company-catalog-request'),
                            onPressed: () => edit(entries, request: true),
                            icon: const Icon(Icons.send_outlined),
                            label: Text(l.text('catalog.request')),
                          ),
                      ],
                    ),
                    Expanded(
                      child: matching.isEmpty
                          ? Center(child: Text(l.text('catalog.empty')))
                          : ListView.builder(
                              itemCount: matching.length,
                              itemBuilder: (context, i) {
                                final e = matching[i];
                                final units = entries.where(
                                  (u) => u.id == e.unitId,
                                );
                                return ListTile(
                                  key: Key('company-catalog-entry-${e.id}'),
                                  title: Text('${e.code} · ${e.name}'),
                                  subtitle: Text(
                                    [
                                      if (units.isNotEmpty) units.single.name,
                                      l.text(
                                        e.active
                                            ? 'catalog.active'
                                            : 'catalog.inactive',
                                      ),
                                    ].join(' · '),
                                  ),
                                  trailing: widget.service.canManage
                                      ? const Icon(Icons.edit_outlined)
                                      : null,
                                  onTap: widget.service.canManage
                                      ? () => edit(entries, entry: e)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
                requests.isEmpty
                    ? Center(child: Text(l.text('common.empty')))
                    : ListView.builder(
                        itemCount: requests.length,
                        itemBuilder: (context, i) {
                          final r = requests[i];
                          return ListTile(
                            key: Key('catalog-request-${r.id}'),
                            title: Text('${r.code} · ${r.name}'),
                            subtitle: Text(
                              '${l.text('catalog.kind.${r.kind.name}')} · ${l.text('catalog.status.${r.status}')}\n${r.reason}${r.resolution == null ? '' : '\n${r.resolution}'}',
                            ),
                            trailing:
                                widget.service.canManage &&
                                    r.status == 'pending'
                                ? const Icon(Icons.rule)
                                : null,
                            onTap:
                                widget.service.canManage &&
                                    r.status == 'pending'
                                ? () => resolve(r, entries)
                                : null,
                          );
                        },
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({
    required this.service,
    required this.entries,
    required this.kind,
    this.entry,
    this.request = false,
  });
  final CompanyCatalogService service;
  final List<CatalogEntry> entries;
  final CatalogKind kind;
  final CatalogEntry? entry;
  final bool request;
  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  late final code = TextEditingController(text: widget.entry?.code);
  late final name = TextEditingController(text: widget.entry?.name);
  final reason = TextEditingController();
  late String? unitId = widget.entry?.unitId;
  late bool active = widget.entry?.active ?? true;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    name.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.request) {
        await widget.service.request(
          id: _id(),
          kind: widget.kind,
          code: code.text,
          name: name.text,
          reason: reason.text,
        );
      } else {
        final entry = CatalogEntry(
          id: widget.entry?.id ?? _id(),
          farmId: widget.service.subject.farmId,
          kind: widget.kind,
          code: widget.entry?.code ?? '',
          name: name.text.trim(),
          unitId: unitId,
          active: active,
        );
        if (widget.entry == null) {
          await widget.service.create(entry, reason: reason.text);
        } else {
          await widget.service.save(
            entry,
            expectedRevision: widget.entry!.revision,
            reason: reason.text,
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is CatalogFailure ? e.code : 'catalog.saveFailed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final units = widget.entries.where(
      (e) => e.kind == CatalogKind.unit && (e.active || e.id == unitId),
    );
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(
          l.text(widget.request ? 'catalog.request' : 'catalog.edit'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.text('catalog.kind.${widget.kind.name}')),
                if (widget.entry != null || widget.request)
                  TextField(
                    key: const Key('company-catalog-code'),
                    controller: code,
                    enabled: !saving && widget.entry == null,
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: l.text('catalog.code'),
                    ),
                  ),
                if (widget.entry == null && !widget.request)
                  Text("${l.text('catalog.code')}: auto"),
                TextField(
                  key: const Key('company-catalog-name'),
                  controller: name,
                  enabled: !saving,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: l.text('catalog.name'),
                  ),
                ),
                if (!widget.request && widget.kind != CatalogKind.unit)
                  DropdownButtonFormField<String>(
                    key: const Key('company-catalog-unit'),
                    isExpanded: true,
                    initialValue: unitId,
                    decoration: InputDecoration(
                      labelText: l.text('catalog.kind.unit'),
                    ),
                    items: [
                      for (final u in units)
                        DropdownMenuItem(
                          value: u.id,
                          child: Tooltip(
                            message: '${u.name} (${u.code})',
                            child: Text(
                              '${u.name} (${u.code})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => setState(() => unitId = v),
                  ),
                if (!widget.request)
                  SwitchListTile(
                    title: Text(l.text('catalog.active')),
                    value: active,
                    onChanged: saving
                        ? null
                        : (v) => setState(() => active = v),
                  ),
                TextField(
                  key: const Key('company-catalog-reason'),
                  controller: reason,
                  enabled: !saving,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: l.text('catalog.reason'),
                  ),
                ),
                if (error != null)
                  Text(
                    l.text(error!),
                    key: const Key('company-catalog-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l.text('common.cancel')),
          ),
          FilledButton(
            key: const Key('company-catalog-save'),
            onPressed: saving ? null : save,
            child: Text(l.text(saving ? 'catalog.saving' : 'common.save')),
          ),
        ],
      ),
    );
  }
}

class _ResolveRequest extends StatefulWidget {
  const _ResolveRequest({
    required this.service,
    required this.request,
    required this.entries,
  });
  final CompanyCatalogService service;
  final CatalogRequest request;
  final List<CatalogEntry> entries;
  @override
  State<_ResolveRequest> createState() => _ResolveRequestState();
}

class _ResolveRequestState extends State<_ResolveRequest> {
  String? entryId, error;
  final reason = TextEditingController();
  late final TextEditingController name;
  String? unitId;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.request.name);
    reason.text = widget.request.reason;
    for (final e in widget.entries) {
      if (e.active &&
          e.kind == widget.request.kind &&
          (e.code == widget.request.code ||
              e.name.toUpperCase() == widget.request.name.toUpperCase())) {
        entryId = e.id;
        break;
      }
    }
  }

  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> resolve(bool approve) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.service.resolve(
        widget.request.id,
        entryId: approve ? entryId : null,
        createEntry: approve && entryId == null
            ? CatalogEntry(
                id: 'catalog-${DateTime.now().microsecondsSinceEpoch}',
                farmId: widget.service.subject.farmId,
                kind: widget.request.kind,
                code: '',
                name: name.text.trim(),
                unitId: widget.request.kind == CatalogKind.unit ? null : unitId,
              )
            : null,
        reason: reason.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is CatalogFailure ? e.code : 'catalog.saveFailed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(l.text('catalog.resolve')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.request.code} · ${widget.request.name}'),
              Text(widget.request.reason),
              Text(l.text('catalog.approveHint')),
              DropdownButtonFormField<String>(
                key: const Key('catalog-resolve-entry'),
                isExpanded: true,
                initialValue: entryId ?? '',
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(
                      l.text('catalog.createFromRequest'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final e in widget.entries.where(
                    (e) => e.kind == widget.request.kind && e.active,
                  ))
                    DropdownMenuItem(
                      value: e.id,
                      child: Tooltip(
                        message: '${e.name} (${e.code})',
                        child: Text(
                          '${e.name} (${e.code})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (v) => setState(() => entryId = v == '' ? null : v),
              ),
              if (entryId == null) ...[
                Text(
                  'Mã danh mục mới sẽ được hệ thống cấp tự động khi phê duyệt.',
                ),
                TextField(
                  key: const Key('catalog-approval-name'),
                  controller: name,
                  enabled: !saving,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: l.text('catalog.name'),
                  ),
                ),
                if (widget.request.kind != CatalogKind.unit)
                  DropdownButtonFormField<String>(
                    key: const Key('catalog-approval-unit'),
                    isExpanded: true,
                    initialValue: unitId,
                    decoration: InputDecoration(
                      labelText: l.text('catalog.kind.unit'),
                    ),
                    items: [
                      for (final u in widget.entries.where(
                        (e) => e.kind == CatalogKind.unit && e.active,
                      ))
                        DropdownMenuItem(
                          value: u.id,
                          child: Text(
                            '${u.name} (${u.code})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => setState(() => unitId = v),
                  ),
              ],
              TextField(
                key: const Key('catalog-resolve-reason'),
                controller: reason,
                enabled: !saving,
                decoration: InputDecoration(
                  labelText: l.text('catalog.reason'),
                ),
                maxLength: 500,
              ),
              if (error != null)
                Text(l.text(error!), key: const Key('catalog-resolve-error')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l.text('common.cancel')),
          ),
          TextButton(
            key: const Key('catalog-reject'),
            onPressed: saving ? null : () => resolve(false),
            child: Text(l.text('catalog.reject')),
          ),
          FilledButton(
            key: const Key('catalog-approve'),
            onPressed: saving ? null : () => resolve(true),
            child: Text(l.text('catalog.approve')),
          ),
        ],
      ),
    );
  }
}
