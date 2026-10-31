// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: AR Viewer  —  built on Google <model-viewer> (model_viewer_plus).
//
// WHY THIS DESIGN:
//   Ground-plane AR ("place it on your floor, walk around it") needs ARCore — a
//   HARDWARE capability entry-level phones lack; no app can force it on.
//   model_viewer_plus wraps Google <model-viewer>, which handles this per-device:
//     • EVERY phone (budget included) → on-screen 3D with animation: rotate, zoom.
//     • ARCore phones → model-viewer ALSO shows its OWN built-in AR button
//       (bottom-right of the view) that launches ground-plane AR through Google's
//       proven flow. We deliberately keep that native button for AR entry because
//       it is guaranteed to work — we do not hand-wire AR activation.
//
//   On top of that we add a themed "3D | AR" segmented toggle that restyles to the
//   active app theme's accent colour. "3D View" is the default on-screen mode;
//   "View in Your Room" points the student to the native AR button and is enabled
//   only on AR-capable phones, so budget users clearly get 3D and capable users
//   get both.
//
// Route (unchanged): /student/ar/<topicId>?glb=<model>&audio=<narration>
// With no ?glb (demo mode) a bundled model is shown so AR works offline.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../constants/colors.dart';
import '../../theme/theme_provider.dart';
import '../../providers/device_capability_provider.dart';
import '../../services/device_probe.dart';

class ArViewerScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? modelUrl; // ?glb=  (Draco _lite.glb — needs a WASM decoder)
  final String? nativeModelUrl; // ?nglb=  (non-Draco _native.glb — no decoder)
  final String? targetsUrl; // ?mind=  (kept for route compatibility; unused)
  final String? audioUrl; // ?audio=
  final String? videoUrl; // ?video=
  final String? chromaColor; // ?chroma=

  const ArViewerScreen({
    super.key,
    required this.topicId,
    this.modelUrl,
    this.nativeModelUrl,
    this.targetsUrl,
    this.audioUrl,
    this.videoUrl,
    this.chromaColor,
  });

  // Bundled demo model (offline-safe). Drop any valid .glb into
  // assets/ar/models/ to use your own; this ships so AR always shows something.
  static const String _bundledDemoGlb = 'assets/ar/models/mitra_demo_spin.glb';

  @override
  ConsumerState<ArViewerScreen> createState() => _ArViewerScreenState();
}

class _ArViewerScreenState extends ConsumerState<ArViewerScreen> {
  final AudioPlayer _audio = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _startNarration();
  }

  // Narration is a SEPARATE file (glTF can't carry audio). The on-screen viewer
  // previously declared audioUrl but never played it — this plays it on open.
  Future<void> _startNarration() async {
    final url = widget.audioUrl;
    if (url == null || url.trim().isEmpty) return;
    try {
      await _audio.stop();
      await _audio.play(UrlSource(url.trim()));
    } catch (_) {/* narration is best-effort; never block the model */}
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final accent = ThemeHelper.getActiveHighlight(theme);

    // Only ARCore-capable phones get in-room AR; others clearly get on-screen 3D.
    final tier = ref.watch(deviceCapabilityProvider).maybeWhen(
          data: (r) => r.tier,
          orElse: () => DeviceTier.medium,
        );
    final arCapable = tier != DeviceTier.low;

    // model_viewer renders in a WebView. A Draco-compressed GLB (_lite.glb)
    // needs Google's decoder WASM fetched at runtime — on a restricted/offline
    // school phone that fails SILENTLY and the model area is just BLACK. The
    // non-Draco native tier (_native.glb, embedded JPEG textures) has no such
    // dependency, so prefer it here; fall back to the Draco url, then the demo.
    final nativeSrc = widget.nativeModelUrl?.trim();
    final dracoSrc = widget.modelUrl?.trim();
    final src = (nativeSrc != null && nativeSrc.isNotEmpty)
        ? nativeSrc
        : (dracoSrc != null && dracoSrc.isNotEmpty
            ? dracoSrc
            : ArViewerScreen._bundledDemoGlb);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 3D / AR surface ──────────────────────────────────────────────
          Positioned.fill(
            child: ModelViewer(
              key: ValueKey(src),
              src: src,
              alt: 'A 3D model for ${widget.topicId}',
              // ar:true → model-viewer shows its OWN built-in AR button on
              // capable phones (this is the AR entry point — guaranteed to work).
              ar: true,
              arModes: const ['scene-viewer', 'webxr', 'quick-look'],
              autoRotate: true,
              cameraControls: true,
              backgroundColor: const Color(0xFF0B0B12),
              // Autoplay animation + floor placement, set directly on the web
              // component (plain <model-viewer> attributes — no version-specific
              // Dart enums).
              relatedJs: '''
                const mv = document.querySelector('model-viewer');
                if (mv) {
                  mv.setAttribute('autoplay', '');
                  mv.setAttribute('ar-placement', 'floor');
                  mv.setAttribute('ar-scale', 'auto');
                  mv.setAttribute('shadow-intensity', '1');
                  mv.setAttribute('tone-mapping', 'neutral');
                  mv.setAttribute('exposure', '1.2');
                  mv.setAttribute('environment-image', 'neutral');
                }
              ''',
            ),
          ),

          // ── Top bar: close + topic chip ──────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.close,
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/student/learn');
                      }
                    },
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(MitraRadius.pill),
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.view_in_ar, color: accent, size: 14),
                        const SizedBox(width: 6),
                        const Text(
                          'AR Lesson',
                          style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom: theme-matched 3D | AR segmented toggle ───────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: _ModeToggle(
                accent: accent,
                arCapable: arCapable,
                onPickAr: () {
                  // The native model-viewer AR button is the real AR entry point.
                  // This toggle signals AR mode and guides the student to it.
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                            'Tap the AR icon on the model to place it in your room'),
                        duration: const Duration(seconds: 3),
                        backgroundColor: accent.withValues(alpha: 0.9),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Theme-aware segmented control: [ 3D View | View in Your Room ] ──────────
class _ModeToggle extends StatefulWidget {
  final Color accent;
  final bool arCapable;
  final VoidCallback onPickAr;
  const _ModeToggle({
    required this.accent,
    required this.arCapable,
    required this.onPickAr,
  });

  @override
  State<_ModeToggle> createState() => _ModeToggleState();
}

class _ModeToggleState extends State<_ModeToggle> {
  bool _ar = false; // false = 3D (default), true = AR

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(MitraRadius.pill),
        border: Border.all(color: a.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            label: '3D View',
            icon: Icons.threed_rotation,
            selected: !_ar,
            enabled: true,
            onTap: () => setState(() => _ar = false),
          ),
          _seg(
            label: 'View in Your Room',
            icon: Icons.view_in_ar,
            selected: _ar,
            enabled: widget.arCapable,
            onTap: () {
              setState(() => _ar = true);
              widget.onPickAr();
            },
          ),
        ],
      ),
    );
  }

  Widget _seg({
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final a = widget.accent;
    final fg =
        !enabled ? Colors.white30 : (selected ? Colors.black : Colors.white);
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            // The selected segment fills with the active theme's accent colour,
            // so the control matches whichever of the 5 themes is on.
            gradient: selected
                ? LinearGradient(colors: [a, a.withValues(alpha: 0.82)])
                : null,
            borderRadius: BorderRadius.circular(MitraRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}
