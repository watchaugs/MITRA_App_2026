// ═══════════════════════════════════════════════════════
// SCREEN S-05: Student Home Dashboard
// Back button handled entirely by StudentShell
// Background animation moved to lib/widgets/language_alphabet_background.dart
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/colors.dart';
import '../../stores/auth_store.dart';
import '../../services/api_service.dart';
import '../../demo/demo_data.dart';
import '../../theme/theme_provider.dart';
import '../../services/quotes_service.dart';
import '../../services/brain_spark_service.dart';
import 'widgets/sponsor_banner.dart';

// ═══════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════

class Subject {
  final String emoji;
  final String name;
  final double progress;
  final int arCount;
  final Color color;

  const Subject({
    required this.emoji,
    required this.name,
    required this.progress,
    required this.arCount,
    required this.color,
  });

  factory Subject.fromJson(Map<String, dynamic> json, Color color) {
    return Subject(
      emoji: json['emoji'] as String? ?? '📚',
      name: json['name'] as String? ?? 'Subject',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      arCount: (json['ar'] ?? json['ar_topics_count'] ?? 0) as int,
      color: color,
    );
  }
}

// ── Word Data Model ─────────────────────────────────────
class WordData {
  final String word, meaning, usage, partOfSpeech;
  final String difficulty;
  late final String generatedUsage;

  WordData({
    required this.word,
    required this.meaning,
    required this.usage,
    required this.partOfSpeech,
    this.difficulty = 'intermediate',
  }) {
    generatedUsage = usage.isNotEmpty ? usage : '';
  }

  factory WordData.fromJson(Map<String, dynamic> json) {
    return WordData(
      word: json['word'] as String? ?? '',
      meaning: json['meaning'] as String? ?? '',
      usage: json['usage'] as String? ?? '',
      partOfSpeech: json['partOfSpeech'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'intermediate',
    );
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'meaning': meaning,
        'usage': usage,
        'partOfSpeech': partOfSpeech,
        'difficulty': difficulty,
      };
}

// ═══════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════

final dailyMotivationProvider = FutureProvider<String>((ref) async {
  return QuotesService.instance.getQuoteOfDay().quote;
});

final quoteAuthorProvider = FutureProvider<String>((ref) async {
  return QuotesService.instance.getQuoteOfDay().author;
});

final quoteProfessionProvider = FutureProvider<String>((ref) async {
  return QuotesService.instance.getQuoteOfDay().profession;
});

// Brain Spark — synchronous, already loaded at startup
final brainSparkProvider = Provider<BrainSparkFact>((ref) {
  return BrainSparkService.instance.currentFact;
});

final subjectsProvider = FutureProvider<List<Subject>>((ref) async {
  const colors = [
    Color(0x267C5CDD),
    Color(0x2600C389),
    Color(0x26FFB800),
    Color(0x260EA5E9),
  ];

  // Presentation mode: seeded subjects, no network.
  if (kPresentationMode) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return [
      for (var i = 0; i < kDemoSubjects.length; i++)
        Subject.fromJson(kDemoSubjects[i], colors[i % colors.length]),
    ];
  }

  // Geofence subjects by the student's state so the dashboard's
  // target_states scoping applies here too.
  final user = ref.read(currentUserProvider);
  final res = await CurriculumAPI.tree(state: user?.assignedState);
  final allNodes = res.data['nodes'] as List<dynamic>? ?? [];
  final rawSubjects = allNodes
      .where((n) => (n as Map<String, dynamic>)['node_type'] == 'subject')
      .toList();

  return [
    for (var i = 0; i < rawSubjects.length; i++)
      Subject.fromJson(
        rawSubjects[i] as Map<String, dynamic>,
        colors[i % colors.length],
      ),
  ];
});

