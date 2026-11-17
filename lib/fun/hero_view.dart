// ═══════════════════════════════════════════════════════════════════════════
// Animated MITRA hero: hovers, cape flutters, eyes blink, Gyani aura spins.
// Tap = power move (flies up with a spark burst). Code-drawn, works offline.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'hero_catalog.dart';
import 'hero_svg.dart';

class MitraHeroView extends StatefulWidget {
  final HeroDef hero;
  final HeroGender gender; // team = boy + girl side by side
  final int level; // costume level 0..4
  final double height;
  final bool tapForPower;

  const MitraHeroView({
    super.key,
    required this.hero,
    required this.gender,
    required this.level,
    this.height = 220,
    this.tapForPower = true,
  });

  @override
  State<MitraHeroView> createState() => _MitraHeroViewState();
}

class _MitraHeroViewState extends State<MitraHeroView> {
  final _keys = [GlobalKey<_OneHeroState>(), GlobalKey<_OneHeroState>()];

  void _power() {
    for (final k in _keys) {
      k.currentState?.power();
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.gender == HeroGender.team;
    final w = widget.height * kHeroW / kHeroH;
    final heroes = team
        ? [
            _OneHero(key: _keys[0], hero: widget.hero, girl: false, level: widget.level, width: w * .8, height: widget.height * .8),
            _OneHero(key: _keys[1], hero: widget.hero, girl: true, level: widget.level, width: w * .8, height: widget.height * .8, phase: .5),
          ]
        : [
            _OneHero(key: _keys[0], hero: widget.hero, girl: widget.gender == HeroGender.girl, level: widget.level, width: w, height: widget.height),
          ];
    return Semantics(
      label: heroName(widget.hero, widget.gender),
      button: widget.tapForPower,
      child: GestureDetector(
        onTap: widget.tapForPower ? _power : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: heroes),
      ),
    );
  }
}

class _OneHero extends StatefulWidget {
  final HeroDef hero;
  final bool girl;
  final int level;
  final double width, height;
  final double phase; // 0..1 offset so a team doesn't move in lockstep
  const _OneHero({
    super.key,
    required this.hero,
    required this.girl,
    required this.level,
    required this.width,
    required this.height,
    this.phase = 0,
  });

  @override
  State<_OneHero> createState() => _OneHeroState();
}

class _OneHeroState extends State<_OneHero> with TickerProviderStateMixin {
  late HeroLayers _layers;
  late final AnimationController _loop; // hover + cape + aura
  late final AnimationController _blink;
  late final AnimationController _power;
  Timer? _blinkTimer;
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _layers = buildHeroLayers(widget.hero, girl: widget.girl, level: widget.level);
    _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..value = widget.phase
      ..repeat();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
    _power = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2400 + _rnd.nextInt(2600)), () async {
      if (!mounted) return;
      await _blink.forward(from: 0);
      if (!mounted) return;
      await _blink.reverse();
      if (mounted) _scheduleBlink();
    });
  }

  void power() {
    if (!_power.isAnimating) _power.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _OneHero old) {
    super.didUpdateWidget(old);
    if (old.hero != widget.hero || old.girl != widget.girl || old.level != widget.level) {
      _layers = buildHeroLayers(widget.hero, girl: widget.girl, level: widget.level);
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _loop.dispose();
    _blink.dispose();
    _power.dispose();
    super.dispose();
  }

  Widget _svg(String s) => s.isEmpty
      ? const SizedBox.shrink()
      : SvgPicture.string(s, width: widget.width, height: widget.height, fit: BoxFit.contain);

  @override
  Widget build(BuildContext context) {
    final aura = _svg(_layers.aura), back = _svg(_layers.back), cape = _svg(_layers.cape);
    final body = _svg(_layers.body), eyes = _svg(_layers.eyes);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _blink, _power]),
        builder: (context, _) {
          final t = _loop.value * 2 * math.pi;
          final hover = math.sin(t) * widget.height * 0.02;
          final p = _power.value;
          // Power move: up and back with a little lean.
          final lift = p == 0 ? 0.0 : math.sin(p * math.pi) * widget.height * 0.15;
          final lean = p == 0 ? 0.0 : -math.sin(p * math.pi) * 0.1;
          final capeSkew = math.sin(t * 1.7) * 0.12;
          return Stack(clipBehavior: Clip.none, children: [
            if (_layers.aura.isNotEmpty)
              Positioned.fill(
                child: Transform.rotate(
                  // spins around the hero's chest (120, 170) of 240 × 320
                  alignment: const Alignment(0, 0.0625),
                  angle: _loop.value * 2 * math.pi / 6,
                  child: aura,
                ),
              ),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, hover - lift),
                child: Transform.rotate(
                  angle: lean,
                  alignment: Alignment.bottomCenter,
                  child: Stack(children: [
                    back,
                    // Cape hangs from the shoulders (y 112 of 320).
                    Transform(
                      alignment: const Alignment(0, -0.3),
                      transform: Matrix4.skewX(capeSkew)
                          .multiplied(Matrix4.diagonal3Values(1 + capeSkew.abs() * 0.3, 1, 1)),
                      child: cape,
                    ),
                    body,
                    // Eyes close around their centre line (y 70 of 320).
                    Transform(
                      alignment: const Alignment(0, -0.5625),
                      transform: Matrix4.diagonal3Values(1, 1 - 0.9 * _blink.value, 1),
                      child: eyes,
                    ),
                  ]),
                ),
              ),
            ),
            if (p > 0 && p < 1)
              Positioned.fill(
                child: CustomPaint(painter: _SparkPainter(p, widget.hero.accent)),
              ),
          ]);
        },
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final double t; // 0..1
  final Color accent;
  _SparkPainter(this.t, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.47);
    final reach = size.width * 0.55 * Curves.easeOut.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0);
    for (int i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final pt = c + Offset(math.cos(a), math.sin(a)) * reach;
      final paint = Paint()..color = (i.isEven ? accent : const Color(0xFFFDE68A)).withValues(alpha: fade);
      canvas.drawCircle(pt, size.width * 0.025 * (0.6 + t), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.t != t || old.accent != accent;
}
