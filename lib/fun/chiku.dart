// ═══════════════════════════════════════════════════════════════════════════
// Chiku — MITRA's monkey guide.
//
// ChikuCorner: Chiku hangs from his vine in a corner. Anime cel-shaded look.
// The swing is a pendulum from the vine's knot above the corner: his body
// trails the gripping arm, his head stays level, tail and legs follow a beat
// later, he breathes and blinks, and once per swing he waves and grins. Every
// motion repeats on the same 4.8 s cycle, so nothing jumps when it loops.
//
// celebrateWithChiku(): he lets go, swings across the screen coming up close
// (zoomed in) while dancing and throwing bananas; when he is closest he squeezes
// his eyes shut, sticks his tongue out and wiggles a hand at his ear to tease,
// then swings back and settles in his corner. Any screen can call it (daily
// goal done, new card, hero levelled up). Code-drawn, works offline.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../packs/pack_store.dart';

// Corners currently on screen, oldest first. The newest one (e.g. Hero HQ
// pushed over Home) is the one the student is looking at.
final List<_ChikuCornerState> _activeCorners = [];

/// Asks the Chiku the student is looking at to do his celebration swing.
void celebrateWithChiku() {
  if (_activeCorners.isNotEmpty) _activeCorners.last._onCelebrate();
}

const double _cw = 300, _ch = 410; // Chiku canvas: viewBox 60 90 300 410

// A point of Chiku's drawing (400 × 600 design space) as an Alignment of the
// figure's box. The vine's knot (200, 34) sits above the box, out of view.
Alignment _pt(double x, double y) =>
    Alignment((x - 60) / 150 - 1, (y - 90) / 205 - 1);

