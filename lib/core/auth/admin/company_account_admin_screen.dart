import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../permissions/authorization.dart';
import '../../permissions/company_roles.dart';
import '../company_membership.dart';
import 'company_account_admin_service.dart';

class CompanyAccountAdminScreen extends StatefulWidget {
  const CompanyAccountAdminScreen({
    super.key,
    required this.service,
    this.loadScopeOptions,
  });
  final Future<Map<String, Map<String, String>>> Function()? loadScopeOptions;
  final CompanyAccountAdminService service;
  @override
  State<CompanyAccountAdminScreen> createState() =>
      _CompanyAccountAdminScreenState();
}

class _CompanyAccountAdminScreenState extends State<CompanyAccountAdminScreen> {
  List<CompanyAccountRecord> records = [];
  bool busy = false;
  String? error;
  String t(String key) => AppLocalizations.of(context).text('accounts.$key');
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
      records = [];
    });
    try {
      final values = await widget.service.list();
      values.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (mounted) {
        setState(() => records = values);
      }
    } on AccountAdminFailure catch (e) {
      if (mounted) {
        setState(() => error = e.code);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'invalid');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _edit(CompanyAccountRecord? record) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AccountEditor(
          service: widget.service,
          original: record,
          loadScopeOptions: widget.loadScopeOptions,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _load();
    }
  }

  Future<void> _audit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final entries = await widget.service.audit();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(t('audit'))),
            body: ListView(
              children: [
                for (final entry in entries)
                  ListTile(
                    title: Text(entry.reason),
                    subtitle: Text(
                      '${entry.actorUid} → ${entry.targetUid}\n'
                      '${entry.occurredAt.toLocal()} · #${entry.revision}',
                    ),
                    isThreeLine: true,
                  ),
              ],
            ),
          ),
        ),
      );
    } on AccountAdminFailure catch (e) {
      if (mounted) {
        setState(() => error = e.code);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'invalid');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('title')),
      actions: [
        IconButton(
          onPressed: busy ? null : _audit,
          tooltip: t('audit'),
          icon: const Icon(Icons.history),
        ),
        IconButton(
          onPressed: busy ? null : _load,
          tooltip: t('refresh'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t('onlineHint')),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t('error.$error')),
                ),
              if (records.isEmpty && error == null)
                ListTile(title: Text(t('empty'))),
              for (final record in records)
                ListTile(
                  key: ValueKey('account-${record.uid}'),
                  title: Text(record.displayName),
                  subtitle: Text(
                    '${record.uid}\n${record.membership.profile.roles.map((r) => t('role.${r.role.name}')).join(', ')}',
                  ),
                  isThreeLine: true,
                  leading: Icon(
                    record.membership.profile.active
                        ? Icons.person
                        : Icons.person_off,
                  ),
                  onTap: () => _edit(record),
                ),
            ],
          ),
    floatingActionButton: busy
        ? null
        : FloatingActionButton.extended(
            key: const Key('account-add'),
            onPressed: () => _edit(null),
            icon: const Icon(Icons.person_add),
            label: Text(t('add')),
          ),
  );
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({
    required this.service,
    this.original,
    this.loadScopeOptions,
  });
  final Future<Map<String, Map<String, String>>> Function()? loadScopeOptions;
  final CompanyAccountAdminService service;
  final CompanyAccountRecord? original;
  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController uid, name;
  final reason = TextEditingController();
  final ids = <String, TextEditingController>{};
  Map<String, Map<String, String>> scopeOptions = {};
  Future<void> loadScopeOptions() async {
    try {
      final options = await widget.loadScopeOptions?.call();
      if (mounted && options != null) setState(() => scopeOptions = options);
    } catch (_) {
      /* Existing IDs remain editable if the local directory is unavailable. */
    }
  }

  final roles = <CompanyRole, Set<DataScope>>{};
  final extras = <String>{}, denies = <String>{};
  final extraScopes = <DataScope>{};
  late bool active;
  late DateTime deadline;
  bool saving = false;
  String? error;
  bool get self => widget.original?.uid == widget.service.subject.userId;
  String t(String key) => AppLocalizations.of(context).text('accounts.$key');
  @override
  void initState() {
    super.initState();
    final original = widget.original;
    final profile = original?.membership.profile;
    uid = TextEditingController(text: original?.uid ?? '');
    name = TextEditingController(text: original?.displayName ?? '');
    active = profile?.active ?? true;
    deadline =
        original?.membership.offlineUntil ??
        DateTime.now().toUtc().add(const Duration(days: 7));
    for (final role in profile?.roles ?? <RoleAssignment>[]) {
      roles[role.role] = {...role.scopes};
    }
    extras.addAll(profile?.extraPermissions ?? {});
    denies.addAll(profile?.deniedPermissions ?? {});
    extraScopes.addAll(profile?.extraPermissionScopes ?? {});
    final values = <String, Set<String>>{
      'projectIds': profile?.projectIds ?? {},
      'departmentIds': profile?.departmentIds ?? {},
      'teamIds': profile?.teamIds ?? {},
      'fieldIds': profile?.fieldIds ?? {},
      'taskIds': profile?.taskIds ?? {},
      'machineIds': profile?.machineIds ?? {},
      'warehouseIds': profile?.warehouseIds ?? {},
    };
    for (final entry in values.entries) {
      ids[entry.key] = TextEditingController(text: entry.value.join(', '));
    }
    loadScopeOptions();
  }

  @override
  void dispose() {
    uid.dispose();
    name.dispose();
    reason.dispose();
    for (final c in ids.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget scopes(Set<DataScope> selected) => Wrap(
    spacing: 8,
    children: [
      for (final scope in DataScope.values)
        FilterChip(
          label: Text(t('scope.${scope.name}')),
          selected: selected.contains(scope),
          onSelected: saving || self
              ? null
              : (enabled) => setState(() {
                  if (enabled) {
                    selected.add(scope);
                  } else {
                    selected.remove(scope);
                  }
                }),
        ),
    ],
  );
  Future<void> _date() async {
    final now = DateTime.now();
    final initial = deadline.toLocal().isBefore(now) ? now : deadline.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: initial.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(deadline.toLocal()),
    );
    if (time != null && mounted) {
      setState(
        () => deadline = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ).toUtc(),
      );
    }
  }

  Set<String> values(String key) => ids[key]!.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  Future<void> _save() async {
    if (!form.currentState!.validate() || saving || self) {
      return;
    }
    late final CompanyAccountRecord record;
    try {
      final profile = CompanyAccessProfile(
        userId: uid.text.trim(),
        membershipId: uid.text.trim(),
        farmId: widget.service.subject.farmId,
        active: active,
        roles: [
          for (final e in roles.entries) RoleAssignment(e.key, scopes: e.value),
        ],
        extraPermissions: extras,
        deniedPermissions: denies,
        extraPermissionScopes: extraScopes,
        projectIds: values('projectIds'),
        departmentIds: values('departmentIds'),
        teamIds: values('teamIds'),
        fieldIds: values('fieldIds'),
        taskIds: values('taskIds'),
        machineIds: values('machineIds'),
        warehouseIds: values('warehouseIds'),
        offlineValidUntil: deadline,
      );
      record = CompanyAccountRecord(
        displayName: name.text.trim(),
        membership: CompanyMembership(profile: profile, offlineUntil: deadline),
      );
      widget.service.validate(record: record, reason: reason.text);
    } on AccountAdminFailure catch (e) {
      setState(() => error = e.code);
      return;
    } on FormatException {
      setState(() => error = 'invalid');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('confirm')),
        content: SingleChildScrollView(
          child: Text(
            '${name.text.trim()}\n${uid.text.trim()}\n'
            '${roles.keys.map((r) => t('role.${r.name}')).join(', ')}\n'
            '${t(active ? 'active' : 'locked')}\n${deadline.toLocal()}\n'
            '${t('extras')}: ${extras.length} · ${t('denies')}: ${denies.length}\n'
            '${reason.text.trim()}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.service.save(
        record: record,
        expectedRevision: widget.original?.revision,
        reason: reason.text,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on AccountAdminFailure catch (e) {
      if (mounted) {
        setState(() => error = e.code);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'invalid');
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: Text(t(widget.original == null ? 'add' : 'edit'))),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(t(self ? 'selfHint' : 'createHint')),
            TextFormField(
              key: const Key('account-uid'),
              controller: uid,
              enabled: widget.original == null && !saving,
              decoration: InputDecoration(labelText: t('uid')),
              validator: (v) =>
                  v == null ||
                      !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(v.trim())
                  ? t('error.invalid')
                  : null,
            ),
            TextFormField(
              key: const Key('account-name'),
              controller: name,
              enabled: !saving && !self,
              decoration: InputDecoration(labelText: t('name')),
              maxLength: 100,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? t('error.invalid') : null,
            ),
            SwitchListTile(
              title: Text(t('active')),
              value: active,
              onChanged: saving || self
                  ? null
                  : (v) => setState(() => active = v),
            ),
            ListTile(
              title: Text(t('deadline')),
              subtitle: Text(deadline.toLocal().toString()),
              trailing: const Icon(Icons.calendar_month),
              onTap: saving || self ? null : _date,
            ),
            Text(t('roles')),
            Text(t('roleLimit')),
            for (final role in CompanyRole.values)
              ExpansionTile(
                title: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('role.${role.name}')),
                  value: roles.containsKey(role),
                  onChanged: saving || self
                      ? null
                      : (enabled) => setState(() {
                          if (enabled == true) {
                            roles[role] = {
                              ...CompanyRolePolicy.defaultScopes(role),
                            };
                          } else {
                            roles.remove(role);
                          }
                        }),
                ),
                children: [
                  if (roles.containsKey(role))
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: scopes(roles[role]!),
                    ),
                ],
              ),
            ExpansionTile(
              title: Text(t('assignments')),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(t('idsHint')),
                ),
                for (final e in ids.entries)
                  if (scopeOptions.containsKey(e.key))
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t(e.key)),
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final id in {
                                ...scopeOptions[e.key]!.keys,
                                ...e.value.text
                                    .split(',')
                                    .map((v) => v.trim())
                                    .where((v) => v.isNotEmpty),
                              })
                                FilterChip(
                                  label: Text(scopeOptions[e.key]![id] ?? id),
                                  selected: values(e.key).contains(id),
                                  onSelected: saving || self
                                      ? null
                                      : (selected) => setState(() {
                                          final chosen = values(e.key).toSet();
                                          if (selected) {
                                            chosen.add(id);
                                          } else {
                                            chosen.remove(id);
                                          }
                                          e.value.text = chosen.join(', ');
                                        }),
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    TextFormField(
                      controller: e.value,
                      enabled: !saving && !self,
                      decoration: InputDecoration(labelText: t(e.key)),
                    ),
              ],
            ),
            ExpansionTile(
              title: Text(t('extras')),
              children: [
                scopes(extraScopes),
                for (final code in PermissionCodes.values)
                  CheckboxListTile(
                    title: Text(t('permission.$code')),
                    value: extras.contains(code),
                    onChanged: saving || self
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              extras.add(code);
                            } else {
                              extras.remove(code);
                            }
                          }),
                  ),
              ],
            ),
            ExpansionTile(
              title: Text(t('denies')),
              children: [
                for (final code in PermissionCodes.values)
                  CheckboxListTile(
                    title: Text(t('permission.$code')),
                    value: denies.contains(code),
                    onChanged: saving || self
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              denies.add(code);
                            } else {
                              denies.remove(code);
                            }
                          }),
                  ),
              ],
            ),
            TextFormField(
              key: const Key('account-reason'),
              controller: reason,
              enabled: !saving && !self,
              decoration: InputDecoration(labelText: t('reason')),
              maxLength: 500,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? t('error.invalid') : null,
            ),
            if (error != null)
              Text(
                t('error.$error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (saving)
              const Center(child: CircularProgressIndicator())
            else if (!self)
              FilledButton(
                key: const Key('account-save'),
                onPressed: _save,
                child: Text(t('save')),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );
}
