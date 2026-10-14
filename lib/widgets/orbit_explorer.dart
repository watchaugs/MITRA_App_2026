// ═══════════════════════════════════════════════════════════════════════════
// widgets/orbit_explorer.dart
//
// MITRA "Orbit Explorer" — a theme-aware planet with two orbiting moons.
// Used in two places:
//   • OrbitLoader    — the app-wide loading animation between screens.
//   • OrbitErrorView — the friendly, child-centric "something went wrong"
//                      screen (offline / lesson missing / file won't open).
//
// Pure Flutter vector animation (CustomPaint). No images, tiny, works offline,
// and recolours itself to whichever MitraTheme is active via ThemeHelper.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme_provider.dart';

// Fixed playful accent colours (kept constant across themes so the buddy always
// has a splash of fun, on any background).
const Color _moonGold = Color(0xFFFFB800);
const Color _moonEmerald = Color(0xFF00C389);
const Color _funOrange = Color(0xFFFF6B35);
const Color _funViolet = Color(0xFFB57BFF);

/// The core animation: a shaded planet with a tilted ring and two moons
/// orbiting at different speeds. Drop it anywhere; it fills the given [size].
class OrbitAnimation extends ConsumerStatefulWidget {
  final double size;
  const OrbitAnimation({super.key, this.size = 140});

  @override
  ConsumerState<OrbitAnimation> createState() => _OrbitAnimationState();
}