// Anime cel-shaded Chiku, one SVG per moving part (same canvas, so they stack
// exactly): vine, tail, legs, body, waving arm, ears, head, eyes, smile, the
// arm gripping the vine — and the teasing face: eyes squeezed shut, open mouth
// and a tongue that wags.
const String _ckVine =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M200 0 C 196 60, 206 130, 204 196" stroke="#2F7D32" stroke-width="6" fill="none" stroke-linecap="round"/><path d="M200 44 C 186 38 182 54 198 56 Z M205 110 C 220 102 224 120 207 122 Z M201 158 C 186 152 183 168 199 169 Z" fill="#4ADE80" stroke="#14532D" stroke-width="1.2"/></svg>';
const String _ckTail =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M238 392 C 296 404, 326 360, 306 326 C 292 304, 266 312, 274 332 C 280 344, 292 340, 290 332" stroke="#2A140A" stroke-width="14.0" fill="none" stroke-linecap="round"/><path d="M238 392 C 296 404, 326 360, 306 326 C 292 304, 266 312, 274 332 C 280 344, 292 340, 290 332" stroke="#9A5322" stroke-width="9" fill="none" stroke-linecap="round"/></svg>';
const String _ckLegs =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M184 408 C 176 428, 168 446, 166 462" stroke="#2A140A" stroke-width="22.0" fill="none" stroke-linecap="round"/><path d="M184 408 C 176 428, 168 446, 166 462" stroke="#B5652A" stroke-width="17" fill="none" stroke-linecap="round"/><path d="M226 408 C 234 428, 244 444, 248 458" stroke="#2A140A" stroke-width="22.0" fill="none" stroke-linecap="round"/><path d="M226 408 C 234 428, 244 444, 248 458" stroke="#B5652A" stroke-width="17" fill="none" stroke-linecap="round"/><ellipse cx="164" cy="468" rx="13" ry="8" fill="#FFE3C4" stroke="#2A140A" stroke-width="2.5" transform="rotate(-20 164 468)"/><ellipse cx="250" cy="464" rx="13" ry="8" fill="#FFE3C4" stroke="#2A140A" stroke-width="2.5" transform="rotate(25 250 464)"/></svg>';
const String _ckBody =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M205 300 C 248 300, 262 340, 258 372 C 254 408, 232 420, 205 420 C 178 420, 152 408, 150 372 C 146 336, 166 300, 205 300 Z" fill="#B5652A" stroke="#2A140A" stroke-width="2.5"/><path d="M205 300 C 248 300, 262 340, 258 372 C 254 408, 232 420, 205 420 C 228 400, 240 360, 230 320Z" fill="#7A3A12" opacity=".35"/><path d="M205 326 C 230 326, 238 352, 236 374 C 234 398, 220 408, 205 408 C 190 408, 176 398, 174 374 C 172 352, 180 326, 205 326 Z" fill="#FFE3C4"/></svg>';
const String _ckWave =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M156 318 C 140 338, 128 356, 120 380" stroke="#2A140A" stroke-width="20.0" fill="none" stroke-linecap="round"/><path d="M156 318 C 140 338, 128 356, 120 380" stroke="#B5652A" stroke-width="15" fill="none" stroke-linecap="round"/><circle cx="119" cy="384" r="11" fill="#FFE3C4" stroke="#2A140A" stroke-width="2.5"/></svg>';
const String _ckEars =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M126 262 C 106 258, 98 276, 106 290 C 114 302, 132 298, 136 284" fill="#B5652A" stroke="#2A140A" stroke-width="2.5"/><path d="M246 262 C 266 258, 274 276, 266 290 C 258 302, 240 298, 236 284" fill="#B5652A" stroke="#2A140A" stroke-width="2.5"/><path d="M124 270 C 112 270 110 284 118 290 C 124 294 130 290 132 284Z M248 270 C 260 270 262 284 254 290 C 248 294 242 290 240 284Z" fill="#F7A9A0"/></svg>';
const String _ckHead =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M186 206 C 236 206, 252 240, 250 268 C 248 302, 222 322, 186 322 C 150 322, 124 302, 122 268 C 120 240, 136 206, 186 206 Z" fill="#B5652A" stroke="#2A140A" stroke-width="2.5"/><path d="M186 206 C 236 206, 252 240, 250 268 C 249 286, 240 300, 228 310 C 236 290, 236 250, 210 228 C 200 220, 192 214, 186 206Z" fill="#7A3A12" opacity=".35"/><path d="M168 210 Q 178 196 186 210 Q 194 194 204 210" stroke="#2A140A" stroke-width="2.5" fill="#B5652A"/><path d="M186 232 C 200 222, 226 228, 228 254 C 230 272, 222 282, 220 290 C 222 306, 206 316, 186 316 C 166 316, 150 306, 152 290 C 150 282, 142 272, 144 254 C 146 228, 172 222, 186 232 Z" fill="#FFE3C4"/><path d="M186 276 C 210 276, 222 288, 220 300 C 218 312, 204 318, 186 318 C 168 318, 154 312, 152 300 C 150 288, 162 276, 186 276 Z" fill="#FFEFD9"/><path d="M154 238 Q 166 232 178 238 M194 238 Q 206 232 218 238" stroke="#2A140A" stroke-width="3" fill="none" stroke-linecap="round"/><path d="M180 286 Q 186 282 192 286 Q 186 292 180 286Z" fill="#2A140A"/><ellipse cx="156" cy="294" rx="9" ry="5" fill="#FB7185" opacity="0.7"/><ellipse cx="216" cy="294" rx="9" ry="5" fill="#FB7185" opacity="0.7"/></svg>';
const String _ckEyes =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><ellipse cx="168" cy="258" rx="15" ry="18" fill="#FFFFFF"/><ellipse cx="204" cy="258" rx="15" ry="18" fill="#FFFFFF"/><circle cx="170" cy="261" r="10.8" fill="#7C3AED"/><circle cx="206" cy="261" r="10.8" fill="#7C3AED"/><circle cx="170" cy="262" r="6.3" fill="#120A06"/><circle cx="206" cy="262" r="6.3" fill="#120A06"/><circle cx="174" cy="255" r="4.2" fill="#FFFFFF"/><circle cx="210" cy="255" r="4.2" fill="#FFFFFF"/><circle cx="166" cy="266" r="2.0" fill="#FFFFFF"/><circle cx="202" cy="266" r="2.0" fill="#FFFFFF"/><path d="M160 247 l3 -6 l3 6 l-3 6Z M196 247 l3 -6 l3 6 l-3 6Z" fill="#fff"/></svg>';
const String _ckSquint =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M156 249 L 178 258 L 156 267 M216 249 L 194 258 L 216 267" stroke="#2A140A" stroke-width="4.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const String _ckSmile =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M168 298 Q 186 316 204 298 Q 186 306 168 298Z" fill="#E11D48" stroke="#2A140A" stroke-width="1.6" stroke-linejoin="round"/><path d="M181 302 L 191 302 L 190 307 L 182 307Z" fill="#FFFFFF"/></svg>';
const String _ckMouthOpen =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M166 296 Q 186 290 206 296 Q 204 316 186 318 Q 168 316 166 296Z" fill="#7F1D1D" stroke="#2A140A" stroke-width="2.5"/><path d="M174 297 L 182 297 L 181 302 L 175 302Z M190 297 L 198 297 L 197 302 L 191 302Z" fill="#FFFFFF"/></svg>';
const String _ckTongue =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M176 306 C 176 326, 182 338, 186 338 C 190 338, 196 326, 196 306 Z" fill="#FB7185" stroke="#2A140A" stroke-width="2.5"/><path d="M186 310 L 186 330" stroke="#E11D48" stroke-width="2" stroke-linecap="round"/><ellipse cx="181" cy="316" rx="3" ry="5" fill="#FFFFFF" opacity=".45"/></svg>';
const String _ckGrip =
    r'<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 90 300 410"><path d="M236 318 C 262 292, 264 236, 212 198" stroke="#2A140A" stroke-width="21.0" fill="none" stroke-linecap="round"/><path d="M236 318 C 262 292, 264 236, 212 198" stroke="#B5652A" stroke-width="16" fill="none" stroke-linecap="round"/><circle cx="207" cy="192" r="13" fill="#FFE3C4" stroke="#2A140A" stroke-width="2.5"/></svg>';