// ═══════════════════════════════════════════════════════
// HOME SCREEN
// ═══════════════════════════════════════════════════════

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final firstName = user?.firstName ?? 'Student';
    final subjectsAsync = ref.watch(subjectsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show the geofenced sponsor ad as a full-screen overlay once per launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maybeShowSponsorInterstitial(context, ref);
    });

    final glassColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.04);
    final glassBorder = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);
    final mainTextColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final mutedTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ───────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                border: Border(
                  bottom: BorderSide(color: glassBorder, width: 1.5),
                ),
              ),
              // ✨ Mathematically forces the header below the status bar
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.paddingOf(context).top + 16, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(),
                            style: TextStyle(
                                fontFamily: 'Mukta',
                                fontSize: 15,
                                color: mutedTextColor),
                          ),
                          Text(
                            '$firstName 👋',
                            style: TextStyle(
                                fontFamily: 'Baloo2',
                                fontWeight: FontWeight.w800,
                                fontSize: 30,
                                color: mainTextColor),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.notifications_none_rounded,
                                color: mainTextColor, size: 28),
                            onPressed: () =>
                                context.push('/student/notifications'),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              border: Border.all(
                                  color: MitraColors.saffron, width: 2.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(user?.avatarEmoji ?? '🎒',
                                style: const TextStyle(fontSize: 28)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Class chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: MitraColors.saffron.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(MitraRadius.pill),
                      border: Border.all(
                          color: MitraColors.saffron.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '🏫 ${user?.classGrade ?? "Class IX"} · ${user?.assignedState ?? "India"}',
                      style: const TextStyle(
                          fontFamily: 'Mukta',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: MitraColors.saffron),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ✨ NEW: Grouped Stats Row + Massive Achievement Tag
                  Builder(builder: (context) {
                    final totalXp = (user?.totalXp ?? 0).toInt();

                    // Calculate the live tier based on XP
                    final currentTier = _galacticTiers.firstWhere(
                      (t) => totalXp >= t.minXp && totalXp < t.maxXp,
                      orElse: () => _galacticTiers.last,
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _StatChip('⭐ $totalXp XP', isDark),
                        const SizedBox(width: 8),
                        _StatChip('🔥 ${user?.currentStreakDays ?? 0} Streak',
                            isDark),
                        const SizedBox(width: 16),

                        // The dynamic tag — tap to open My Level
                        GestureDetector(
                          onTap: () => context.push('/student/achievements'),
                          child: _GlowingAchievementText(
                            title: currentTier.title,
                            color: currentTier.glowColor,
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                // ✨ Auto-calculates the bottom glass bar thickness
                padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 32),
                child: Column(
                  children: [
                    // Thought for the Day
                    const SizedBox(height: 8),
                    ref.watch(dailyMotivationProvider).when(
                          loading: () => const _LoadingCard(),
                          error: (_, __) => const _ErrorCard('Failed to load'),
                          data: (thought) {
                            final author =
                                ref.watch(quoteAuthorProvider).valueOrNull ??
                                    '';
                            return _ThoughtTile(
                              thought: thought,
                              author: author,
                            );
                          },
                        ),

                    // ⚡ Brain Spark
                    const SizedBox(height: 8),
                    _BrainSparkTile(
                      fact: ref.watch(brainSparkProvider),
                    ),

                    // Subjects
                    _Section(
                      title: 'Subjects',
                      child: subjectsAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: MitraColors.saffron)),
                        ),
                        error: (err, stack) => const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Failed to load subjects',
                              style: TextStyle(color: MitraColors.textMuted)),
                        ),
                        data: (subjects) => subjects.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No subjects found.',
                                    style: TextStyle(
                                        color: MitraColors.textMuted)),
                              )
                            : GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 1.2,
                                ),
                                itemCount: subjects.length,
                                itemBuilder: (ctx, i) =>
                                    _SubjectCard(subject: subjects[i]),
                              ),
                      ),
                    ),

                    // Continue Learning
                    _Section(
                      title: 'Continue Learning',
                      trailing: GestureDetector(
                        onTap: () => context.go('/student/learn'),
                        child: const Text('See all',
                            style: TextStyle(
                                fontSize: 12,
                                color: MitraColors.saffron,
                                fontFamily: 'Mukta')),
                      ),
                      child: GestureDetector(
                        onTap: () => context.go('/student/learn'),
                        child: const _ContinueLearningCard(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ), // ✨ FIX: This closes the SafeArea we added
    ); // ✨ FIX: This closes the Scaffold we added
  }
}

