// ═══════════════════════════════════════════════════════════════════════════
// "My heroes": one original hero per subject the student has lessons in.
// Each hero's costume fills up with that subject's XP (20% → 100%).
// The profile gender picks the boy / girl hero; 'Other' shows the hero team.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/tr_ext.dart';
import '../screens/student/learn_screen.dart';
import '../stores/auth_store.dart';
import '../theme/theme_provider.dart';
import '../widgets/mitra_scaffold.dart';
import 'fun_progress.dart';
import 'hero_catalog.dart';
import 'hero_view.dart';

/// Pieces added at each costume level (shown as a checklist).
const List<(String, String)> kCostumePieces = [
  ('fun_piece_1', 'Hero T-shirt with emblem patch'),
  ('fun_piece_2', 'Mask and full hero suit'),
  ('fun_piece_3', 'Flowing cape and power belt'),
  ('fun_piece_4', 'Gloves, hero boots and shoulder guards'),
  ('fun_piece_5', 'Gold armour, headpiece and power aura'),
];

/// The hero detail sheet (big hero, power move, costume checklist).
void openHeroSheet(BuildContext context, WidgetRef ref, String subject,
        HeroDef hero, HeroGender gender, int level) =>
    const HeroGalleryScreen()
        ._openHero(context, ref, subject, hero, gender, level);

class HeroGalleryScreen extends ConsumerWidget {
  const HeroGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tp = ThemeHelper.ctxTextPrimary(context);
    final ts = ThemeHelper.ctxTextSecondary(context);
    final gender = heroGenderFor(ref.watch(currentUserProvider)?.gender);
    final allSubjects =
        ref.watch(arCatalogProvider).valueOrNull?.bySubject.keys.toList() ??
            const <String>[];
    final subjects = ref.watch(metSubjectsProvider);
    final hidden = allSubjects.length - subjects.length;
    final prog = ref.watch(subjectHeroProgressProvider).valueOrNull ?? const {};

