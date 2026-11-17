// ═══════════════════════════════════════════════════════════════════════════
// Hero HQ — replaces the old Achievements page (same tab, same routes).
//
// One story: TOTAL XP gives your hero RANK (the existing tiers, unchanged:
// Jigyasu → Anveshak → Vidwan → Acharya → Gyani at 0 / 500 / 2000 / 5000 /
// 10000 XP, set by the achievement engine). SUBJECT XP dresses up each
// subject's hero. Below: streak, subject heroes, hero cards, weekly parent
// card, and the tier badges as hero medals. Follows the active app theme.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/tr_ext.dart';
import '../screens/student/learn_screen.dart';
import '../services/achievement_engine.dart';
import '../stores/auth_store.dart';
import '../theme/theme_provider.dart';
import '../widgets/mitra_scaffold.dart';
import 'card_album_screen.dart';
import 'chiku.dart';
import 'fun_cards.dart';
import 'fun_progress.dart';
import 'hero_catalog.dart';
import 'hero_gallery_screen.dart';
import 'hero_view.dart';
import 'parent_card.dart';

class HeroRank {
  final String name, emoji, badgeId;
  final int minXp;
  final Color color;
  const HeroRank(this.name, this.emoji, this.badgeId, this.minXp, this.color);
}

// Same ladder as AchievementEngine._updateGlobalXp (names, XP, badge ids).
const List<HeroRank> kHeroRanks = [
  HeroRank('Jigyasu', '🥉', 'jigyasu_bronze', 0, Color(0xFFCD7F32)),
  HeroRank('Anveshak', '🥈', 'anveshak_silver', 500, Color(0xFF94A3B8)),
  HeroRank('Vidwan', '✨', 'vidwan_spark', 2000, Color(0xFFF59E0B)),
  HeroRank('Acharya', '🥇', 'acharya_gold', 5000, Color(0xFF8B5CF6)),
  HeroRank('Gyani', '💎', 'gyani_diamond', 10000, Color(0xFFFFD700)),
];

HeroRank rankForXp(int xp) {
  var r = kHeroRanks.first;
  for (final k in kHeroRanks) {
    if (xp >= k.minXp) r = k;
  }
  return r;
}

HeroRank? nextRank(int xp) {
  for (final k in kHeroRanks) {
    if (xp < k.minXp) return k;
  }
  return null;
}

/// The student's lead hero: the most dressed-up hero they have met.
/// (subject, hero, costume level), or null before any hero is met.
final leadHeroProvider = Provider<(String, HeroDef, int)?>((ref) {
  final prog = ref.watch(subjectHeroProgressProvider).valueOrNull;
  final subjects = ref.watch(metSubjectsProvider);
  if (subjects.isEmpty) return null;
  String best = subjects.first;
  double bestShare = -1;
  for (final s in subjects) {
    final share = prog?[s]?.share ?? 0;
    if (share > bestShare) {
      bestShare = share;
      best = s;
    }
  }
  return (best, heroForSubject(best), prog?[best]?.level ?? 0);
});

class HeroHqScreen extends ConsumerWidget {
  /// true when pushed on its own (back button + themed background); false as
  /// the Achievements tab inside the student shell.
  final bool standalone;
  const HeroHqScreen({super.key, this.standalone = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tp = ThemeHelper.ctxTextPrimary(context);
    final ts = ThemeHelper.ctxTextSecondary(context);
    final hl = Theme.of(context).colorScheme.primary;
    final profile = ref.watch(studentProfileProvider).valueOrNull;
    final xp = profile?.totalXp ?? 0;
    final streak = profile?.currentStreakDays ?? 0;
    final badges = profile?.unlockedBadges ?? const <String>[];
    final rank = rankForXp(xp), next = nextRank(xp);
    final gender = heroGenderFor(ref.watch(currentUserProvider)?.gender);
    final lead = ref.watch(leadHeroProvider);
    final allSubjects =
        ref.watch(arCatalogProvider).valueOrNull?.bySubject.keys.toList() ??
            const <String>[];
    final subjects = ref.watch(metSubjectsProvider);
    final hidden = allSubjects.length - subjects.length;
    final prog = ref.watch(subjectHeroProgressProvider).valueOrNull ?? const {};
    final cards = ref.watch(albumCardsProvider);
    final gotCards = cards.where((c) => c.unlocked).length;
    final newCards = cards.where((c) => c.isNew).length;
    final rankProgress = next == null
        ? 1.0
        : ((xp - rank.minXp) / (next.minXp - rank.minXp)).clamp(0.0, 1.0);
    String rankName(HeroRank r) =>
        context.tr(ref, 'tier_${r.name.toLowerCase()}', r.name);

    BoxDecoration glass([Color? border]) => BoxDecoration(
          color: ThemeHelper.ctxGlassFill(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: border ?? ThemeHelper.ctxGlassBorder(context),
              width: border == null ? 1 : 2),
        );

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(title,
              style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: tp)),
        );