// ═══════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  final String text;
  final bool isDark;
  const _StatChip(this.text, this.isDark);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(MitraRadius.pill),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: Text(text,
            style: TextStyle(
                fontFamily: 'SpaceMono',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87)),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Section({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: MitraColors.textPrimary)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

class _ContinueLearningCard extends StatelessWidget {
  const _ContinueLearningCard();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(MitraRadius.sm),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                height: 3,
                decoration: const BoxDecoration(
                  color: MitraColors.saffron,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(MitraRadius.md),
                      topRight: Radius.circular(MitraRadius.md)),
                )),
            Padding(
              padding: const EdgeInsets.all(MitraSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SCIENCE · CHAPTER 3',
                      style: TextStyle(
                          fontFamily: 'Mukta',
                          fontSize: 10,
                          color: MitraColors.textMuted,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  const Text('Microscopy & Cell Structure',
                      style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: MitraColors.textPrimary)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(MitraRadius.pill),
                    child: const LinearProgressIndicator(
                      value: 0.65,
                      minHeight: 5,
                      backgroundColor: MitraColors.bgSurface,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(MitraColors.saffron),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('13/20 topics',
                          style: TextStyle(
                              fontFamily: 'Mukta',
                              fontSize: 12,
                              color: MitraColors.textMuted)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: MitraColors.gold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(MitraRadius.pill),
                          border: Border.all(
                              color: MitraColors.gold.withValues(alpha: 0.4)),
                        ),
                        child: const Text('+240 XP',
                            style: TextStyle(
                                fontFamily: 'SpaceMono',
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: MitraColors.gold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SubjectCard extends StatelessWidget {
  final Subject subject;
  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.go('/student/learn'),
        child: Container(
          padding: const EdgeInsets.all(MitraSpacing.md),
          decoration: BoxDecoration(
            color: subject.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(MitraRadius.md),
            border: Border.all(color: MitraColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subject.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 6),
              Text(subject.name,
                  style: const TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: MitraColors.textPrimary)),
              Text(
                  '${(subject.progress * 100).toInt()}% · ${subject.arCount} AR topics',
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 10,
                      color: MitraColors.textMuted)),
            ],
          ),
        ),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      child: const Center(
          child: CircularProgressIndicator(color: MitraColors.saffron)));
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard(this.message);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(message, style: TextStyle(color: Colors.red[300])));
}

// ── Thought Tile ───────────────────────────────────────
class _ThoughtTile extends ConsumerWidget {
  final String thought;
  final String author;

  const _ThoughtTile({
    required this.thought,
    required this.author,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final accentColor = ThemeHelper.getActiveHighlight(theme);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor.withValues(alpha: 0.12),
              accentColor.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '💭 Thought for the day',
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: FontWeight.w700, // Explicitly Big & Bold Title
                fontSize: 20,
                color: MitraColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              thought,
              style: const TextStyle(
                fontFamily: 'Courgette',
                fontSize: 17,
                fontWeight: FontWeight.w400, // Regular font weight
                color: MitraColors.textPrimary,
                height: 1.6,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            if (author.isNotEmpty)
              Text(
                '— $author',
                style: const TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 12,
                  fontWeight: FontWeight.w400, // Regular font weight
                  color: MitraColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ⚡ BRAIN SPARK TILE
// ═══════════════════════════════════════════════════════

class _SparkParticle extends StatefulWidget {
  final double left;
  final double top;
  final double fontSize;
  final double duration;
  final double delay;
  final String symbol;

  const _SparkParticle({
    required this.left,
    required this.top,
    required this.fontSize,
    required this.duration,
    required this.delay,
    required this.symbol,
  });

  @override
  State<_SparkParticle> createState() => _SparkParticleState();
}

class _SparkParticleState extends State<_SparkParticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: Duration(milliseconds: (widget.duration * 1000).round()),
      vsync: this,
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.10), weight: 25),
      TweenSequenceItem(tween: ConstantTween(0.10), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.10, end: 0.0), weight: 25),
    ]).animate(_ctrl);
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.2), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 0.8), weight: 50),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Positioned(
          left: widget.left,
          top: widget.top,
          child: Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Text(widget.symbol,
                  style: TextStyle(fontSize: widget.fontSize)),
            ),
          ),
        ),
      );
}

class _BrainSparkTile extends ConsumerWidget {
  final BrainSparkFact fact;

  const _BrainSparkTile({required this.fact});

  static const _symbols = [
    '⚡',
    '🔬',
    '💡',
    '🧪',
    '✨',
    '🔭',
    '🧬',
    '⭐',
    '💎',
    '🌀',
    '⚡',
    '💡',
    '🔬',
    '✨',
    '🌟',
    '🧪',
    '🔭',
    '⚡',
    '💡',
    '✨',
  ];
  static const _fontSizes = [
    14.0,
    18.0,
    12.0,
    16.0,
    13.0,
    17.0,
    15.0,
    12.5,
    14.5,
    16.5,
    13.5,
    18.0,
    12.0,
    15.0,
    14.0,
    17.5,
    13.0,
    16.0,
    12.5,
    15.5,
  ];
  static const _durations = [
    6.0,
    8.0,
    7.5,
    5.5,
    9.0,
    6.5,
    8.5,
    7.0,
    5.0,
    9.5,
    6.0,
    7.0,
    8.0,
    5.5,
    9.0,
    6.5,
    7.5,
    5.0,
    8.5,
    6.0,
  ];
  static const _delays = [
    0.0,
    1.0,
    2.0,
    3.0,
    4.0,
    0.5,
    1.5,
    2.5,
    3.5,
    4.5,
    0.2,
    1.2,
    2.2,
    3.2,
    4.2,
    0.7,
    1.7,
    2.7,
    3.7,
    4.7,
  ];