class _OrbitAnimationState extends ConsumerState<OrbitAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final highlight = ThemeHelper.getActiveHighlight(theme);
    final ink = ThemeHelper.isLightTheme(theme)
        ? const Color(0xFF1A1A2E)
        : Colors.white;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _OrbitPainter(
            t: _c.value,
            planet: highlight,
            ink: ink,
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final double t; // 0..1 loop
  final Color planet;
  final Color ink;
  _OrbitPainter({required this.t, required this.planet, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.21; // planet radius

    // Gentle bob of the whole planet.
    final bob = math.sin(t * 2 * math.pi) * (size.height * 0.03);
    final planetCenter = Offset(cx, cy + bob);

    // ── Tilted orbit ring (faint) ──────────────────────────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.transform(Matrix4.rotationZ(-0.32).storage);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ink.withValues(alpha: 0.28);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 0.78,
        height: size.height * 0.30,
      ),
      ringPaint,
    );
    canvas.restore();

    // ── Planet body with a radial shade for a 3D feel ──────────────────────
    final planetRect = Rect.fromCircle(center: planetCenter, radius: r);
    final bodyShader = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      colors: [
        Colors.white,
        planet,
        _funViolet.withValues(alpha: 0.85),
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(planetRect);
    canvas.drawCircle(
      planetCenter,
      r,
      Paint()..shader = bodyShader,
    );

    // A soft highlight dot (specular) and a warm surface blob.
    canvas.drawCircle(
      planetCenter.translate(-r * 0.32, -r * 0.34),
      r * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      planetCenter.translate(r * 0.28, r * 0.22),
      r * 0.22,
      Paint()..color = _funOrange.withValues(alpha: 0.55),
    );

    // ── Two orbiting moons (different speeds/phase) ────────────────────────
    void moon(double speed, double phase, double orbit, double mr, Color col) {
      final a = (t * speed + phase) * 2 * math.pi;
      // Elliptical path (wider than tall) to match the tilted ring.
      final mx = cx + math.cos(a) * orbit;
      final my = cy + math.sin(a) * orbit * 0.42 + bob * 0.5;
      // Dim the moon when it's "behind" the planet (upper half of the loop).
      final behind = math.sin(a) < 0;
      canvas.drawCircle(
        Offset(mx, my),
        mr,
        Paint()..color = col.withValues(alpha: behind ? 0.45 : 1.0),
      );
    }

    moon(1.0, 0.0, size.width * 0.38, size.width * 0.045, _moonGold);
    moon(0.66, 0.4, size.width * 0.46, size.width * 0.035, _moonEmerald);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.t != t || old.planet != planet || old.ink != ink;
}

// ═══════════════════════════════════════════════════════════════════════════
// LOADER — use anywhere a spinner would go, between screens / while fetching.
// ═══════════════════════════════════════════════════════════════════════════

class OrbitLoader extends ConsumerWidget {
  final String? message;
  final double size;
  const OrbitLoader({super.key, this.message, this.size = 110});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitAnimation(size: size),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Mukta',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ThemeHelper.textSecondary(theme),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ERROR VIEW — friendly, child-centric. Never shows a wrong 3D model.
// ═══════════════════════════════════════════════════════════════════════════

enum OrbitErrorType {
  offline, // no internet
  missing, // model file not found (404)
  broken, // file failed to load / parse
  comingSoon, // state is covered, but nothing released yet
  unavailable, // outside MITRA's approved territory (geofence)
}

class _ErrorCopy {
  final String msg;
  final String sub;
  const _ErrorCopy(this.msg, this.sub);
}

const Map<OrbitErrorType, _ErrorCopy> _copy = {
  OrbitErrorType.offline: _ErrorCopy(
    "You're off the grid!",
    "We can't reach this lesson right now. Check your internet and tap Try again.",
  ),
  OrbitErrorType.missing: _ErrorCopy(
    "This lesson is still cooking!",
    "We couldn't find this 3D lesson yet. It may be on its way — check back soon.",
  ),
  OrbitErrorType.broken: _ErrorCopy(
    "A piece got jumbled",
    "This lesson didn't open properly. Give it another go!",
  ),
  OrbitErrorType.comingSoon: _ErrorCopy(
    "New adventures are on the way! 🚀",
    "Your 3D lessons are being packed for launch — check back soon!",
  ),
  OrbitErrorType.unavailable: _ErrorCopy(
    "You're exploring from outside MITRA's map! 🗺️",
    "These 3D lessons aren't available in your area yet — they're rolling out to new regions soon.",
  ),
};

class OrbitErrorView extends ConsumerWidget {
  final OrbitErrorType type;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  const OrbitErrorView({
    super.key,
    required this.type,
    this.onRetry,
    this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final highlight = ThemeHelper.getActiveHighlight(theme);
    final bg = ThemeHelper.getBackgroundGradient(theme);
    final isLight = ThemeHelper.isLightTheme(theme);
    final copy = _copy[type]!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bg,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OrbitAnimation(size: 150),
              const SizedBox(height: 18),
              Text(
                copy.msg,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ThemeHelper.textPrimary(theme),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                copy.sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 13.5,
                  height: 1.45,
                  color: ThemeHelper.textSecondary(theme),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRetry != null)
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: highlight,
                        foregroundColor: isLight ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontFamily: 'Mukta',
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                    ),
                  if (onRetry != null && onBack != null)
                    const SizedBox(width: 10),
                  if (onBack != null)
                    OutlinedButton(
                      onPressed: onBack,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ThemeHelper.textPrimary(theme),
                        side: BorderSide(
                            color: ThemeHelper.textPrimary(theme)
                                .withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontFamily: 'Mukta',
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                      child: const Text('Go back'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY VIEW — for the Learn tab when no lessons are released yet, or the
// student is outside MITRA's approved territory. Same Orbit buddy, playful
// message, no "Try again" button (nothing to retry — it's just not here yet).
//
//   OrbitEmptyView(type: OrbitErrorType.comingSoon)   // state covered, none released
//   OrbitEmptyView(type: OrbitErrorType.unavailable)  // outside the geofenced area
// ═══════════════════════════════════════════════════════════════════════════

class OrbitEmptyView extends ConsumerWidget {
  final OrbitErrorType type;
  final double size;
  const OrbitEmptyView({
    super.key,
    this.type = OrbitErrorType.comingSoon,
    this.size = 130,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final copy = _copy[type]!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OrbitAnimation(size: size),
            const SizedBox(height: 16),
            Text(
              copy.msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Mukta',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ThemeHelper.textPrimary(theme),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              copy.sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Mukta',
                fontSize: 13.5,
                height: 1.45,
                color: ThemeHelper.textSecondary(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
