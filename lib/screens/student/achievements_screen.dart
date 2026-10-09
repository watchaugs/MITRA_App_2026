// ═══════════════════════════════════════════════════════════════════════════
// achievements_screen.dart
//
// NOTE: This screen is hosted inside StudentShell, which already provides:
//   • LanguageAlphabetBackground (Positioned.fill behind all child routes)
//   • MitraScaffold with useSafeArea: false
//   • Bottom nav bar with glassmorphism
//   • Scroll padding injection via MediaQuery override
//
// Therefore this file must:
//   • NOT import or render LanguageAlphabetBackground (would double the effect)
//   • Use Scaffold(backgroundColor: Colors.transparent) so the shell's
//     background layer shows through correctly
//   • Use theme-aware colors (Theme.of(context).colorScheme) throughout
//     so the screen works in both dark and light MITRA themes
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/achievement_models.dart';
import '../../services/achievement_engine.dart';
import '../../stores/auth_store.dart';

// ── Tier Data Model ──────────────────────────────────────────────────────────

class AchievementTier {
  final String title;
  final String subtitle;
  final int minXp;
  final int maxXp;
  final String badgeEmoji;
  final int stars;
  final Color glowColor;

  const AchievementTier(
    this.title,
    this.subtitle,
    this.minXp,
    this.maxXp,
    this.badgeEmoji,
    this.stars,
    this.glowColor,
  );
}

const List<AchievementTier> _galacticTiers = [
  AchievementTier(
      'Jigyasu', 'The Curious', 0, 500, '🥉', 1, Color(0xFFCD7F32)), // Bronze
  AchievementTier('Anveshak', 'The Explorer', 500, 2000, '🥈', 2,
      Color(0xFF94A3B8)), // Silver
  AchievementTier('Vidwan', 'The Scholar', 2000, 5000, '✨', 3,
      Color(0xFFF59E0B)), // Warm Amber
  AchievementTier('Acharya', 'The Master', 5000, 10000, '🥇', 4,
      Color(0xFF8B5CF6)), // Amethyst
  AchievementTier('Gyani', 'The Enlightened', 10000, 999999, '💎', 5,
      Color(0xFFFFD700)), // Radiant Gold
];