  List<({double left, double top})> _positions(double w, double h) {
    const phi = 0.6180339887;
    const count = 20;
    return List.generate(count, (i) {
      final frac = (i * phi) % 1.0;
      final left =
          frac < 0.5 ? frac * 0.20 * w : (0.80 + (frac - 0.5) * 0.40) * w;
      final top = (i / count) * h;
      return (left: left, top: top);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final accentColor = ThemeHelper.getActiveHighlight(theme);
    final slotLabel = BrainSparkService.instance.currentSlotLabel;
    final nextTime = BrainSparkService.instance.nextFactTime;
    final hoursLeft = nextTime.difference(DateTime.now()).inHours;
    final minsLeft = nextTime.difference(DateTime.now()).inMinutes % 60;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          const h = 200.0;
          final positions = _positions(w, h);

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var i = 0; i < 20; i++)
                _SparkParticle(
                  symbol: _symbols[i],
                  left: positions[i].left,
                  top: positions[i].top,
                  fontSize: _fontSizes[i],
                  duration: _durations[i],
                  delay: _delays[i],
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(alpha: 0.12),
                      accentColor.withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: accentColor.withValues(alpha: 0.24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text('⚡',
                                style: TextStyle(
                                    fontSize: 16, color: accentColor)),
                            const SizedBox(width: 6),
                            Text(
                              'BRAIN SPARK',
                              style: TextStyle(
                                fontFamily: 'Baloo2',
                                fontWeight: FontWeight.w700, // Big & Bold Title
                                fontSize: 15,
                                color: accentColor,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(MitraRadius.pill),
                            border: Border.all(
                                color: accentColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            slotLabel,
                            style: TextStyle(
                              fontFamily: 'SpaceMono',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Category chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(MitraRadius.pill),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text(
                        '${fact.emoji}  ${fact.category}',
                        style: const TextStyle(
                          fontFamily: 'Mukta',
                          fontSize: 11,
                          fontWeight: FontWeight.w400, // Regular font weight
                          color: MitraColors.textMuted,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // The fact
                    Text(
                      fact.fact,
                      style: const TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 14,
                        fontWeight:
                            FontWeight.w400, // Regular font weight (not bold)
                        color: MitraColors.textPrimary,
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Countdown footer
                    Row(
                      children: [
                        const Icon(Icons.schedule,
                            size: 12, color: MitraColors.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          hoursLeft > 0
                              ? 'Next fact in ${hoursLeft}h ${minsLeft}m'
                              : 'Next fact in ${minsLeft}m',
                          style: const TextStyle(
                            fontFamily: 'SpaceMono',
                            fontSize: 10,
                            fontWeight: FontWeight.w400, // Regular font weight
                            color: MitraColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════
// NEW: DYNAMIC ACHIEVEMENT CLASSES
// ═══════════════════════════════════════════════════════

class AchievementTier {
  final String title;
  final int minXp;
  final int maxXp;
  final Color glowColor;

  const AchievementTier(this.title, this.minXp, this.maxXp, this.glowColor);
}

const List<AchievementTier> _galacticTiers = [
  AchievementTier('Jigyasu', 0, 500, Color(0xFFCD7F32)),
  AchievementTier('Anveshak', 500, 2000, Color(0xFF94A3B8)),
  AchievementTier('Vidwan', 2000, 5000, Color(0xFFF59E0B)),
  AchievementTier('Acharya', 5000, 10000, Color(0xFF8B5CF6)),
  AchievementTier('Gyani', 10000, 999999, Color(0xFFFFD700)),
];

class _GlowingAchievementText extends StatefulWidget {
  final String title;
  final Color color;

  const _GlowingAchievementText({required this.title, required this.color});

  @override
  State<_GlowingAchievementText> createState() =>
      _GlowingAchievementTextState();
}

class _GlowingAchievementTextState extends State<_GlowingAchievementText>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    // 1.5 second breathing cycle
    _glowController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return Text(
          widget.title,
          style: TextStyle(
            fontFamily: 'Baloo2',
            fontWeight: FontWeight.w800,
            fontSize: 24, // ✨ Exactly double the 12pt text of the _StatChip
            color: widget.color, // ✨ Automatically matches active tier color
            shadows: [
              Shadow(
                color: widget.color.withValues(alpha: _pulse.value * 0.8),
                blurRadius: 15 * _pulse.value, // ✨ Breathing dynamic glow
              ),
            ],
          ),
        );
      },
    );
  }
}
