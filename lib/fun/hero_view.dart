// ═══════════════════════════════════════════════════════════════════════════
// Animated MITRA hero ("Bio-tech armour" look, hero_biotech.dart): breathes,
// cape sways, light lines pulse, eyes blink, Gyani aura spins.
// Tap = power move (1.6 s): crouch → launch with a chest flash and visor flare
// → sparks and a shockwave at the top → land with a ground impact.
// Code-drawn, works offline.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'hero_biotech.dart';
import 'hero_catalog.dart';

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
    final w = widget.height * kBioW / kBioH;
    final heroes = team
        ? [
            _OneHero(
                key: _keys[0],
                hero: widget.hero,
                girl: false,
                level: widget.level,
                width: w * .8,
                height: widget.height * .8),
            _OneHero(
                key: _keys[1],
                hero: widget.hero,
                girl: true,
                level: widget.level,
                width: w * .8,
                height: widget.height * .8,
                phase: .5),
          ]
        : [
            _OneHero(
                key: _keys[0],
                hero: widget.hero,
                girl: widget.gender == HeroGender.girl,
                level: widget.level,
                width: w,
                height: widget.height),
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
  late BiotechLayers _layers;
  late final AnimationController _loop; // breathe + cape + aura + glow pulse
  late final AnimationController _blink;
  late final AnimationController _power;
  Timer? _blinkTimer;
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _layers =
        buildBiotechLayers(widget.hero, girl: widget.girl, level: widget.level);
    _loop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200))
      ..value = widget.phase
      ..repeat();
    _blink = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160));
    _power = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer =
        Timer(Duration(milliseconds: 2400 + _rnd.nextInt(2600)), () async {
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
    if (old.hero != widget.hero ||
        old.girl != widget.girl ||
        old.level != widget.level) {
      _layers = buildBiotechLayers(widget.hero,
          girl: widget.girl, level: widget.level);
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
      : SvgPicture.string(s,
          width: widget.width, height: widget.height, fit: BoxFit.contain);

  // A point of the 400 × 600 canvas as an Alignment of this box.
  static Alignment _at(double x, double y) =>
      Alignment(x / 200 - 1, y / 300 - 1);

  // Power-move keyframes: [progress 0..1, value], eased between.
  static double _kf(double p, List<List<double>> k) {
    if (p <= k.first[0]) return k.first[1];
    for (var i = 1; i < k.length; i++) {
      if (p <= k[i][0]) {
        final a = k[i - 1], b = k[i];
        final f = (p - a[0]) / (b[0] - a[0]);
        return a[1] + (b[1] - a[1]) * Curves.easeInOut.transform(f);
      }
    }
    return k.last[1];
  }

  static const _moveY = [
    [0.0, 0.0],
    [.12, 8.0],
    [.34, -74.0],
    [.52, -80.0],
    [.78, 0.0],
    [.88, -6.0],
    [1.0, 0.0]
  ];
  static const _sclX = [
    [0.0, 1.0],
    [.12, 1.04],
    [.34, .97],
    [.52, 1.0],
    [.78, 1.05],
    [.88, 1.0],
    [1.0, 1.0]
  ];
  static const _sclY = [
    [0.0, 1.0],
    [.12, .94],
    [.34, 1.05],
    [.52, 1.0],
    [.78, .94],
    [.88, 1.0],
    [1.0, 1.0]
  ];
  static const _tilt = [
    [0.0, 0.0],
    [.34, -3.0],
    [.52, 2.0],
    [.78, 0.0],
    [1.0, 0.0]
  ]; // degrees
  static const _flashO = [
    [0.0, 0.0],
    [.32, 0.0],
    [.40, .9],
    [.60, 0.0],
    [1.0, 0.0]
  ];
  static const _shockO = [
    [0.0, 0.0],
    [.34, 0.0],
    [.40, 1.0],
    [.70, 0.0],
    [1.0, 0.0]
  ];
  static const _shockS = [
    [0.0, .3],
    [.34, .3],
    [.40, .6],
    [.70, 4.2],
    [1.0, 4.2]
  ];
  static const _shock2O = [
    [0.0, 0.0],
    [.44, 0.0],
    [.50, 1.0],
    [.82, 0.0],
    [1.0, 0.0]
  ];
  static const _shock2S = [
    [0.0, .3],
    [.44, .3],
    [.50, .6],
    [.82, 3.4],
    [1.0, 3.4]
  ];
  static const _sparkO = [
    [0.0, 0.0],
    [.36, 0.0],
    [.44, 1.0],
    [.72, 0.0],
    [1.0, 0.0]
  ];
  static const _sparkS = [
    [0.0, .2],
    [.36, .2],
    [.44, 1.0],
    [.72, 2.4],
    [1.0, 2.4]
  ];
  static const _sparkR = [
    [0.0, 0.0],
    [.36, 0.0],
    [.44, 20.0],
    [.72, 60.0],
    [1.0, 60.0]
  ]; // degrees
  static const _vflareO = [
    [0.0, 0.0],
    [.26, 0.0],
    [.36, 1.0],
    [.56, 0.0],
    [1.0, 0.0]
  ];
  static const _impactO = [
    [0.0, 0.0],
    [.74, 0.0],
    [.80, 1.0],
    [1.0, 0.0]
  ];
  static const _impactS = [
    [0.0, .3],
    [.74, .3],
    [.80, .6],
    [1.0, 2.0]
  ];
  static const _capeSk = [
    [0.0, 0.0],
    [.30, 0.0],
    [.40, -6.0],
    [.60, 5.0],
    [.82, -2.0],
    [1.0, 0.0]
  ]; // degrees
  static const _capeSy = [
    [0.0, 1.0],
    [.30, 1.0],
    [.40, 1.1],
    [.60, .92],
    [.82, 1.04],
    [1.0, 1.0]
  ];

  static const _deg = math.pi / 180;

  // One power-move effect layer, faded and scaled around [a].
  Widget _fx(String svg, double opacity, double scale, Alignment a,
      [double turn = 0]) {
    if (svg.isEmpty || opacity <= 0.01) return const SizedBox.shrink();
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        alignment: a,
        child: Transform.rotate(
            angle: turn * _deg, alignment: a, child: _svg(svg)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aura = _svg(_layers.aura), ground = _svg(_layers.ground);
    final back = _svg(_layers.back), cape = _svg(_layers.cape);
    final body = _svg(_layers.body),
        glow = _svg(_layers.glow),
        eyes = _svg(_layers.eyes);
    final u = widget.height / kBioH; // one canvas unit in pixels
    final chest = _at(200, 222),
        feet = _at(200, 540),
        shoulders = _at(200, 182);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _blink, _power]),
        builder: (context, _) {
          final t = _loop.value * 2 * math.pi;
          final breathe = 1 + math.sin(t) * 0.012;
          final p = _power.value;
          final acting = p > 0 && p < 1;
          final capeSkew = math.sin(t * 1.3) * 0.05 +
              (acting ? _kf(p, _capeSk) * _deg : 0.0);
          final capeY = acting ? _kf(p, _capeSy) : 1.0;
          final pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 2));
          return Stack(clipBehavior: Clip.none, children: [
            if (_layers.aura.isNotEmpty)
              Positioned.fill(
                child: Transform.rotate(
                  alignment:
                      Alignment.center, // the aura rings' centre (200, 300)
                  angle: _loop.value * 2 * math.pi / 4,
                  child: aura,
                ),
              ),
            Positioned.fill(child: ground),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, acting ? _kf(p, _moveY) * u : 0.0),
                child: Transform.rotate(
                  angle: acting ? _kf(p, _tilt) * _deg : 0.0,
                  alignment: feet,
                  child: Transform(
                    alignment: feet,
                    transform: Matrix4.diagonal3Values(
                        acting ? _kf(p, _sclX) : 1.0,
                        (acting ? _kf(p, _sclY) : 1.0) * breathe,
                        1),
                    child: Stack(children: [
                      // Cape hangs from the shoulders (y 182 of 600).
                      Transform(
                        alignment: shoulders,
                        transform: Matrix4.skewX(capeSkew)
                            .multiplied(Matrix4.diagonal3Values(1, capeY, 1)),
                        child: cape,
                      ),
                      back,
                      body,
                      Opacity(opacity: acting ? 1.0 : pulse, child: glow),
                      // Eyes close around their centre line (y 113 of 600).
                      Transform(
                        alignment: _at(200, 113),
                        transform: Matrix4.diagonal3Values(
                            1, 1 - 0.9 * _blink.value, 1),
                        child: eyes,
                      ),
                      if (acting) ...[
                        _fx(_layers.vflare, _kf(p, _vflareO), 1, _at(200, 113)),
                        _fx(_layers.flash, _kf(p, _flashO), 1, chest),
                        _fx(_layers.shock, _kf(p, _shockO), _kf(p, _shockS),
                            chest),
                        _fx(_layers.shock2, _kf(p, _shock2O), _kf(p, _shock2S),
                            chest),
                        _fx(_layers.sparks, _kf(p, _sparkO), _kf(p, _sparkS),
                            chest, _kf(p, _sparkR)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
            if (acting)
              Positioned.fill(
                child: _fx(_layers.impact, _kf(p, _impactO), _kf(p, _impactS),
                    _at(200, 548)),
              ),
          ]);
        },
      ),
    );
  }
}