// Chiku's look from a content pack: a part replaced, colours swapped, a hat /
// glasses on his head, a scarf on his body. Worked out once per run.
final Map<String, String> _ckPartOf = {
  _ckVine: 'vine',
  _ckTail: 'tail',
  _ckLegs: 'legs',
  _ckBody: 'body',
  _ckWave: 'wave',
  _ckEars: 'ears',
  _ckHead: 'head',
  _ckEyes: 'eyes',
  _ckSquint: 'squint',
  _ckSmile: 'smile',
  _ckMouthOpen: 'mouth_open',
  _ckTongue: 'tongue',
  _ckGrip: 'grip',
};
final Map<String, String> _ckLook = {};
String _ck(String builtIn) {
  final part = _ckPartOf[builtIn];
  if (part == null) return builtIn;
  return _ckLook.putIfAbsent(part, () {
    final store = PackStore.instance;
    var s = store.chikuParts[part] ?? builtIn;
    final extra = part == 'head'
        ? store.chikuExtra('head_extra')
        : part == 'body'
            ? store.chikuExtra('body_extra')
            : '';
    if (extra.isNotEmpty) {
      final i = s.lastIndexOf('</svg>');
      if (i > 0) s = s.substring(0, i) + extra + s.substring(i);
    }
    store.chikuColors.forEach((from, to) {
      s = s.replaceAll(RegExp(RegExp.escape(from), caseSensitive: false), to);
    });
    return s;
  });
}

/// Chiku drawn once and posed: [phase] runs 0..1 through one 4.8 s swing.
class _ChikuFigure extends StatelessWidget {
  final double size; // height
  final double phase; // 0..1 through one swing loop
  final double blink; // 0 open .. 1 shut
  final double dance; // radians of whole-body wiggle (celebration)
  final double tease; // 0..1: tongue out, eyes squeezed, hand at his ear
  final double swing; // 1 = full pendulum, 0 = hanging still
  const _ChikuFigure({
    required this.size,
    required this.phase,
    this.blink = 0,
    this.dance = 0,
    this.tease = 0,
    this.swing = 1,
  });

  // Keyframes [phase, value], eased between.
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

  // Free arm: rests, then waves hello once per swing (degrees).
  static const _waveK = [
    [0.0, 0.0],
    [.48, 0.0],
    [.56, 128.0],
    [.62, 108.0],
    [.68, 132.0],
    [.74, 108.0],
    [.80, 128.0],
    [.90, 0.0],
    [1.0, 0.0]
  ];
  // Bigger grin while waving.
  static const _grinK = [
    [0.0, 0.0],
    [.48, 0.0],
    [.58, 1.0],
    [.82, 1.0],
    [.92, 0.0],
    [1.0, 0.0]
  ];