    return MitraScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: tp),
            onPressed: () => context.pop()),
        title: Text(context.tr(ref, 'fun_my_heroes', 'My heroes'),
            style: TextStyle(
                fontFamily: 'Baloo2', fontWeight: FontWeight.w800, color: tp)),
      ),
      body: Stack(children: [
        allSubjects.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    context.tr(ref, 'fun_heroes_empty',
                        'Your heroes appear here when your lessons load.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Mukta', color: ts),
                  ),
                ),
              )
            : subjects.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const MysteryHero(height: 200),
                        HiddenHeroesNote(hidden: hidden, none: true),
                      ]),
                    ),
                  )
                : GridView.builder(
                    padding:
                        EdgeInsets.fromLTRB(12, 96, 12, hidden > 0 ? 72 : 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: subjects.length,
                    itemBuilder: (ctx, i) {
                      final subj = subjects[i];
                      final hero = heroForSubject(subj);
                      final p = prog[subj];
                      final level = p?.level ?? 0;
                      return HeroTile(
                        subject: subj,
                        hero: hero,
                        gender: gender,
                        level: level,
                        onTap: () =>
                            _openHero(context, ref, subj, hero, gender, level),
                      );
                    },
                  ),
        if (subjects.isNotEmpty && hidden > 0)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 8,
            child: HiddenHeroesNote(hidden: hidden),
          ),
        // Chiku lives only on Home and Hero HQ.
      ]),
    );
  }

  void _openHero(BuildContext context, WidgetRef ref, String subject,
      HeroDef hero, HeroGender gender, int level) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final tp = ThemeHelper.ctxTextPrimary(ctx);
        final ts = ThemeHelper.ctxTextSecondary(ctx);
        final hl = Theme.of(ctx).colorScheme.primary;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MitraHeroView(
                  hero: hero, gender: gender, level: level, height: 300),
              const SizedBox(height: 6),
              Text(heroName(hero, gender),
                  style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: tp)),
              Text(
                  context.trp(
                      ref,
                      'fun_hero_of',
                      '{subject} hero · tap for power move',
                      {'subject': subject}),
                  style:
                      TextStyle(fontFamily: 'Mukta', fontSize: 13, color: ts)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: kCostumePct[level] / 100,
                  minHeight: 10,
                  color: hl,
                  backgroundColor: ThemeHelper.ctxGlassBorder(ctx),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                  context.trp(ref, 'fun_costume_pct', 'Costume {pct}% complete',
                      {'pct': '${kCostumePct[level]}'}),
                  style: TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w700,
                      color: tp)),
              const SizedBox(height: 8),
              for (int i = 0; i < kCostumePieces.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(
                        i <= level
                            ? Icons.check_circle_rounded
                            : Icons.lock_outline_rounded,
                        size: 18,
                        color: i <= level ? hl : ts),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          context.tr(
                              ref, kCostumePieces[i].$1, kCostumePieces[i].$2),
                          style: TextStyle(
                              fontFamily: 'Mukta',
                              fontSize: 13,
                              color: i <= level ? tp : ts)),
                    ),
                  ]),
                ),
              const SizedBox(height: 6),
              Text(
                level >= 4
                    ? context.tr(ref, 'fun_costume_full',
                        'Fully suited up — a true Gyani hero!')
                    : context.trp(
                        ref,
                        'fun_costume_next',
                        'Learn more {subject} to unlock the next piece.',
                        {'subject': subject}),
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Mukta', fontSize: 12, color: ts),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// One subject hero with its costume % (used by Hero HQ too).
class HeroTile extends ConsumerWidget {
  final String subject;
  final HeroDef hero;
  final HeroGender gender;
  final int level;
  final VoidCallback onTap;
  const HeroTile({
    super.key,
    required this.subject,
    required this.hero,
    required this.gender,
    required this.level,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tp = ThemeHelper.ctxTextPrimary(context);
    final ts = ThemeHelper.ctxTextSecondary(context);
    final hl = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: '${heroName(hero, gender)}, $subject, ${kCostumePct[level]}%',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ThemeHelper.ctxGlassFill(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ThemeHelper.ctxGlassBorder(context)),
          ),
          child: Column(children: [
            Expanded(
              child: FittedBox(
                child: MitraHeroView(
                    hero: hero,
                    gender: gender,
                    level: level,
                    height: 170,
                    tapForPower: false),
              ),
            ),
            Text(heroName(hero, gender),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: tp)),
            Text(subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Mukta', fontSize: 12, color: ts)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: kCostumePct[level] / 100,
                minHeight: 6,
                color: hl,
                backgroundColor: ThemeHelper.ctxGlassBorder(context),
              ),
            ),
            const SizedBox(height: 2),
            Text('${kCostumePct[level]}%',
                style: TextStyle(
                    fontFamily: 'SpaceMono',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: hl)),
          ]),
        ),
      ),
    );
  }
}

/// Stand-in for a hero the student has not met yet: a dim shield with "?".
class MysteryHero extends StatelessWidget {
  final double height;
  const MysteryHero({super.key, this.height = 170});

  @override
  Widget build(BuildContext context) {
    final ts = ThemeHelper.ctxTextSecondary(context);
    return SizedBox(
      width: height * 0.75,
      height: height,
      child: Stack(alignment: Alignment.center, children: [
        Icon(Icons.shield_rounded,
            size: height * 0.72, color: ts.withValues(alpha: 0.22)),
        Text('?',
            style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: FontWeight.w800,
                fontSize: height * 0.3,
                color: ts.withValues(alpha: 0.75))),
      ]),
    );
  }
}

/// "Heroes are hiding" line under the hero grid (or alone when none met).
class HiddenHeroesNote extends ConsumerWidget {
  final int hidden;
  final bool none;
  const HiddenHeroesNote({super.key, required this.hidden, this.none = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ThemeHelper.ctxTextSecondary(context);
    final text = none
        ? context.tr(ref, 'fun_heroes_none',
            "Your heroes are hiding! Open any lesson to meet that subject's hero.")
        : context.trp(
            ref,
            'fun_heroes_hidden',
            '{n} more heroes are hiding. Open a lesson in a new subject to meet one.',
            {'n': '$hidden'});
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ThemeHelper.ctxGlassFill(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelper.ctxGlassBorder(context)),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, size: 18, color: ts),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontFamily: 'Mukta', fontSize: 13, color: ts)),
        ),
      ]),
    );
  }
}
