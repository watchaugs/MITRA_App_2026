// ═══════════════════════════════════════════════════════
// Exit App Dialog — Theme-aware confirmation dialog
//
// A single, shared dialog used everywhere the user presses
// the hardware back button on the Home screen. Its background
// gradient, accent color, border and glow are all derived
// from the user's currently selected MitraTheme so it feels
// like a natural extension of whatever palette they've picked.
//
// Usage:
//   final shouldExit = await showExitAppDialog(context, ref);
//   if (shouldExit) SystemNavigator.pop();
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme_provider.dart';

import '../providers/tr_ext.dart';
/// Displays a themed "Exit App?" confirmation dialog.
///
/// Returns `true` if the user tapped **Exit**, `false` if they
/// tapped **Cancel** or dismissed the dialog by tapping outside.
Future<bool> showExitAppDialog(BuildContext context, WidgetRef ref) async {
  final activeTheme = ref.read(themeProvider);
  final bgColors = ThemeHelper.getBackgroundGradient(activeTheme);
  final highlight = ThemeHelper.getActiveHighlight(activeTheme);

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => _ExitAppDialogContent(
      bgColors: bgColors,
      highlight: highlight,
    ),
  );
  return result ?? false;
}

class _ExitAppDialogContent extends ConsumerWidget {
  final List<Color> bgColors;
  final Color highlight;

  const _ExitAppDialogContent({
    required this.bgColors,
    required this.highlight,
  });

  // Choose readable text color for the highlight-colored button
  Color get _onHighlight =>
      highlight.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: bgColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: highlight.withValues(alpha: 0.45),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: highlight.withValues(alpha: 0.18),
                blurRadius: 28,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Themed icon badge ──────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: highlight.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: highlight.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: highlight,
                  size: 30,
                ),
              ),

              const SizedBox(height: 18),

              // ── Title ──────────────────────────────────
              Text(
                context.tr(ref, 'common_exit_app', 'Exit App?'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 8),

              // ── Body ───────────────────────────────────
              Text(
                context.tr(ref, 'common_are_you_sure_you_want_to', 'Are you sure you want to close MITRA?'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 15,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),

              const SizedBox(height: 24),

              // ── Actions ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                      ),
                      child: Text(
                        context.tr(ref, 'btn_cancel', 'Cancel'),
                        style: TextStyle(
                          fontFamily: 'Mukta',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: highlight,
                        foregroundColor: _onHighlight,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        context.tr(ref, 'common_exit', 'Exit'),
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _onHighlight,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
