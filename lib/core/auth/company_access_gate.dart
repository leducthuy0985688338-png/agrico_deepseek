import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../app_v2/agrico_v2_composition.dart';
import '../localization/app_localizations.dart';
import '../permissions/authorization.dart';
import 'company_session.dart';
import 'file_company_session_store.dart';
import 'firebase_company_identity_gateway.dart';

class CompanyAccessGate extends StatefulWidget {
  const CompanyAccessGate({super.key, this.service, this.sessionBuilder});
  final CompanySessionService? service;
  final Widget Function(AuthorizationSubject subject, VoidCallback logout)?
  sessionBuilder;
  @override
  State<CompanyAccessGate> createState() => _CompanyAccessGateState();
}

class _CompanyAccessGateState extends State<CompanyAccessGate>
    with WidgetsBindingObserver {
  CompanySessionService? service;
  AuthorizationSubject? openedSubject;
  final email = TextEditingController();
  final password = TextEditingController();
  Timer? timer;
  bool busy = true, obscure = true, unlocked = false;
  String? message;
  int generation = 0, ticks = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  Future<void> _initialize() async {
    try {
      service =
          widget.service ??
          CompanySessionService(
            gateway: FirebaseCompanyIdentityGateway(),
            store: FileCompanySessionStore(
              File(
                '${(await getApplicationSupportDirectory()).path}/agrico_company_session_v1.json',
              ),
            ),
          );
      unlocked = await service!.restore();
      if (unlocked) {
        openedSubject = service!.subject;
      }
    } catch (e) {
      message = _failure(e);
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  String _failure(Object error) => error is AccessFailure
      ? error.code
      : error is AccessUnavailable
      ? 'onlineRequired'
      : 'setupRequired';
  Future<void> _login() async {
    if (busy || service == null) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await service!.login(email.text, password.text);
      unlocked = true;
      openedSubject = service!.subject;
      generation++;
      password.clear();
    } catch (e) {
      unlocked = false;
      message = _failure(e);
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> _logout() async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      unlocked = false;
      generation++;
    });
    try {
      await service!.logout();
    } catch (_) {
      message = 'signOutFailed';
    }
    password.clear();
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> _refresh() async {
    if (busy || service == null || !unlocked) {
      return;
    }
    final previous = jsonEncode(service!.current?.membership.toJson());
    setState(() => busy = true);
    try {
      unlocked = await service!.restore();
      if (unlocked) {
        openedSubject = service!.subject;
      }
      if (previous != jsonEncode(service!.current?.membership.toJson())) {
        generation++;
      }
    } catch (e) {
      unlocked = false;
      generation++;
      message = _failure(e);
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> _tick() async {
    if (busy || !unlocked || service == null) {
      return;
    }
    try {
      await service!.checkpoint();
    } catch (_) {
      if (mounted) {
        setState(() {
          unlocked = false;
          generation++;
          message = 'sessionExpired';
        });
      }
      return;
    }
    ticks++;
    if (ticks % 5 == 0) {
      await _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (unlocked && service != null) {
      // Every business route lives here. Lock/logout disposes the whole stack.
      return Stack(
        children: [
          Navigator(
            key: ValueKey('company-session-$generation'),
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) =>
                  widget.sessionBuilder?.call(
                    openedSubject!,
                    () => _logout(),
                  ) ??
                  AgricoV2Root(
                    userId: openedSubject!.userId,
                    subject: openedSubject!,
                    onSignOut: () => _logout(),
                    sessionOffline: service!.offline,
                  ),
            ),
          ),
          if (busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: const AbsorbPointer(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      );
    }
    if (busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.agriculture, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    l10n.text('auth.companyTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.text('auth.companyHint')),
                  TextField(
                    key: const Key('company-email'),
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l10n.text('auth.companyEmail'),
                    ),
                  ),
                  TextField(
                    key: const Key('company-password'),
                    controller: password,
                    obscureText: obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: l10n.text('auth.password'),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l10n.text('auth.access.$message'),
                        key: const Key('company-message'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('company-sign-in'),
                    onPressed: service == null ? null : _login,
                    child: Text(l10n.text('auth.signIn')),
                  ),
                  TextButton(
                    onPressed: service == null
                        ? null
                        : () async {
                            if (busy) {
                              return;
                            }
                            setState(() => busy = true);
                            try {
                              await service!.gateway.resetPassword(email.text);
                              message = 'resetSent';
                            } catch (e) {
                              message = _failure(e);
                            }
                            if (mounted) {
                              setState(() => busy = false);
                            }
                          },
                    child: Text(l10n.text('auth.forgotPassword')),
                  ),
                  TextButton(
                    onPressed: () {
                      if (busy) {
                        return;
                      }
                      setState(() {
                        busy = true;
                        message = null;
                      });
                      _initialize();
                    },
                    child: Text(l10n.text('auth.retryConnection')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
