import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../constants/colors.dart';
import '../../widgets/sync_status_banner.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tr_ext.dart';
class TeacherShell extends ConsumerWidget {
  final Widget child;
  const TeacherShell({super.key, required this.child});

  static const _tabs = [
    _Tab('Home', '🏠', '/teacher/home'),
    _Tab('Students', '👥', '/teacher/students'),
    _Tab('Analytics', '📊', '/teacher/analytics'),
    _Tab('Content', '📚', '/teacher/assign'),
    _Tab('Profile', '👤', '/teacher/profile'),
  ];

  int _idx(BuildContext ctx) {
    final loc = GoRouterState.of(ctx).uri.path;
    return _tabs
        .indexWhere((t) => loc.startsWith(t.route))
        .clamp(0, _tabs.length - 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _idx(context);
    return MitraScaffold(
      body: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        height: 72,
        decoration: const BoxDecoration(
          color: Color(0xFF0a1a0a),
          border: Border(top: BorderSide(color: Color(0x330DC389))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_tabs.length, (i) {
            final focused = i == idx;
            return GestureDetector(
              onTap: () => context.go(_tabs[i].route),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_tabs[i].emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 2),
                    Text(context.trText(ref, _tabs[i].label),
                        style: TextStyle(
                          fontFamily: 'Mukta',
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                          color: focused
                              ? MitraColors.emerald
                              : MitraColors.textMuted,
                        )),
                    if (focused)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: const BoxDecoration(
                            color: MitraColors.emerald, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _Tab {
  final String label, emoji, route;
  const _Tab(this.label, this.emoji, this.route);
}