// ── Root Screen ──────────────────────────────────────────────────────────────

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(studentProfileProvider);

    // IMPORTANT: backgroundColor must be transparent.
    // StudentShell's LanguageAlphabetBackground sits behind this route.
    // An opaque color here would hide the shell's background entirely.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        ),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Could not load achievements',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  e.toString(),
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => ref.invalidate(studentProfileProvider),
                  icon: const Icon(Icons.refresh, color: Color(0xFF8B5CF6)),
                  label: const Text(
                    'Retry',
                    style: TextStyle(color: Color(0xFF8B5CF6)),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          final totalXp = profile.totalXp.toInt();
          final streak =
              (ref.watch(currentUserProvider)?.currentStreakDays ?? 0).toInt();

          // Safe tier lookup: indexWhere returns -1 when no tier range
          // matches (e.g. XP >= 999999, the last tier's maxXp). Clamping -1
          // to 0 would incorrectly show the first tier (Jigyasu) for the
          // top student — instead we explicitly fall back to the last tier.
          final rawTierIndex = _galacticTiers
              .indexWhere((t) => totalXp >= t.minXp && totalXp < t.maxXp);
          final currentTierIndex =
              rawTierIndex == -1 ? _galacticTiers.length - 1 : rawTierIndex;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ThemedAchievementHeader(
                profile: profile,
                currentTier: _galacticTiers[currentTierIndex],
              ),
              Expanded(
                child: SingleChildScrollView(
                  // ✨ FIX: Dynamically calculate bottom padding to clear the StudentShell's bottom nav bar
                  padding: EdgeInsets.only(
                    top: 20,
                    bottom: MediaQuery.paddingOf(context).bottom +
                        100, // 100px provides ample clearance for the glass bottom bar
                  ),
                  child: Column(
                    children: List.generate(_galacticTiers.length, (index) {
                      final tier = _galacticTiers[index];
                      final isAchieved = index < currentTierIndex;
                      final isCurrent = index == currentTierIndex;
                      final isLocked = index > currentTierIndex;
                      final isLeftAligned = index % 2 == 0;

                      double progress = 0.0;
                      if (isAchieved) progress = 1.0;
                      if (isCurrent) {
                        progress =
                            ((totalXp - tier.minXp) / (tier.maxXp - tier.minXp))
                                .clamp(0.0, 1.0);
                      }

                      return Column(
                        children: [
                          _ConstellationNode(
                            tier: tier,
                            isLeftAligned: isLeftAligned,
                            isUnlocked: !isLocked,
                            isCurrent: isCurrent,
                            progress: progress,
                            totalXp: totalXp,
                            streak: streak,
                            nextTier: index < _galacticTiers.length - 1
                                ? _galacticTiers[index + 1]
                                : null,
                          ),
                          if (index < _galacticTiers.length - 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: AnimatedArrowConnector(
                                isUnlocked: !isLocked,
                                color: _galacticTiers[index + 1].glowColor,
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _ThemedAchievementHeader extends StatelessWidget {
  final StudentProfile profile;
  final AchievementTier currentTier;

  const _ThemedAchievementHeader(
      {required this.profile, required this.currentTier});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      // Extra top padding: MitraScaffold uses useSafeArea:false so this
      // screen extends behind the status bar. 50px clears it on most devices.
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: currentTier.glowColor, width: 2),
                  color: currentTier.glowColor.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Text(
                    currentTier.badgeEmoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // TODO: replace with profile.name when that field is added
                    'Cosmic Explorer',
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    currentTier.title,
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: currentTier.glowColor,
                      shadows: [
                        // ✅ Shadow (not BoxShadow) — correct type for TextStyle
                        Shadow(
                          color: currentTier.glowColor.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'TOTAL XP',
                style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${profile.totalXp.toInt()}',
                style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// FLOATING COSMIC TILES
// ═══════════════════════════════════════════════════════

class _ConstellationNode extends StatefulWidget {
  final AchievementTier tier;
  final bool isLeftAligned;
  final bool isUnlocked;
  final bool isCurrent;
  final double progress;
  final int totalXp;
  final int streak;
  final AchievementTier? nextTier;

  const _ConstellationNode({
    required this.tier,
    required this.isLeftAligned,
    required this.isUnlocked,
    required this.isCurrent,
    required this.progress,
    required this.totalXp,
    required this.streak,
    required this.nextTier,
  });

  @override
  State<_ConstellationNode> createState() => _ConstellationNodeState();
}

class _ConstellationNodeState extends State<_ConstellationNode>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _floatAnimation;

  // Unlocked tiles can be tapped to reveal personal progress details.
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    final int duration = 1200 + (widget.tier.minXp % 600);
    _glowController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.2).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _floatAnimation = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    if (widget.isUnlocked) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _ConstellationNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isUnlocked != oldWidget.isUnlocked) {
      if (widget.isUnlocked) {
        _glowController.repeat(reverse: true);
      } else {
        _glowController
          ..stop()
          ..reset();
        _expanded = false;
      }
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.tier;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final remaining =
        widget.nextTier == null ? 0 : widget.nextTier!.minXp - widget.totalXp;

    return Align(
      alignment:
          widget.isLeftAligned ? Alignment.centerLeft : Alignment.centerRight,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final double pulse = _pulseAnimation.value;
          final double clampedPulse = pulse.clamp(0.0, 1.0);

          return Transform.translate(
            offset: Offset(0, widget.isUnlocked ? _floatAnimation.value : 0),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              margin: EdgeInsets.only(
                left: widget.isLeftAligned ? 20 : 0,
                right: widget.isLeftAligned ? 0 : 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.isUnlocked
                      ? [
                          tier.glowColor.withValues(alpha: 0.15),
                          tier.glowColor.withValues(alpha: 0.05),
                        ]
                      : [
                          onSurface.withValues(alpha: 0.08),
                          onSurface.withValues(alpha: 0.02),
                        ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: widget.isCurrent
                      ? tier.glowColor
                          .withValues(alpha: 0.6 + (0.4 * clampedPulse))
                      : (widget.isUnlocked
                          ? tier.glowColor.withValues(alpha: 0.4 * clampedPulse)
                          : onSurface.withValues(alpha: 0.15)),
                  width: widget.isCurrent ? 2 : 1.5,
                ),
                boxShadow: widget.isUnlocked
                    ? [
                        BoxShadow(
                          color: tier.glowColor.withValues(
                              alpha: (widget.isCurrent ? 0.8 : 0.4) * pulse),
                          blurRadius: 16 * pulse,
                          spreadRadius: 0,
                          blurStyle: BlurStyle.outer,
                        ),
                      ]
                    : [],
              ),
              child: child,
            ),
          );
        },
        // Static card interior. Unlocked tiles tap to expand personal details.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isUnlocked
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Opacity(
              opacity: widget.isUnlocked ? 1.0 : 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.isUnlocked
                              ? tier.glowColor.withValues(alpha: 0.15)
                              : onSurface.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: widget.isUnlocked
                            ? Text(tier.badgeEmoji,
                                style: const TextStyle(fontSize: 28))
                            : Icon(Icons.lock,
                                color: onSurface.withValues(alpha: 0.5),
                                size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: List.generate(
                                tier.stars,
                                (i) => Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: Icon(Icons.star,
                                      color: tier.glowColor, size: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.tier.title,
                              style: TextStyle(
                                fontFamily: 'Baloo2',
                                fontWeight: FontWeight.w700,
                                fontSize: 26,
                                color: onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.isUnlocked)
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: onSurface.withValues(alpha: 0.5),
                          size: 24,
                        ),
                    ],
                  ),
                  if (widget.isCurrent) ...[
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: widget.progress,
                        minHeight: 10,
                        backgroundColor: onSurface.withValues(alpha: 0.1),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(tier.glowColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(widget.progress * 100).toInt()}% Explored',
                      style: TextStyle(
                        fontFamily: 'SpaceMono',
                        fontSize: 12,
                        color: tier.glowColor,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.isUnlocked
                          ? 'Coordinates Reached'
                          : 'Requires ${widget.tier.minXp} XP',
                      style: TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 13,
                        color: widget.isUnlocked
                            ? tier.glowColor
                            : onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],

                  // ── Expandable personal-progress details (unlocked only) ──
                  if (widget.isUnlocked && _expanded) ...[
                    const SizedBox(height: 20),
                    Divider(
                        color: onSurface.withValues(alpha: 0.12), height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            emoji: '⭐',
                            value: '${widget.totalXp}',
                            label: 'Total XP',
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MiniStat(
                            emoji: '🔥',
                            value: '${widget.streak}',
                            label: 'Day streak',
                            color: onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.nextTier == null
                          ? 'Highest level reached — Gyani 💎'
                          : remaining > 0
                              ? '$remaining XP to ${widget.nextTier!.title}'
                              : '${widget.nextTier!.title} already unlocked ✓',
                      style: TextStyle(
                        fontFamily: 'SpaceMono',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tier.glowColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Compact stat shown inside an expanded achievement tile ──
class _MiniStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  const _MiniStat({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: color)),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 10,
                  color: color.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ANIMATED ARROW CONNECTOR
// ═══════════════════════════════════════════════════════

class AnimatedArrowConnector extends StatefulWidget {
  final bool isUnlocked;
  // NOTE: `color` is accepted for call-site compatibility but is intentionally
  // unused at runtime. The connector cycles the full HSV spectrum when
  // unlocked for visual variety. To use the passed tier color instead,
  // replace `dynamicColor` in build() with `widget.color`.
  final Color color;

  const AnimatedArrowConnector(
      {super.key, required this.isUnlocked, required this.color});

  @override
  State<AnimatedArrowConnector> createState() => _AnimatedArrowConnectorState();
}

class _AnimatedArrowConnectorState extends State<AnimatedArrowConnector>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true); // reverse:true = smooth bob, not snap-back
    _float = Tween<double>(begin: -5.0, end: 5.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final dynamicColor =
            HSVColor.fromAHSV(1.0, _controller.value * 360, 0.7, 1.0).toColor();

        // Theme-aware locked color so arrow is visible in light mode too
        final displayColor = widget.isUnlocked
            ? dynamicColor
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1);

        return Transform.translate(
          offset: Offset(0, widget.isUnlocked ? _float.value : 0),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 48,
            color: displayColor,
            shadows: widget.isUnlocked
                ? [
                    Shadow(
                      color: displayColor.withValues(alpha: 0.6),
                      blurRadius: 15,
                    ),
                  ]
                : [],
          ),
        );
      },
    );
  }
}
