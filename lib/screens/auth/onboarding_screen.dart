// ═══════════════════════════════════════════════════════
// SCREEN S-02: Onboarding — 3 swipeable slides
// Mirrors app/onboarding.tsx from Expo project
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tr_ext.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart'; // 🚨 NEW IMPORT ADDED
import '../../widgets/mitra_scaffold.dart';
import '../../constants/colors.dart';

class _Slide {
  final String emoji;
  final String title;
  final String titleAccent;
  final String body;
  final List<Color> gradient;

  const _Slide({
    required this.emoji,
    required this.title,
    required this.titleAccent,
    required this.body,
    required this.gradient,
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
    emoji: '🏆',
    title: 'Earn XP,',
    titleAccent: 'Climb the Leaderboard',
    body:
        'Answer quizzes, complete AR sessions, and maintain daily streaks to earn XP points and badges. Compete with classmates!',
    gradient: [Color(0xFF1a0a0a), Color(0xFF3a1a00)],
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
              // 🚨 FIX: Replaced standard TextStyle with GoogleFonts
              child: Text(context.tr(ref, 'auth_skip', 'Skip'),
                  style: GoogleFonts.mukta(color: MitraColors.textMuted)),
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
                            : context.tr(ref, 'auth_get_started', 'Get Started →'),
                        // 🚨 FIX: Replaced standard TextStyle with GoogleFonts
                        style: GoogleFonts.baloo2(
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
        child: Padding(
          padding: const EdgeInsets.all(MitraSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // AR frame illustration
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MitraRadius.lg),
                  border: Border.all(color: MitraColors.border, width: 1.5),
                  color: MitraColors.bgCard,
                ),
                alignment: Alignment.center,
                child: Text(slide.emoji, style: const TextStyle(fontSize: 96)),
              ),
              const SizedBox(height: 40),

              // Title
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  // 🚨 FIX: Replaced standard TextStyle with GoogleFonts
                  style: GoogleFonts.baloo2(
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      color: MitraColors.textPrimary),
                  children: [
                    TextSpan(text: '${context.trText(ref, slide.title)}\n'),
                    TextSpan(
                        text: context.trText(ref, slide.titleAccent),
                        style: const TextStyle(color: MitraColors.saffron)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Body
              Text(
                context.trText(ref, slide.body),
                textAlign: TextAlign.center,
                // 🚨 FIX: Replaced standard TextStyle with GoogleFonts
                style: GoogleFonts.mukta(
                  fontSize: 15,
                  color: MitraColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 120), // space for bottom controls
            ],
          ),
        ),
      ),
    );
  }
}
