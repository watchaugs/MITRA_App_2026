// ═══════════════════════════════════════════════════════════════════════════
// Home card: streak power meter + today's goal (3-part ring) + missions,
// with Chiku hanging in its top-right corner. Follows the active app theme
// (glass surface + theme highlight), like every other card in the app.
// When today's goal completes: a POW! burst and Chiku's swing celebration.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/tr_ext.dart';
import '../services/achievement_engine.dart';
import '../theme/theme_provider.dart';
import 'chiku.dart';
import 'fun_progress.dart';

class HeroPowerCard extends ConsumerStatefulWidget {
  const HeroPowerCard({super.key});

  @override
  ConsumerState<HeroPowerCard> createState() => _HeroPowerCardState();
}

class _HeroPowerCardState extends ConsumerState<HeroPowerCard>
    with TickerProviderStateMixin {
  late final AnimationController _zap; // bolt pulse
  late final AnimationController _pow; // goal-complete burst

  @override
  void initState() {
    super.initState();
    _zap = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  }

  @override
  void dispose() {
    _zap.dispose();
    _pow.dispose();
    super.dispose();
  }

  void _maybeCelebrate(DailyGoal g) {
    final prefs = ref.read(sharedPreferencesProvider);
    if (takeGoalCelebration(prefs, g)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pow.forward(from: 0);
        celebrateWithChiku();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hl = Theme.of(context).colorScheme.primary;
    final tp = ThemeHelper.ctxTextPrimary(context);
    final ts = ThemeHelper.ctxTextSecondary(context);
    final streak = ref.watch(studentProfileProvider).valueOrNull?.currentStreakDays ?? 0;
    final goal = ref.watch(dailyGoalProvider);
    if (goal != null) _maybeCelebrate(goal);
    final lo = prevStreakMilestone(streak), hi = nextStreakMilestone(streak);
    final meter = hi == lo ? 1.0 : ((streak - lo) / (hi - lo)).clamp(0.0, 1.0);

    String missionText(Mission m) {
      switch (m.kind) {
        case MissionKind.watch:
          return context.trp(ref, 'fun_mission_watch', 'Watch: {title}', {'title': m.title});
        case MissionKind.quiz:
          return context.trp(ref, 'fun_mission_quiz', 'Answer the quiz: {title}', {'title': m.title});
        case MissionKind.revise:
          return context.tr(ref, 'fun_mission_revise', 'Replay any lesson or retry a quiz');
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: ThemeHelper.ctxGlassFill(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ThemeHelper.ctxGlassBorder(context)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AnimatedBuilder(
                animation: _zap,
                builder: (_, __) => Opacity(
                  opacity: 0.6 + 0.4 * _zap.value,
                  child: CustomPaint(size: const Size(34, 40), painter: _BoltPainter()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    context.trp(ref, 'fun_power_level', 'Power level {n}!', {'n': '$streak'}),
                    style: TextStyle(fontFamily: 'Baloo2', fontWeight: FontWeight.w800, fontSize: 20, color: tp),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: meter,
                      minHeight: 8,
                      color: hl,
                      backgroundColor: ThemeHelper.ctxGlassBorder(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.trp(ref, 'fun_power_next', '{left} more days to power level {next}',
                        {'left': '${hi - streak}', 'next': '$hi'}),
                    style: TextStyle(fontFamily: 'Mukta', fontSize: 12, color: ts),
                  ),
                ]),
              ),
              const SizedBox(width: 74), // room for Chiku
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 58,
                height: 58,
                child: CustomPaint(
                  painter: _GoalRingPainter(
                    total: goal?.total ?? kGoalCap,
                    done: goal?.doneCount ?? 0,
                    on: hl,
                    off: ThemeHelper.ctxGlassBorder(context),
                  ),
                  child: Center(
                    child: Text('${goal?.doneCount ?? 0}/${goal?.total ?? kGoalCap}',
                        style: TextStyle(fontFamily: 'SpaceMono', fontWeight: FontWeight.w700, fontSize: 13, color: tp)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    goal != null && goal.complete
                        ? context.tr(ref, 'fun_goal_done', "Today's goal done — super hero work!")
                        : context.tr(ref, 'fun_goal_today', "Today's hero missions"),
                    style: TextStyle(fontFamily: 'Mukta', fontWeight: FontWeight.w700, fontSize: 14, color: tp),
                  ),
                  const SizedBox(height: 4),
                  if (goal == null)
                    Text(context.tr(ref, 'fun_goal_loading', 'Getting your missions ready…'),
                        style: TextStyle(fontFamily: 'Mukta', fontSize: 12, color: ts))
                  else
                    for (int i = 0; i < goal.missions.length; i++)
                      InkWell(
                        onTap: () => context.go('/student/learn'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Icon(goal.done[i] ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                size: 16, color: goal.done[i] ? hl : ts),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(missionText(goal.missions[i]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: 'Mukta',
                                      fontSize: 12.5,
                                      color: goal.done[i] ? ts : tp,
                                      decoration: goal.done[i] ? TextDecoration.lineThrough : null)),
                            ),
                          ]),
                        ),
                      ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push('/student/heroes'),
                icon: Icon(Icons.shield_rounded, size: 18, color: hl),
                label: Text(context.tr(ref, 'fun_my_heroes', 'My heroes'),
                    style: TextStyle(fontFamily: 'Mukta', fontWeight: FontWeight.w700, color: hl)),
              ),
            ),
          ]),
        ),
        const Positioned(top: -6, right: 8, child: ChikuCorner(size: 92)),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pow,
              builder: (_, __) => _pow.value == 0 || _pow.value == 1
                  ? const SizedBox.shrink()
                  : CustomPaint(painter: _PowPainter(_pow.value, hl)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _BoltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(s.width * .62, 0)
      ..lineTo(s.width * .12, s.height * .56)
      ..lineTo(s.width * .45, s.height * .56)
      ..lineTo(s.width * .32, s.height)
      ..lineTo(s.width * .9, s.height * .38)
      ..lineTo(s.width * .55, s.height * .38)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFFFFD43B));
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFFB91C1C));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GoalRingPainter extends CustomPainter {
  final int total, done;
  final Color on, off;
  _GoalRingPainter({required this.total, required this.done, required this.on, required this.off});

  @override
  void paint(Canvas canvas, Size size) {
    final n = math.max(total, 1);
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 5);
    const gap = 0.14;
    final sweep = 2 * math.pi / n;
    for (int i = 0; i < n; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = i < done ? on : off,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GoalRingPainter o) =>
      o.total != total || o.done != done || o.on != on || o.off != off;
}

