import 'dart:ui'; // ✨ Required for the ImageFilter.blur glass effect
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../widgets/language_alphabet_background.dart';
import '../../widgets/sync_status_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tr_ext.dart';

class StudentShell extends ConsumerWidget {
  final Widget child;
  const StudentShell({super.key, required this.child});

  static const _tabs = [
    _Tab(label: 'Home', emoji: '🏨', route: '/student/home'),
    _Tab(label: 'Learn', emoji: '🧠', route: '/student/learn'),
    _Tab(label: 'Achievements', emoji: '🏆', route: '/student/achievements'),
    _Tab(label: 'Profile', emoji: '👥', route: '/student/profile'),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    return _tabs
        .indexWhere((t) => loc.startsWith(t.route))
        .clamp(0, _tabs.length - 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _currentIndex(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final barHeight = 65.0 + bottomPadding;

    return MitraScaffold(
      useSafeArea: false,
      body: Stack(
        children: [
          // --- LAYER 1: Main Content ---
          Column(
            children: [
              const SyncStatusBanner(),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(child: LanguageAlphabetBackground()),

                    // ✨ THE SCROLL FIX: This injects padding into the child screens.
                    // ListViews will automatically add this exact amount of empty space
                    // at the bottom of their scroll, preventing the glass bar from hiding content!
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        padding: EdgeInsets.only(bottom: barHeight),
                      ),
                      child: child,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // --- LAYER 2: True Glassmorphism Navigation Bar ---
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              // ClipRRect is required so the blur doesn't bleed up the screen
              child: BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: 15.0,
                    sigmaY: 15.0), // ✨ Beautiful frosted glass blur
                child: Container(
                  height: barHeight,
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  decoration: BoxDecoration(
                    // ✨ Uses your exact Theme background color, but makes it 60% transparent
                    color: Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.6),
                    border: Border(
                        top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(_tabs.length, (i) {
                      final focused = i == idx;
                      // The bar is icon-only: give screen readers the tab name
                      // (translated) instead of reading out the emoji.
                      return Semantics(
                          button: true,
                          selected: focused,
                          excludeSemantics: true,
                          label: context.tr(
                              ref,
                              'tab_${_tabs[i].label.toLowerCase()}',
                              _tabs[i].label),
                          onTap: () => context.go(_tabs[i].route),
                          child: GestureDetector(
                            onTap: () => context.go(_tabs[i].route),
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              width: 80,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // ✨ Clean, icon-only layout. Sizes and fades smoothly.
                                  Opacity(
                                    opacity: focused ? 1.0 : 0.4,
                                    child: Text(_tabs[i].emoji,
                                        style: TextStyle(
                                            fontSize: focused ? 34 : 28)),
                                  ),
                                ],
                              ),
                            ),
                          ));
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab {
  final String label, emoji, route;
  const _Tab({required this.label, required this.emoji, required this.route});
}
