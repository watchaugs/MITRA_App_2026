// ═══════════════════════════════════════════════════════════════════════════
// Chiku — MITRA's monkey guide.
//
// ChikuCorner: Chiku hangs from his vine in a corner, swinging, blinking and
// curling his tail.
//
// celebrateWithChiku(): he lets go, swings across the screen coming up close
// (zoomed in) while dancing and throwing bananas, then swings back and settles
// in his corner. Any screen can call it (daily goal done, new card, hero
// levelled up). Code-drawn, works offline.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Corners currently on screen, oldest first. The newest one (e.g. Hero HQ
// pushed over Home) is the one the student is looking at.
final List<_ChikuCornerState> _activeCorners = [];

/// Asks the Chiku the student is looking at to do his celebration swing.
void celebrateWithChiku() {
  if (_activeCorners.isNotEmpty) _activeCorners.last._onCelebrate();
}

const double _cw = 120, _ch = 160; // Chiku canvas (storybook style)

// Storybook Chiku: big head, glossy eyes, fur strokes, toothy grin. Three
// layers (tail behind, body, eyes on top) so the tail can curl and the eyes
// can blink on their own.
const String _chikuBody =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 160">'
    // vine + leaves
    '<path d="M60 -60 L60 30" stroke="#15803D" stroke-width="4"/>'
    '<path d="M58 12 C46 7 43 19 56 20Z" fill="#22C55E" stroke="#15803D" stroke-width="1"/>'
    '<path d="M62 20 C74 15 77 27 64 28Z" fill="#4ADE80" stroke="#15803D" stroke-width="1"/>'
    // arm up, holding the vine
    '<path d="M50 92 C46 70 54 50 60 34" stroke="#8A4A1C" stroke-width="7" fill="none" stroke-linecap="round"/>'
    '<circle cx="60" cy="32" r="4.8" fill="#FAD4AE" stroke="#5B2A0A" stroke-width="1.3"/>'
    // body, belly, fur strokes
    '<ellipse cx="60" cy="116" rx="19" ry="21" fill="#A0522D" stroke="#4A2207" stroke-width="1.8"/>'
    '<ellipse cx="60" cy="121" rx="12" ry="13" fill="#FAD4AE"/>'
    '<path d="M45 106 l3 -3 M47 112 l3 -3 M73 106 l-3 -3 M71 112 l-3 -3" stroke="#6B3410" stroke-width="1.2" stroke-linecap="round"/>'
    // arm down + hand
    '<path d="M76 106 C84 112 88 118 90 126" stroke="#8A4A1C" stroke-width="7" fill="none" stroke-linecap="round"/>'
    '<circle cx="91" cy="129" r="4.8" fill="#FAD4AE" stroke="#5B2A0A" stroke-width="1.3"/>'
    // legs + feet
    '<path d="M51 134 L47 150 M69 134 L73 150" stroke="#8A4A1C" stroke-width="7" stroke-linecap="round"/>'
    '<ellipse cx="46" cy="152" rx="6" ry="3.5" fill="#FAD4AE" stroke="#5B2A0A" stroke-width="1"/>'
    '<ellipse cx="74" cy="152" rx="6" ry="3.5" fill="#FAD4AE" stroke="#5B2A0A" stroke-width="1"/>'
    // ears
    '<circle cx="32" cy="64" r="11" fill="#A0522D" stroke="#4A2207" stroke-width="1.6"/>'
    '<circle cx="32" cy="64" r="7" fill="#FAD4AE"/><circle cx="33" cy="65" r="3.5" fill="#E8A87C"/>'
    '<circle cx="88" cy="64" r="11" fill="#A0522D" stroke="#4A2207" stroke-width="1.6"/>'
    '<circle cx="88" cy="64" r="7" fill="#FAD4AE"/><circle cx="87" cy="65" r="3.5" fill="#E8A87C"/>'
    // head + fur tufts
    '<circle cx="60" cy="64" r="26" fill="#A0522D" stroke="#4A2207" stroke-width="1.8"/>'
    '<path d="M50 40 l2 4 M58 38 l1 4 M66 39 l-1 4 M72 43 l-2 3" stroke="#6B3410" stroke-width="1.3" stroke-linecap="round"/>'
    // face
    '<path d="M40 68 C40 52 52 50 60 57 C68 50 80 52 80 68 C80 86 40 86 40 68Z" fill="#FAD4AE" stroke="#C98B5E" stroke-width="1"/>'
    '<path d="M45 56 Q51 52 56 56 M64 56 Q69 52 75 56" stroke="#3B1A08" stroke-width="1.8" fill="none" stroke-linecap="round"/>'
    // nose, grin, tooth, cheeks
    '<ellipse cx="60" cy="74" rx="2.6" ry="1.6" fill="#5B2A0A"/>'
    '<path d="M52 78 Q60 86 68 78" stroke="#3B1A08" stroke-width="1.8" fill="#C2410C" stroke-linecap="round"/>'
    '<rect x="58" y="78.5" width="4" height="3" fill="#FFFFFF"/>'
    '<ellipse cx="43" cy="75" rx="3.6" ry="2.2" fill="#F9A8D4"/>'
    '<ellipse cx="77" cy="75" rx="3.6" ry="2.2" fill="#F9A8D4"/>'
    '</svg>';