class _PowPainter extends CustomPainter {
  final double t;
  final Color hl;
  _PowPainter(this.t, this.hl);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .42);
    final grow = Curves.elasticOut.transform(t.clamp(0.0, 1.0));
    final fade = t < .7 ? 1.0 : (1 - (t - .7) / .3).clamp(0.0, 1.0);
    // Comic burst star.
    final r1 = 70 * grow, r2 = 44 * grow;
    final star = Path();
    for (int i = 0; i < 24; i++) {
      final r = i.isEven ? r1 : r2;
      final a = i * math.pi / 12 - math.pi / 2;
      final pt = c + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        star.moveTo(pt.dx, pt.dy);
      } else {
        star.lineTo(pt.dx, pt.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFFFD43B).withValues(alpha: fade));
    canvas.drawPath(
        star,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFB91C1C).withValues(alpha: fade));
    // Lightning sparks flying out.
    for (int i = 0; i < 10; i++) {
      final a = i * math.pi / 5;
      final d = 70 + 90 * t;
      final pt = c + Offset(math.cos(a), math.sin(a)) * d;
      canvas.drawCircle(pt, 5, Paint()..color = (i.isEven ? hl : const Color(0xFFEF4444)).withValues(alpha: fade));
    }
    final tp = TextPainter(
      text: TextSpan(
        text: 'POW!',
        style: TextStyle(
          fontFamily: 'Baloo2',
          fontWeight: FontWeight.w800,
          fontSize: 34 * grow.clamp(0.01, 2.0),
          color: const Color(0xFFB91C1C).withValues(alpha: fade),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PowPainter o) => o.t != t || o.hl != hl;
}
