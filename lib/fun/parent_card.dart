// ═══════════════════════════════════════════════════════════════════════════
// Weekly card for parents: a bright, shareable picture of the week — rank,
// streak, XP, lessons finished, quizzes tried, new hero cards, and the lead
// hero. "Share" turns it into a PNG and opens the phone's share sheet
// (WhatsApp etc.); nothing is uploaded by MITRA. Only the first name and class
// appear on it.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/tr_ext.dart';
import '../services/achievement_engine.dart';
import '../stores/auth_store.dart';
import '../theme/theme_provider.dart'; // sharedPreferencesProvider
import 'fun_cards.dart';
import 'hero_catalog.dart';
import 'hero_hq_screen.dart';
import 'hero_view.dart';

Future<void> showParentCard(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _ParentCardSheet(),
  );
}

class _ParentCardSheet extends ConsumerStatefulWidget {
  const _ParentCardSheet();

  @override
  ConsumerState<_ParentCardSheet> createState() => _ParentCardSheetState();
}

class _ParentCardSheetState extends ConsumerState<_ParentCardSheet> {
  final _shot = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final box =
          _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (box == null) return;
      final img = await box.toImage(pixelRatio: 3);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/mitra_week_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(f.path, mimeType: 'image/png')],
        text: context.tr(
            ref, 'fun_parent_share_text', "This week's MITRA learning card"),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.tr(ref, 'fun_parent_share_failed',
                'Could not share the card. Try again.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = ThemeHelper.ctxTextPrimary(context);
    final hl = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(context.tr(ref, 'fun_parent_title', 'Weekly card for parents'),
              style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: tp)),
          const SizedBox(height: 10),
          RepaintBoundary(key: _shot, child: const ParentCard()),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: hl,
                foregroundColor: ThemeHelper.ctxIsLight(context)
                    ? Colors.white
                    : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.share_rounded),
              label: Text(
                  context.tr(ref, 'fun_parent_share', 'Share with family'),
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The card itself (fixed bright colours: it is shared as a picture).
class ParentCard extends ConsumerWidget {
  const ParentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(studentProfileProvider).valueOrNull;
    final prefs = ref.watch(sharedPreferencesProvider);
    ref.watch(cardTickProvider);
    final week = WeekCounts(prefs);
    final cards = CardStore(prefs).unlockedThisWeek();
    final xp = profile?.totalXp ?? 0;
    final streak = profile?.currentStreakDays ?? 0;
    final rank = rankForXp(xp);
    final lead = ref.watch(leadHeroProvider);
    final gender = heroGenderFor(user?.gender);

    Widget stat(String value, String label, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(value,
                  style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: c)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 11,
                      color: Color(0xFF334155))),
            ]),
          ),
        );

    return Container(
      width: 340,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B), width: 3),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  context.tr(
                      ref, 'fun_parent_header', 'MITRA weekly hero report'),
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFFB45309))),
              Text(user?.firstName ?? '',
                  style: const TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      color: Color(0xFF1E1B4B))),
              Text(
                  '${user?.classGrade ?? ''}  ·  ${rank.emoji} ${context.tr(ref, 'tier_${rank.name.toLowerCase()}', rank.name)}',
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 13,
                      color: Color(0xFF475569))),
            ]),
          ),
          SizedBox(
            height: 120,
            child: MitraHeroView(
                hero: lead?.$2 ?? kFallbackHero,
                gender: gender,
                level: lead?.$3 ?? 0,
                height: 120,
                tapForPower: false),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          stat('$streak', context.tr(ref, 'fun_parent_streak', 'day streak'),
              const Color(0xFFDC2626)),
          stat('$xp', context.tr(ref, 'fun_parent_xp', 'total XP'),
              const Color(0xFF7C3AED)),
        ]),
        Row(children: [
          stat(
              '${week.lessons}',
              context.tr(ref, 'fun_parent_lessons', 'lessons this week'),
              const Color(0xFF0E7490)),
          stat(
              '${week.quizzes}',
              context.tr(ref, 'fun_parent_quizzes', 'quizzes this week'),
              const Color(0xFF15803D)),
          stat('$cards', context.tr(ref, 'fun_parent_cards', 'new hero cards'),
              const Color(0xFFB45309)),
        ]),
        const SizedBox(height: 6),
        Text(
            context.tr(ref, 'fun_parent_footer',
                'Learning with MITRA — ask me what I learnt!'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'Mukta', fontSize: 12, color: Color(0xFF64748B))),
      ]),
    );
  }
}
