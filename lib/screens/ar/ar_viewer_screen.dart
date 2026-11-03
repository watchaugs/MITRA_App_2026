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
    debugPrint('🟣 ArViewerScreen OPENED — topicId=${widget.topicId} '
        'nativeUrl=${widget.nativeModelUrl} modelUrl=${widget.modelUrl}');
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

    final media = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      body: LayoutBuilder(
        builder: (context, c) {
          // Real PIXEL size for the WebView — not 100vh/100%, which evaluate
          // against the WebView's collapsed 150px default and stay 150px.
          final w = (c.maxWidth.isFinite && c.maxWidth > 0)
              ? c.maxWidth
              : media.width;
          final h = (c.maxHeight.isFinite && c.maxHeight > 0)
              ? c.maxHeight
              : media.height;
          final wPx = w.ceil();
          final hPx = h.ceil();

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ModelViewer(
                  key: ValueKey('$src-${wPx}x$hPx'),
                  src: src,
                  alt: 'A 3D model for ${widget.topicId}',
                  onWebViewCreated: (controller) {
                    debugPrint(
                        '🟣 ModelViewer WebView created (${wPx}x$hPx) for src=$src');
                  },
                  // AR is handled by the native ArRoomScreen (via the entry chooser),
                  // NOT by model-viewer's button: its WebXR mode is unsupported in
                  // Android WebView and crashes the app. Keep this view 3D-only.
                  ar: false,
                  autoRotate: true,
                  cameraControls: true,
                  backgroundColor: const Color(0xFF0B0B12),
                  // ROOT CAUSE: model_viewer_plus 1.8.0 injects relatedCss INSIDE
                  // the `model-viewer { ... }` rule. Passing full selector blocks
                  // nested them → they matched nothing → <model-viewer> fell back
                  // to its 150px Shadow-DOM default (the top strip). So pass ONLY
                  // bare properties here (they land on <model-viewer> correctly),
                  // with a fixed PIXEL height — not vh/% (which = 100% of 150px).
                  relatedCss: '''
                    position: fixed !important;
                    top: 0 !important;
                    left: 0 !important;
                    width: ${wPx}px !important;
                    height: ${hPx}px !important;
                    display: block !important;
                    --poster-color: transparent;
                  ''',
                  // html & body get no height from the package → size them here in
                  // explicit pixels via an injected top-level <style> (no nesting
                  // trap), reinforced by direct style sets each tick.
                  relatedJs: '''
                    (function () {
                      var s = document.createElement('style');
                      s.innerHTML =
                        'html,body{width:${wPx}px!important;height:${hPx}px!important;margin:0!important;padding:0!important;overflow:hidden!important;background:#0B0B12!important;}';
                      document.head.appendChild(s);
                      var n = 0;
                      var iv = setInterval(function () {
                        var mv = document.querySelector('model-viewer');
                        if (document.documentElement) {
                          document.documentElement.style.height = '${hPx}px';
                        }
                        if (document.body) {
                          document.body.style.height = '${hPx}px';
                        }
                        if (mv) {
                          mv.style.width = '${wPx}px';
                          mv.style.height = '${hPx}px';
                          mv.setAttribute('shadow-intensity', '1');
                          mv.setAttribute('exposure', '1.1');
                          window.dispatchEvent(new Event('resize'));
                        }
                        if (++n > 20) clearInterval(iv);
                      }, 100);
                    })();
                  ''',
                  minCameraOrbit: 'auto auto auto',
                  maxCameraOrbit: 'auto auto auto',
                  cameraOrbit: '0deg 75deg 105%',
                  fieldOfView: '30deg',
                  minFieldOfView: '25deg',
                  maxFieldOfView: '45deg',
                  cameraTarget: 'auto auto auto',
                  autoPlay: true,
                ),
              ),

              // ── Top bar: close + topic chip ──────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius:
                                BorderRadius.circular(MitraRadius.pill),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.5)),
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
              ),
            ],
          );
        },
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
