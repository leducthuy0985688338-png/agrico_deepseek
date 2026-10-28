import 'dart:async';

import 'package:flutter/material.dart';

/// One timer after each completed refresh, active only on the visible route.
mixin WorkspacePolling<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _polling = false;
  bool _visible = false;
  bool _foreground = true;
  int _seconds = 10;
  Future<void> refreshWorkspace();
  bool get workspaceChanged;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = ModalRoute.of(context)?.isCurrent ?? true;
    _schedule(immediate: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule(immediate: true);
  }

  void _schedule({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!mounted || !_visible || !_foreground || _polling) return;
    _pollTimer = Timer(Duration(seconds: immediate ? 0 : _seconds), () async {
      _polling = true;
      try {
        await refreshWorkspace();
        _seconds = workspaceChanged ? 10 : (_seconds * 2).clamp(10, 60);
      } finally {
        _polling = false;
        _schedule();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