const String _chikuTail =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 160">'
    '<path d="M78 124 C104 126 110 98 95 90 C87 98 93 110 79 115" stroke="#7A3A12" stroke-width="5.5" fill="none" stroke-linecap="round"/>'
    '<circle cx="95" cy="90" r="2.6" fill="#7A3A12"/>'
    '</svg>';

// Whole eyes (whites + pupils + shine) so a blink closes them fully.
const String _chikuEyes =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 160">'
    '<ellipse cx="51" cy="64" rx="6" ry="7" fill="#FFFFFF" stroke="#3B1A08" stroke-width="1"/>'
    '<ellipse cx="69" cy="64" rx="6" ry="7" fill="#FFFFFF" stroke="#3B1A08" stroke-width="1"/>'
    '<ellipse cx="52" cy="65" rx="4" ry="5" fill="#1C1917"/>'
    '<ellipse cx="70" cy="65" rx="4" ry="5" fill="#1C1917"/>'
    '<circle cx="53.5" cy="63" r="1.6" fill="#FFFFFF"/><circle cx="71.5" cy="63" r="1.6" fill="#FFFFFF"/>'
    '<circle cx="50.5" cy="67" r="0.8" fill="#FFFFFF"/><circle cx="68.5" cy="67" r="0.8" fill="#FFFFFF"/>'
    '</svg>';

/// Chiku drawn once, with an optional dance wiggle and blink amount.
class _ChikuFigure extends StatelessWidget {
  final double size; // height
  final double dance; // radians of body wiggle
  final double blink; // 0 open .. 1 shut
  final double tail; // radians of tail curl
  const _ChikuFigure(
      {required this.size, this.dance = 0, this.blink = 0, this.tail = 0});

  @override
  Widget build(BuildContext context) {
    final w = size * _cw / _ch;
    Widget layer(String s) => SvgPicture.string(s, width: w, height: size);
    return SizedBox(
      width: w,
      height: size,
      child: Transform.rotate(
        angle: dance,
        alignment: const Alignment(0, -0.6),
        child: Stack(clipBehavior: Clip.none, children: [
          Transform.rotate(
              angle: tail,
              alignment: const Alignment(0.32, 0.44), // tail base (79, 115)
              child: layer(_chikuTail)),
          layer(_chikuBody),
          Transform(
            alignment: const Alignment(0, -0.2), // eye line (y 64 of 160)
            transform: Matrix4.diagonal3Values(1, 1 - 0.9 * blink, 1),
            child: layer(_chikuEyes),
          ),
        ]),
      ),
    );
  }
}

/// Chiku hanging in a corner. Put it in a Stack (Positioned top-right).
class ChikuCorner extends StatefulWidget {
  final double size;
  const ChikuCorner({super.key, this.size = 92});

  @override
  State<ChikuCorner> createState() => _ChikuCornerState();
}