    final content = ListView(
      padding: EdgeInsets.fromLTRB(
          16,
          standalone ? 72 : MediaQuery.paddingOf(context).top + 12,
          16,
          MediaQuery.paddingOf(context).bottom + 32),
      children: [
        Row(children: [
          Expanded(
            child: Text(context.tr(ref, 'fun_hq_title', 'Hero HQ'),
                style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    color: tp)),
          ),
          const SizedBox(width: 80),
        ]),
        // ── Lead hero + rank ──
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(14),
          decoration: glass(rank.color),
          child: Row(children: [
            if (lead != null)
              MitraHeroView(
                  hero: lead.$2, gender: gender, level: lead.$3, height: 170)
            else
              const MysteryHero(height: 170),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr(ref, 'fun_hq_rank', 'Hero rank'),
                        style: TextStyle(
                            fontFamily: 'Mukta', fontSize: 12, color: ts)),
                    Text('${rank.emoji} ${rankName(rank)}',
                        style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            color: rank.color)),
                    if (lead != null)
                      Text('${heroName(lead.$2, gender)} · ${lead.$1}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Mukta', fontSize: 13, color: tp)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: rankProgress,
                          minHeight: 9,
                          color: rank.color,
                          backgroundColor: ThemeHelper.ctxGlassBorder(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      next == null
                          ? context.trp(ref, 'fun_hq_rank_max',
                              '{xp} XP · top rank!', {'xp': '$xp'})
                          : context.trp(ref, 'fun_hq_rank_next',
                              '{xp} XP · {left} XP to {rank}', {
                              'xp': '$xp',
                              'left': '${next.minXp - xp}',
                              'rank': rankName(next)
                            }),
                      style: TextStyle(
                          fontFamily: 'Mukta', fontSize: 12, color: ts),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.bolt_rounded,
                          color: Color(0xFFFFD43B), size: 20),
                      Text(
                          context.trp(ref, 'fun_power_level',
                              'Power level {n}!', {'n': '$streak'}),
                          style: TextStyle(
                              fontFamily: 'Mukta',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: tp)),
                    ]),
                  ]),
            ),
          ]),
        ),

        // ── Subject heroes ──
        section(context.tr(ref, 'fun_hq_subject_heroes', 'Subject heroes')),
        if (allSubjects.isEmpty)
          Text(
              context.tr(ref, 'fun_heroes_empty',
                  'Your heroes appear here when your lessons load.'),
              style: TextStyle(fontFamily: 'Mukta', color: ts))
        else if (subjects.isEmpty)
          HiddenHeroesNote(hidden: hidden, none: true)
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.62),
            itemCount: subjects.length,
            itemBuilder: (ctx, i) {
              final s = subjects[i];
              final h = heroForSubject(s);
              final lvl = prog[s]?.level ?? 0;
              return HeroTile(
                subject: s,
                hero: h,
                gender: gender,
                level: lvl,
                onTap: () => openHeroSheet(context, ref, s, h, gender, lvl),
              );
            },
          ),
        if (subjects.isNotEmpty && hidden > 0) HiddenHeroesNote(hidden: hidden),

        // ── Hero cards + parent card ──
        section(context.tr(ref, 'fun_hq_more', 'Collect and share')),
        Row(children: [
          Expanded(
            child: _HqButton(
              icon: Icons.style_rounded,
              title: context.tr(ref, 'fun_hq_cards', 'Hero cards'),
              sub: context.trp(
                  ref,
                  'fun_hq_cards_sub',
                  '{got} of {all} collected',
                  {'got': '$gotCards', 'all': '${cards.length}'}),
              badge: newCards > 0 ? '$newCards' : null,
              onTap: () => context.push('/student/cards').whenComplete(() {
                ref.read(cardTickProvider.notifier).state++;
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _HqButton(
              icon: Icons.family_restroom_rounded,
              title: context.tr(ref, 'fun_hq_parent', 'Parent card'),
              sub: context.tr(
                  ref, 'fun_hq_parent_sub', "Share this week's report"),
              onTap: () => showParentCard(context, ref),
            ),
          ),
        ]),

        // ── Medals (the tier badges) ──
        section(context.tr(ref, 'fun_hq_medals', 'Hero medals')),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: glass(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final r in kHeroRanks)
                _Medal(
                    rank: r,
                    earned: badges.contains(r.badgeId) || xp >= r.minXp,
                    label: rankName(r),
                    hl: hl),
            ],
          ),
        ),
      ],
    );

    final body = Stack(children: [
      content,
      Positioned(
        top: standalone ? 60 : MediaQuery.paddingOf(context).top + 4,
        right: 14,
        child: const ChikuCorner(size: 88),
      ),
    ]);

    if (!standalone) {
      // As a tab: transparent, so the shell's background shows (like before).
      return Scaffold(backgroundColor: Colors.transparent, body: body);
    }
    return MitraScaffold(
      useSafeArea: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: tp),
            onPressed: () => context.pop()),
      ),
      body: body,
    );
  }
}

class _HqButton extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final String? badge;
  final VoidCallback onTap;
  const _HqButton(
      {required this.icon,
      required this.title,
      required this.sub,
      required this.onTap,
      this.badge});

  @override
  Widget build(BuildContext context) {
    final tp = ThemeHelper.ctxTextPrimary(context);
    final ts = ThemeHelper.ctxTextSecondary(context);
    final hl = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ThemeHelper.ctxGlassFill(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ThemeHelper.ctxGlassBorder(context)),
        ),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, color: hl, size: 30),
            if (badge != null)
              Positioned(
                right: -8,
                top: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(badge!,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: tp)),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Mukta', fontSize: 11.5, color: ts)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Medal extends StatelessWidget {
  final HeroRank rank;
  final bool earned;
  final String label;
  final Color hl;
  const _Medal(
      {required this.rank,
      required this.earned,
      required this.label,
      required this.hl});

  @override
  Widget build(BuildContext context) {
    final ts = ThemeHelper.ctxTextSecondary(context);
    return Semantics(
      label: '$label ${earned ? '' : '(locked)'}',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Opacity(
          opacity: earned ? 1.0 : 0.3,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rank.color.withValues(alpha: 0.18),
              border: Border.all(color: rank.color, width: 2),
            ),
            child: Text(earned ? rank.emoji : '🔒',
                style: const TextStyle(fontSize: 20)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontFamily: 'Mukta', fontSize: 10.5, color: earned ? hl : ts)),
      ]),
    );
  }
}
