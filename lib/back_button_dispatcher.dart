// ═══════════════════════════════════════════════════════
// MitraBackButtonHandler
//
// Registered as a WidgetsBindingObserver in main.dart.
// Works reliably because AndroidManifest does NOT set
// enableOnBackInvokedCallback=true — so Android still
// sends back presses as key events that Flutter's
// WidgetsBindingObserver.didPopRoute() intercepts.
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'widgets/exit_app_dialog.dart';

class MitraBackButtonHandler with WidgetsBindingObserver {
  final GoRouter router;
  final WidgetRef ref;
  final GlobalKey<NavigatorState> rootNavKey;

  bool _isShowingExitDialog = false;

  MitraBackButtonHandler({
    required this.router,
    required this.ref,
    required this.rootNavKey,
  });

  void register() => WidgetsBinding.instance.addObserver(this);
  void unregister() => WidgetsBinding.instance.removeObserver(this);

  @override
  Future<bool> didPopRoute() async {
    final loc = router.routerDelegate.currentConfiguration.uri.path;
    final ctx = rootNavKey.currentContext;
    debugPrint('🔙 Back: $loc');
    if (ctx == null) return false;

    // The bottom-nav TAB routes. Back from a tab goes to Home (like a normal
    // tab app); back from the Home tab prompts exit. EVERY other screen is a
    // pushed detail (AR viewer, edit-profile, notifications, quiz, result, …)
    // and must return to the screen it came from — pop the stack.
    const studentTabs = <String>[
      '/student/home',
      '/student/learn',
      '/student/achievements',
      '/student/profile',
    ];
    const teacherTabs = <String>[
      '/teacher/home',
      '/teacher/students',
      '/teacher/analytics',
      '/teacher/assign',
      '/teacher/profile',
    ];

    // ── Home tabs → prompt exit ───────────────────────
    if (loc == '/student/home' || loc == '/teacher/home') {
      return _promptExit(ctx);
    }

    // ── Other bottom-nav tabs → Home ──────────────────
    if (studentTabs.contains(loc)) {
      router.go('/student/home');
      return true;
    }
    if (teacherTabs.contains(loc)) {
      router.go('/teacher/home');
      return true;
    }

    // ── Everything else is a pushed detail screen ─────
    // Pop back to exactly where the user came from. Only if there's nothing to
    // pop (e.g. a screen reached via go() with no stack) do we fall back to a
    // sensible section home instead of dead-ending.
    if (router.canPop()) {
      router.pop();
      return true;
    }
    // No stack to pop — choose a safe home by section.
    if (loc.startsWith('/teacher/')) {
      router.go('/teacher/home');
      return true;
    }
    if (loc.startsWith('/student/') ||
        loc.startsWith('/quiz') ||
        loc.startsWith('/ar')) {
      router.go('/student/home');
      return true;
    }
    return _promptExit(ctx);
  }

  Future<bool> _promptExit(BuildContext ctx) async {
    if (_isShowingExitDialog) return true;
    _isShowingExitDialog = true;
    try {
      final shouldExit = await showExitAppDialog(ctx, ref);
      if (shouldExit) SystemNavigator.pop();
    } finally {
      _isShowingExitDialog = false;
    }
    return true;
  }
}