class _ChikuCornerState extends State<ChikuCorner>
    with TickerProviderStateMixin {
  late final AnimationController _idle;
  late final AnimationController _blink;
  Timer? _blinkTimer;
  bool _away = false; // hidden while his celebration flight is on screen
  OverlayEntry? _flight;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
    _blink = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scheduleBlink();
    _activeCorners.add(this);
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(
        Duration(milliseconds: 2500 + math.Random().nextInt(2500)), () async {
      if (!mounted) return;
      await _blink.forward(from: 0);
      if (!mounted) return;
      await _blink.reverse();
      if (mounted) _scheduleBlink();
    });
  }

  void _onCelebrate() {
    if (!mounted || _away) return;
    // Only the Chiku on the screen being looked at (never one under a
    // pushed screen, e.g. Home under a quiz).
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final box = context.findRenderObject() as RenderBox?;
    // Root overlay: he flies over the whole screen, bottom bar included.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (box == null || !box.hasSize || overlay == null) return;
    final home = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _away = true);
    _flight = OverlayEntry(
      builder: (_) => _ChikuFlight(
        home: home,
        size: widget.size,
        onDone: () {
          _flight?.remove();
          _flight = null;
          if (mounted) setState(() => _away = false);
        },
      ),
    );
    overlay.insert(_flight!);
  }

  @override
  void dispose() {
    _activeCorners.remove(this);
    _blinkTimer?.cancel();
    _flight?.remove();
    _idle.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size * _cw / _ch;
    return Semantics(
      label: 'Chiku the monkey',
      button: true,
      child: GestureDetector(
        onTap: _onCelebrate, // this Chiku, wherever he is
        child: SizedBox(
          width: w,
          height: widget.size,
          child: Opacity(
            opacity: _away ? 0.0 : 1.0,
            child: AnimatedBuilder(
              animation: Listenable.merge([_idle, _blink]),
              builder: (context, _) {
                final t = _idle.value * 2 * math.pi;
                return Transform.rotate(
                  angle: math.sin(t) * 0.17, // swings from the vine top
                  alignment: Alignment.topCenter,
                  child: _ChikuFigure(
                    size: widget.size,
                    blink: _blink.value,
                    tail: math.sin(t * 1.6) * 0.4,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// One keyframe of the flight: centre as a fraction of the screen (null = the
// corner), zoom and tilt.
class _Key {
  final double t, scale, rot;
  final double? fx, fy;
  const _Key(this.t, this.fx, this.fy, this.scale, this.rot);
}

const List<_Key> _path = [
  _Key(0.00, null, null, 1.0, 0),
  _Key(0.10, 0.62, 0.22, 1.5, -0.44),
  _Key(0.24, 0.20, 0.42, 2.4, 0.35),
  _Key(0.36, 0.50, 0.50, 3.3, -0.14),
  _Key(0.60, 0.50, 0.52, 3.4, 0.14), // dance close to the screen
  _Key(0.72, 0.78, 0.42, 2.2, -0.38),
  _Key(0.86, null, null, 1.3, 0.2),
  _Key(0.94, null, null, 1.05, -0.07),
  _Key(1.00, null, null, 1.0, 0),
];

class _Banana {
  final double born; // flight time 0..1
  final Offset from, vel; // px, px per flight
  final double spin;
  _Banana(this.born, this.from, this.vel, this.spin);
}

class _ChikuFlight extends StatefulWidget {
  final Rect home; // corner position on screen
  final double size;
  final VoidCallback onDone;
  const _ChikuFlight(
      {required this.home, required this.size, required this.onDone});

  @override
  State<_ChikuFlight> createState() => _ChikuFlightState();
}

class _ChikuFlightState extends State<_ChikuFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final List<_Banana> _bananas = [];
  int _thrown = 0;
  // Last throw at 0.58 so every banana finishes its arc (life 0.42) before
  // the flight ends, instead of vanishing mid-air.
  static const _throwAt = [0.18, 0.24, 0.30, 0.36, 0.42, 0.48, 0.54, 0.58];
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4200))
      ..addListener(_tick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  // Centre, zoom and tilt at flight time t.
  (Offset, double, double) _at(double t, Size screen) {
    Offset pos(_Key k) => k.fx == null
        ? widget.home.center
        : Offset(k.fx! * screen.width, k.fy! * screen.height);
    for (int i = 0; i < _path.length - 1; i++) {
      final a = _path[i], b = _path[i + 1];
      if (t <= b.t) {
        final u = Curves.easeInOut
            .transform(((t - a.t) / (b.t - a.t)).clamp(0.0, 1.0));
        return (
          Offset.lerp(pos(a), pos(b), u)!,
          a.scale + (b.scale - a.scale) * u,
          a.rot + (b.rot - a.rot) * u,
        );
      }
    }
    return (widget.home.center, 1.0, 0.0);
  }

  void _tick() {
    if (_thrown < _throwAt.length && _c.value >= _throwAt[_thrown]) {
      final screen = MediaQuery.sizeOf(context);
      final (c, s, _) = _at(_c.value, screen);
      final dir = _thrown.isEven ? -1.0 : 1.0;
      _bananas.add(_Banana(
        _c.value,
        c + Offset(widget.size * 0.25 * s * 0.4, widget.size * 0.2 * s * 0.4),
        Offset(dir * (180 + _rnd.nextDouble() * 220),
            -(260 + _rnd.nextDouble() * 260)),
        dir * (6 + _rnd.nextDouble() * 4),
      ));
      _thrown++;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final (c, scale, rot) = _at(t, screen);
          final dancing = t > 0.36 && t < 0.62;
          final dance = dancing ? math.sin(t * 90) * 0.25 : 0.0;
          final h = widget.size * scale;
          final w = h * _cw / _ch;
          return Stack(children: [
            CustomPaint(size: screen, painter: _BananaPainter(_bananas, t)),
            Positioned(
              left: c.dx - w / 2,
              top: c.dy - h / 2,
              child: Transform.rotate(
                angle: rot,
                child: _ChikuFigure(
                    size: h, dance: dance, tail: math.sin(t * 40) * 0.5),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _BananaPainter extends CustomPainter {
  final List<_Banana> bananas;
  final double t;
  _BananaPainter(this.bananas, this.t);

  // One banana, ~44 px wide before scaling, centred on (0, 0).
  static final Path _peel = Path()
    ..moveTo(-21, -7)
    ..cubicTo(-15, 13, 15, 13, 21, -9)
    ..cubicTo(15, 2, -6, 4, -17, -7)
    ..close();
  static final Path _ridge = Path()
    ..moveTo(-15, -2)
    ..cubicTo(-8, 8, 8, 8, 16, -5);
  static final Path _shine = Path()
    ..moveTo(-10, 5)
    ..quadraticBezierTo(0, 9, 10, 5);

  @override
  void paint(Canvas canvas, Size size) {
    const life = 0.42; // fraction of the flight a banana stays visible
    for (final b in bananas) {
      final age = (t - b.born) / life;
      if (age < 0 || age > 1) continue;
      // Thrown up and out, falling back under gravity.
      final p = b.from +
          Offset(b.vel.dx * age * life,
              b.vel.dy * age * life + 900 * age * age * life * life);
      // Solid for most of the throw; fades only in the last quarter.
      final a = age < 0.75 ? 1.0 : ((1 - age) / 0.25).clamp(0.0, 1.0);
      Color c(int argb) {
        final base = Color(argb);
        return base.withValues(alpha: base.a * a); // keeps a colour's own alpha
      }

      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(b.spin * age);
      final sc = 1.6 + age * 0.5; // big and easy to spot
      canvas.scale(sc, sc);
      // Soft shadow + white sticker edge: readable on light and dark screens.
      canvas.drawPath(
          _peel.shift(const Offset(1.5, 2.5)),
          Paint()
            ..color = c(0x40000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
      canvas.drawPath(
          _peel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.5
            ..strokeJoin = StrokeJoin.round
            ..color = c(0xFFFFFFFF));
      canvas.drawPath(_peel, Paint()..color = c(0xFFFDE047));
      canvas.drawPath(
          _ridge,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..color = c(0xFFEAB308));
      canvas.drawPath(
          _shine,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = c(0xCCFFFFFF));
      canvas.drawPath(
          _peel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeJoin = StrokeJoin.round
            ..color = c(0xFF854D0E));
      // Stem and dark tip.
      canvas.drawLine(
          const Offset(20, -9),
          const Offset(24, -15),
          Paint()
            ..strokeWidth = 3.4
            ..strokeCap = StrokeCap.round
            ..color = c(0xFF713F12));
      canvas.drawCircle(
          const Offset(-20, -7), 1.8, Paint()..color = c(0xFF422006));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BananaPainter old) => true;
}
