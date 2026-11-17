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

const double _cw = 84, _ch = 110; // Chiku canvas

const String _chikuBody =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 84 110">'
    '<path d="M42 -60 L42 22" stroke="#16A34A" stroke-width="3"/>'
    '<path d="M38 -20 C30 -22 28 -14 34 -12Z" fill="#22C55E"/>'
    '<ellipse cx="42" cy="76" rx="15" ry="17" fill="#92400E" stroke="#5B2A0A" stroke-width="1.2"/>'
    '<ellipse cx="42" cy="80" rx="9" ry="10" fill="#FCD9B6"/>'
    '<path d="M36 62 C34 48 39 34 42 24" stroke="#92400E" stroke-width="5" fill="none" stroke-linecap="round"/>'
    '<circle cx="42" cy="23" r="3.2" fill="#FCD9B6"/>'
    '<path d="M54 70 C60 74 64 80 66 86" stroke="#92400E" stroke-width="5" fill="none" stroke-linecap="round"/>'
    '<circle cx="67" cy="88" r="3.2" fill="#FCD9B6"/>'
    '<path d="M64 90 C66 98 74 98 76 92 C72 94 68 94 66 90Z" fill="#FACC15" stroke="#A16207" stroke-width="0.8"/>'
    '<path d="M34 92 L30 104 M50 92 L54 104" stroke="#92400E" stroke-width="5" stroke-linecap="round"/>'
    '<circle cx="25" cy="46" r="6.5" fill="#92400E"/><circle cx="25" cy="46" r="3.8" fill="#FCD9B6"/>'
    '<circle cx="59" cy="46" r="6.5" fill="#92400E"/><circle cx="59" cy="46" r="3.8" fill="#FCD9B6"/>'
    '<circle cx="42" cy="48" r="15" fill="#92400E" stroke="#5B2A0A" stroke-width="1.2"/>'
    '<path d="M31 49 C31 40 38 39 42 43 C46 39 53 40 53 49 C53 58 31 58 31 49Z" fill="#FCD9B6"/>'
    '<path d="M37 54 Q42 58 47 54" stroke="#1C1917" stroke-width="1.3" fill="none" stroke-linecap="round"/>'
    '<circle cx="33" cy="54" r="1.8" fill="#F9A8D4" opacity="0.7"/><circle cx="51" cy="54" r="1.8" fill="#F9A8D4" opacity="0.7"/>'
    '<path d="M36 34 C38 30 42 30 44 33" stroke="#5B2A0A" stroke-width="1.4" fill="none"/>'
    '</svg>';

const String _chikuTail =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 84 110">'
    '<path d="M54 86 C74 86 78 66 68 60 C62 66 66 76 56 80" stroke="#7C2D12" stroke-width="4" fill="none" stroke-linecap="round"/>'
    '</svg>';

const String _chikuEyes =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 84 110">'
    '<ellipse cx="37" cy="48" rx="2.2" ry="2.6" fill="#1C1917"/><ellipse cx="47" cy="48" rx="2.2" ry="2.6" fill="#1C1917"/>'
    '<circle cx="37.8" cy="47.2" r="0.8" fill="#FFFFFF"/><circle cx="47.8" cy="47.2" r="0.8" fill="#FFFFFF"/>'
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
              alignment: const Alignment(0.3, 0.55),
              child: layer(_chikuTail)),
          layer(_chikuBody),
          Transform(
            alignment: const Alignment(0, -0.13),
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
  static const _throwAt = [0.20, 0.30, 0.40, 0.46, 0.52, 0.58, 0.66, 0.74];
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

  @override
  void paint(Canvas canvas, Size size) {
    const life = 0.3; // fraction of the flight a banana stays visible
    for (final b in bananas) {
      final age = (t - b.born) / life;
      if (age < 0 || age > 1) continue;
      // Thrown up and out, falling back under gravity.
      final p = b.from +
          Offset(b.vel.dx * age * life,
              b.vel.dy * age * life + 900 * age * age * life * life);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(b.spin * age);
      final sc = 0.9 + age * 0.6;
      canvas.scale(sc, sc);
      final alpha = (1 - age).clamp(0.0, 1.0);
      final peel = Path()
        ..moveTo(-16, -4)
        ..cubicTo(-10, 10, 10, 10, 16, -6)
        ..cubicTo(12, 0, -4, 2, -12, -4)
        ..close();
      canvas.drawPath(peel,
          Paint()..color = const Color(0xFFFACC15).withValues(alpha: alpha));
      canvas.drawPath(
          peel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = const Color(0xFFA16207).withValues(alpha: alpha));
      canvas.drawLine(
          const Offset(15, -6),
          const Offset(18, -9),
          Paint()
            ..color = const Color(0xFF713F12).withValues(alpha: alpha)
            ..strokeWidth = 2.2);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BananaPainter old) => true;
}
