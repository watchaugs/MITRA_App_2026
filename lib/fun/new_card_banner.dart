// ═══════════════════════════════════════════════════════════════════════════
// "New hero card!" banner shown in the page scanner the first time a lesson's
// page is found. Drops in with a shine, stays 3 s, slides away.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/tr_ext.dart';
import 'fun_cards.dart';

/// Unlocks [lessonId]'s card; true only the first time.
Future<bool> unlockHeroCard(SharedPreferences prefs, String lessonId) =>
    CardStore(prefs).unlock(lessonId);

class NewCardBanner extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  const NewCardBanner({super.key, required this.onDone});

  @override
  ConsumerState<NewCardBanner> createState() => _NewCardBannerState();
}

class _NewCardBannerState extends ConsumerState<NewCardBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..forward();
  Timer? _done;

  @override
  void initState() {
    super.initState();
    _done = Timer(const Duration(milliseconds: 3700), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _done?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          // In over 0.4 s, hold, out over the last 0.4 s.
          final inT = Curves.easeOutBack.transform((t / 0.11).clamp(0.0, 1.0));
          final outT = Curves.easeIn.transform(((t - 0.89) / 0.11).clamp(0.0, 1.0));
          final y = -90 * (1 - inT) - 90 * outT;
          final shine = ((t - 0.1) / 0.35).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(0, y),
            child: Opacity(opacity: (1 - outT).clamp(0.0, 1.0), child: _box(context, shine)),
          );
        },
      ),
    );
  }

  Widget _box(BuildContext context, double shine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A), width: 2),
      ),
      child: Stack(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.shield_rounded, color: Color(0xFFFDE68A), size: 30),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(context.tr(ref, 'fun_new_card', 'New hero card!'),
                  style: const TextStyle(fontFamily: 'Baloo2', fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white)),
              Text(context.tr(ref, 'fun_new_card_sub', 'See it in Hero HQ → Hero cards'),
                  style: const TextStyle(fontFamily: 'Mukta', fontSize: 12, color: Colors.white70)),
            ]),
          ),
        ]),
        // Shine sweeping across.
        if (shine > 0 && shine < 1)
          Positioned.fill(
            child: Align(
              alignment: Alignment(-1.4 + 2.8 * shine, 0),
              child: Container(width: 26, color: Colors.white.withValues(alpha: 0.25)),
            ),
          ),
      ]),
    );
  }
}
