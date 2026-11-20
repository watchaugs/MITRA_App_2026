// ═══════════════════════════════════════════════════════
// SCREEN S-02: Onboarding — 4 swipeable slides
// 1 AR textbook · 2 your superhero + ranks · 3 hero cards + sharing · 4 offline.
// Slides 2 and 3 show the real animated heroes (tap = power move) and Chiku.
// ═══════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import '../../packs/pack_store.dart';
import '../../providers/tr_ext.dart';
import '../../providers/translation_provider.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../constants/colors.dart';
import '../../fun/chiku.dart';
import '../../fun/hero_catalog.dart';
import '../../fun/hero_hq_screen.dart' show kHeroRanks;
import '../../fun/hero_view.dart';

/// What the picture box on a slide shows (svg / lottie: from a slides pack).
enum _Visual { emoji, heroes, cards, svg, lottie }

class _Slide {
  final String emoji;
  final String title;
  final String titleAccent;
  final String body;
  final List<Color> gradient;
  final _Visual visual;
  final bool ranks; // show the rank ladder under the text
  // From a slides pack: text per language, and the picture.
  final Map<String, String>? titleI18n, accentI18n, bodyI18n;
  final String? svg;
  final Uint8List? lottie;

  const _Slide({
    required this.emoji,
    required this.title,
    required this.titleAccent,
    required this.body,
    required this.gradient,
    this.visual = _Visual.emoji,
    this.ranks = false,
    this.titleI18n,
    this.accentI18n,
    this.bodyI18n,
    this.svg,
    this.lottie,
  });
}

// The slides shown: the built-in ones, or as a slides content pack says
// (replace them, or add before / after). Worked out once per run.
List<_Slide>? _slideCache;
List<_Slide> get _allSlides => _slideCache ??= _withPackSlides();

List<_Slide> _withPackSlides() {
  final pack = PackStore.instance.slides;
  if (pack == null) return _slides;
  final raw = pack['slides'];
  final extra = <_Slide>[];
  if (raw is List) {
    for (final m in raw.whereType<Map>()) {
      final s = _slideFromPack(m);
      if (s != null) extra.add(s);
    }
  }
  if (extra.isEmpty) return _slides;
  switch ((pack['mode'] ?? 'replace').toString()) {
    case 'append':
      return [..._slides, ...extra];
    case 'prepend':
      return [...extra, ..._slides];
    default:
      return extra;
  }
}

Map<String, String>? _i18n(Object? v) => v is Map
    ? {
        for (final e in v.entries)
          if (e.value is String) e.key.toString(): e.value as String
      }
    : null;

// Plain text, or the English (else first) entry of a per-language map.
String _english(Object? v) {
  if (v is String) return v;
  final m = _i18n(v);
  if (m == null || m.isEmpty) return '';
  return m['en'] ?? m.values.first;
}

Color? _hexColor(Object? v) {
  if (v is! String) return null;
  final h = v.replaceFirst('#', '');
  final n = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  return n == null ? null : Color(0xFF000000 | n);
}

_Slide? _slideFromPack(Map m) {
  final title = _english(m['title']);
  final body = _english(m['body']);
  if (title.isEmpty || body.isEmpty) return null;
  final g = m['gradient'];
  final top = g is List && g.length == 2 ? _hexColor(g[0]) : null;
  final bottom = g is List && g.length == 2 ? _hexColor(g[1]) : null;
  final svg = m['svg'] is String ? m['svg'] as String : null;
  final lottie = m['lottie'] is Map
      ? Uint8List.fromList(utf8.encode(jsonEncode(m['lottie'])))
      : null;
  var visual = switch ((m['visual'] ?? 'emoji').toString()) {
    'heroes' => _Visual.heroes,
    'cards' => _Visual.cards,
    'svg' => _Visual.svg,
    'lottie' => _Visual.lottie,
    _ => _Visual.emoji,
  };
  if (visual == _Visual.svg && svg == null) visual = _Visual.emoji;
  if (visual == _Visual.lottie && lottie == null) visual = _Visual.emoji;
  return _Slide(
    emoji: (m['emoji'] ?? '✨').toString(),
    title: title,
    titleAccent: _english(m['title_accent']),
    body: body,
    gradient: (top != null && bottom != null)
        ? [top, bottom]
        : MitraColors.gradientIndigo,
    visual: visual,
    ranks: m['ranks'] == true,
    titleI18n: _i18n(m['title']),
    accentI18n: _i18n(m['title_accent']),
    bodyI18n: _i18n(m['body']),
    svg: svg,
    lottie: lottie,
  );
}

// Slide text in the app language: a pack's own translation when it has one,
// else the usual data-text lookup.
String _slideText(BuildContext context, WidgetRef ref, String english,
    Map<String, String>? byLang) {
  if (byLang == null) return context.trText(ref, english);
  final lang = ref.watch(translationProvider).langCode;
  return byLang[lang] ?? byLang['en'] ?? english;
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
    if (_currentIdx < _allSlides.length - 1) {
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
            itemCount: _allSlides.length,
            onPageChanged: (i) => setState(() => _currentIdx = i),
            itemBuilder: (ctx, i) => _SlideWidget(slide: _allSlides[i]),
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
                    _allSlides.length,
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
                        _currentIdx < _allSlides.length - 1
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
                        _Visual.svg => SvgPicture.string(slide.svg!,
                            width: 210, height: 210),
                        _Visual.lottie => Lottie.memory(slide.lottie!,
                            width: 210,
                            height: 210,
                            repeat: true,
                            errorBuilder: (_, __, ___) => Text(slide.emoji,
                                style: const TextStyle(fontSize: 96))),
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
                              text:
                                  '${_slideText(context, ref, slide.title, slide.titleI18n)}\n'),
                          TextSpan(
                              text: _slideText(context, ref, slide.titleAccent,
                                  slide.accentI18n),
                              style:
                                  const TextStyle(color: MitraColors.saffron)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Body
                    Text(
                      _slideText(context, ref, slide.body, slide.bodyI18n),
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