  @override
  Widget build(BuildContext context) {
    final w = size * _cw / _ch;
    final a = phase * 2 * math.pi;
    double deg(double d) => d * math.pi / 180;
    // Pendulum and follow-through (all whole multiples of the loop).
    final swingA = deg(13) * math.sin(a) * swing;
    final lagA = deg(7) * math.sin(a - .5) * swing;
    final headA = -deg(9) * math.sin(a - .15) * swing;
    final tailA =
        deg(15) * math.sin(a - 1.1) * swing + deg(6) * math.sin(3 * a);
    final legsA = deg(10) * math.sin(a - .8) * swing;
    final b = 0.5 + 0.5 * math.sin(2 * a); // breathing
    final ear = 0.5 + 0.5 * math.sin(4 * a);
    final waveDeg = _kf(phase, _waveK) * (1 - tease) +
        (120 + 10 * math.sin(12 * a)) * tease; // tease: hand wiggles at his ear
    final grin = _kf(phase, _grinK) * (1 - tease);
    final tongueA = deg(14) * math.sin(10 * a);

    Widget l(String s) => SvgPicture.string(_ck(s), width: w, height: size);
    Widget rot(double ang, double x, double y, Widget c) =>
        Transform.rotate(angle: ang, alignment: _pt(x, y), child: c);
    Widget scl(double sx, double sy, double x, double y, Widget c) => Transform(
        alignment: _pt(x, y),
        transform: Matrix4.diagonal3Values(sx, sy, 1),
        child: c);

    final teasing = tease > 0.5;
    return SizedBox(
      width: w,
      height: size,
      child: Transform.rotate(
        angle: dance,
        alignment: _pt(205, 300),
        child: rot(
          swingA, 200, 34, // from the vine's knot
          Stack(clipBehavior: Clip.none, children: [
            l(_ckVine),
            rot(
              lagA, 207, 192, // body trails the gripping hand
              Stack(clipBehavior: Clip.none, children: [
                rot(tailA, 238, 392, l(_ckTail)),
                rot(legsA, 204, 398, l(_ckLegs)),
                scl(1 + .02 * b, 1 - .015 * b, 205, 400, l(_ckBody)),
                rot(deg(waveDeg), 156, 318, l(_ckWave)),
                rot(
                  headA, 196, 305, // head stays level
                  Stack(clipBehavior: Clip.none, children: [
                    scl(1 + .03 * ear, 1 - .02 * ear, 186, 262, l(_ckEars)),
                    l(_ckHead),
                    if (teasing) ...[
                      l(_ckSquint),
                      l(_ckMouthOpen),
                      rot(tongueA, 186, 306, l(_ckTongue)),
                    ] else ...[
                      scl(1, 1 - 0.9 * blink, 186, 258, l(_ckEyes)),
                      scl(1 + .15 * grin, 1 + .35 * grin, 186, 300,
                          l(_ckSmile)),
                    ],
                  ]),
                ),
                l(_ckGrip),
              ]),
            ),
          ]),
        ),
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
        vsync: this, duration: const Duration(milliseconds: 4800))
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
              builder: (context, _) => _ChikuFigure(
                size: widget.size,
                phase: _idle.value,
                blink: _blink.value,
              ),
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
          // Closest to the screen (0.38–0.58): he teases — eyes squeezed,
          // tongue out and wagging, a hand wiggling at his ear.
          final tease = Curves.easeInOut.transform(
              ((t - 0.38) / 0.04).clamp(0.0, 1.0) *
                  ((0.58 - t) / 0.04).clamp(0.0, 1.0));
          final dancing = t > 0.36 && t < 0.62;
          final dance = dancing ? math.sin(t * 90) * 0.25 * (1 - tease) : 0.0;
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
                    size: h,
                    // 4.2 s flight on the 4.8 s swing clock
                    phase: (t * 4200 / 4800) % 1.0,
                    dance: dance,
                    tease: tease,
                    swing: 0.5),
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
