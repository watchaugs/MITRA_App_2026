// ═══════════════════════════════════════════════════════
// SCREEN S-02: Onboarding — 4 swipeable slides
// 1 AR textbook · 2 your superhero + ranks · 3 hero cards + sharing · 4 offline.
// Slides 2 and 3 show the real animated heroes (tap = power move) and Chiku.
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tr_ext.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../constants/colors.dart';
import '../../fun/chiku.dart';
import '../../fun/hero_catalog.dart';
import '../../fun/hero_hq_screen.dart' show kHeroRanks;
import '../../fun/hero_view.dart';

/// What the picture box on a slide shows.
enum _Visual { emoji, heroes, cards }

class _Slide {
  final String emoji;
  final String title;
  final String titleAccent;
  final String body;
  final List<Color> gradient;
  final _Visual visual;
  final bool ranks; // show the rank ladder under the text

  const _Slide({
    required this.emoji,
    required this.title,
    required this.titleAccent,
    required this.body,
    required this.gradient,
    this.visual = _Visual.emoji,
    this.ranks = false,
  });
}

const _slides = [
  _Slide(
    emoji: '🔬',
    title: 'See Your Textbook',
    titleAccent: 'Come Alive',
    body:
        'Point your phone at any chapter and watch 3D models of cells, planets, and historical events appear in AR — right from your textbook page.',
    gradient: MitraColors.gradientIndigo,
  ),
  _Slide(
    emoji: '🦸',
    title: 'Meet Your Superhero,',
    titleAccent: 'Who Grows With You',
    body:
        'Every subject has its own hero — Jeevak for Biology, Vidyut for Physics and more. Watch lessons and ace quizzes to suit them up, piece by piece, all the way to gold armour. Tap your hero to see their power move!',
    gradient: [Color(0xFF041A12), Color(0xFF0B3B2A)],
    visual: _Visual.heroes,
    ranks: true,
  ),
  _Slide(
    emoji: '🃏',
    title: 'Collect Hero Cards,',
    titleAccent: 'Show Your Family',
    body:
        'Scan your textbook pages to unlock hero cards for your album. Every week, share your Hero Report with your parents on WhatsApp, Instagram, Facebook or any messaging app — your streak, lessons and new cards in one bright picture.',
    gradient: [Color(0xFF1A0A1F), Color(0xFF3A1240)],
    visual: _Visual.cards,
  ),
  _Slide(
    emoji: '📴',
    title: 'Learn Even',
    titleAccent: 'Without Internet',
    body:
        'Download lessons over Wi-Fi and access all content offline — perfect for areas with limited connectivity.',
    gradient: [Color(0xFF0a1a0a), Color(0xFF0a2a1a)],
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _ctrl = PageController();
  int _currentIdx = 0;

  void _goNext() {
    if (_currentIdx < _slides.length - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MitraScaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _currentIdx = i),
            itemBuilder: (ctx, i) => _SlideWidget(slide: _slides[i]),
          ),

          // Skip button
          Positioned(
            top: 56,
            right: 24,
            child: TextButton(
              onPressed: () => context.go('/login'),
              // Bundled Mukta (was GoogleFonts, which downloads at runtime).
              child: Text(context.tr(ref, 'auth_skip', 'Skip'),
                  style: const TextStyle(
                      fontFamily: 'Mukta', color: MitraColors.textMuted)),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Column(
              children: [
                // Dot indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentIdx ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _currentIdx
                            ? MitraColors.saffron
                            : MitraColors.textMuted,
                        borderRadius: BorderRadius.circular(MitraRadius.pill),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Next / Get Started button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _goNext,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: MitraColors.gradientSaffron),
                        borderRadius: BorderRadius.circular(MitraRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _currentIdx < _slides.length - 1
                            ? context.tr(ref, 'auth_next', 'Next →')
                            : context.tr(
                                ref, 'auth_get_started', 'Get Started →'),
                        style: const TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideWidget extends ConsumerWidget {
  final _Slide slide;
  const _SlideWidget({required this.slide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: slide.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        // Scrolls only on short screens, so a longer slide never overflows.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(MitraSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Picture box: emoji, or the live heroes / hero cards
                    Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(MitraRadius.lg),
                        border:
                            Border.all(color: MitraColors.border, width: 1.5),
                        color: MitraColors.bgCard,
                      ),
                      alignment: Alignment.center,
                      child: switch (slide.visual) {
                        _Visual.heroes => const _HeroesVisual(),
                        _Visual.cards => const _CardsVisual(),
                        _Visual.emoji => Text(slide.emoji,
                            style: const TextStyle(fontSize: 96)),
                      },
                    ),
                    const SizedBox(height: 40),

                    // Title
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                            fontFamily: 'Baloo2',
                            fontWeight: FontWeight.w800,
                            fontSize: 28,
                            color: MitraColors.textPrimary),
                        children: [
                          TextSpan(
                              text: '${context.trText(ref, slide.title)}\n'),
                          TextSpan(
                              text: context.trText(ref, slide.titleAccent),
                              style:
                                  const TextStyle(color: MitraColors.saffron)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Body
                    Text(
                      context.trText(ref, slide.body),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 15,
                        color: MitraColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                    if (slide.ranks) ...[
                      const SizedBox(height: 14),
                      // The five ranks, in the app language (tier_* keys).
                      Text(
                        [
                          for (final r in kHeroRanks)
                            '${r.emoji} ${context.tr(ref, 'tier_${r.name.toLowerCase()}', r.name)}'
                        ].join('  →  '),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: MitraColors.saffron,
                          height: 1.6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 120), // space for bottom controls
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide 2: the Biology hero team in full armour (tap = power move), Chiku
/// swinging from the top of the box, and the five rank medals.
class _HeroesVisual extends StatelessWidget {
  const _HeroesVisual();

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Align(
        alignment: const Alignment(0, 0.12),
        child: MitraHeroView(
          hero: heroForSubject('Biology'),
          gender: HeroGender.team,
          level: 4,
          height: 156,
        ),
      ),
      const Positioned(top: -10, right: 2, child: ChikuCorner(size: 64)),
      Positioned(
        left: 0,
        right: 0,
        bottom: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final r in kHeroRanks)
              Text(r.emoji, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    ]);
  }
}

/// Slide 3: a hero card and the weekly Hero Report, fanned like a hand of
/// cards, with the share button.
class _CardsVisual extends ConsumerWidget {
  const _CardsVisual();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = heroForSubject('Physics');
    Widget stat(String emoji, String n) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(n,
                style: const TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: MitraColors.textPrimary)),
          ]),
        );
    final report = Container(
      width: 112,
      height: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MitraColors.bgDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MitraColors.saffron, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr(ref, 'onb_hero_report', 'Hero Report'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: MitraColors.saffron)),
          const SizedBox(height: 4),
          stat('🔥', '7'),
          stat('📚', '12'),
          stat('🃏', '3'),
          const Spacer(),
          const Align(
            alignment: Alignment.bottomRight,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: MitraColors.saffron,
              child: Icon(Icons.share_rounded, size: 15, color: Colors.white),
            ),
          ),
        ],
      ),
    );
    final card = Container(
      width: 108,
      height: 156,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color.lerp(h.main, Colors.black, .55)!, h.main],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: h.accent, width: 2),
      ),
      child: Column(children: [
        Expanded(
          child: MitraHeroView(
            hero: h,
            gender: HeroGender.boy,
            level: 4,
            height: 118,
            tapForPower: false,
          ),
        ),
        const Text('★★★',
            style: TextStyle(fontSize: 14, color: Color(0xFFFACC15))),
      ]),
    );
    return Stack(alignment: Alignment.center, children: [
      Transform.translate(
        offset: const Offset(40, 6),
        child: Transform.rotate(angle: 0.14, child: report),
      ),
      Transform.translate(
        offset: const Offset(-36, -4),
        child: Transform.rotate(angle: -0.12, child: card),
      ),
    ]);
  }
}
