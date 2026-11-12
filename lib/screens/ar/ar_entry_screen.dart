// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: AR entry router — picks the experience by REAL AR capability.
//
//   ARCore available   → ArRoomScreen   (native ground-plane AR, walk around it)
//   ARCore absent       → ArViewerScreen (on-screen 3D + animation, every phone)
//
// Capability is checked via the native `mitra/device` channel's `checkArCore`
// (ArCoreApk.checkAvailability) — the definitive ARCore check, NOT RAM/tier.
// While checking, a brief loader shows. If ARCore needs installing, we ask the
// native side to trigger the install (ArCoreApk.requestInstall), then route to
// native AR.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/colors.dart';
import 'ar_room_screen.dart';
import 'ar_viewer_screen.dart';
import 'ar_marker_screen.dart';
import 'package:lottie/lottie.dart';
import '../../theme/theme_provider.dart';

class ArEntryScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? modelUrl; // Draco _lite.glb (the 3D viewer decodes Draco)
  final String? nativeModelUrl; // non-Draco _native.glb (native Filament AR)
  final String? audioUrl;
  final Map<String, String>? audios; // multi-language narration {lang: url}
  final Map<String, String>? audiosAac; // AAC fallback {lang: url}
  final String? targetsUrl;
  final String? videoUrl;
  final String? chromaColor;

  const ArEntryScreen({
    super.key,
    required this.topicId,
    this.modelUrl,
    this.nativeModelUrl,
    this.audioUrl,
    this.audios,
    this.audiosAac,
    this.targetsUrl,
    this.videoUrl,
    this.chromaColor,
  });

  @override
  ConsumerState<ArEntryScreen> createState() => _ArEntryScreenState();
}

enum _ViewMode { ar, viewer, marker }

class _ArEntryScreenState extends ConsumerState<ArEntryScreen> {
  static const _ch = MethodChannel('mitra/device');
  bool _arCapable = false;
  _ViewMode? _chosen; // null until the student picks AR or 3D
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    bool capable = false;
    try {
      // Returns one of: 'supported_installed', 'supported_apk_too_old',
      // 'supported_not_installed', 'unsupported', 'unknown', 'error'.
      final String status =
          await _ch.invokeMethod('checkArCore') as String? ?? 'unknown';
      if (status == 'supported_installed') {
        capable = true;
      } else if (status == 'supported_not_installed' ||
          status == 'supported_apk_too_old') {
        // Ask the native side to install/update Google Play Services for AR.
        // If the user completes it, the next AR open will be fully capable.
        try {
          final bool installed =
              await _ch.invokeMethod('requestArCoreInstall') as bool? ?? false;
          capable = installed;
        } catch (_) {
          capable = false;
        }
      }
    } on PlatformException {
      capable = false;
    } on MissingPluginException {
      capable = false; // channel not wired → safe 3D fallback
    }
    if (mounted) {
      setState(() {
        _arCapable = capable;
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: MitraColors.bgDeep,
        body: Center(
          child: CircularProgressIndicator(color: MitraColors.saffron),
        ),
      );
    }

    // A textbook-page marker is available for this lesson?
    final hasMarker = (widget.targetsUrl ?? '').isNotEmpty &&
        (widget.modelUrl ?? '').isNotEmpty;

    // Marker AR chosen → the WebView player (works on any camera phone).
    if (_chosen == _ViewMode.marker) {
      return ArMarkerScreen(
        topicId: widget.topicId,
        targetsUrl: widget.targetsUrl,
        modelUrl: widget.modelUrl,
      );
    }

    // Show the chooser when the phone can do room-AR OR the lesson has a marker
    // (so even non-ARCore phones get the chooser if "Scan page" is possible).
    if ((_arCapable || hasMarker) && _chosen == null) {
      return _ViewChooser(
        topicId: widget.topicId,
        arCapable: _arCapable,
        hasMarker: hasMarker,
        onPickAr: () => setState(() => _chosen = _ViewMode.ar),
        onPick3d: () => setState(() => _chosen = _ViewMode.viewer),
        onPickMarker: () => setState(() => _chosen = _ViewMode.marker),
      );
    }

    if (_arCapable && _chosen == _ViewMode.ar) {
      return ArRoomScreen(
        topicId: widget.topicId,
        modelUrl:
            (widget.nativeModelUrl != null && widget.nativeModelUrl!.isNotEmpty)
                ? widget.nativeModelUrl
                : widget.modelUrl,
        audioUrl: widget.audioUrl,
        audios: widget.audios,
        audiosAac: widget.audiosAac,
        // If native AR can't load the model, drop to the on-screen 3D viewer.
        onNativeLoadFailed: () {
          if (mounted) setState(() => _chosen = _ViewMode.viewer);
        },
      );
    }

    // Non-ARCore phone → on-screen 3D viewer (model_viewer).
    return ArViewerScreen(
      topicId: widget.topicId,
      modelUrl: widget.modelUrl,
      nativeModelUrl: widget.nativeModelUrl, // non-Draco → no black screen
      targetsUrl: widget.targetsUrl,
      audioUrl: widget.audioUrl,
      audios: widget.audios,
      audiosAac: widget.audiosAac,
      videoUrl: widget.videoUrl,
      chromaColor: widget.chromaColor,
    );
  }
}

// Chooser shown to AR-capable phones — fully theme-linked (bg, accent, cards).
class _ViewChooser extends ConsumerWidget {
  final String topicId;
  final bool arCapable;
  final bool hasMarker;
  final VoidCallback onPickAr;
  final VoidCallback onPick3d;
  final VoidCallback onPickMarker;
  const _ViewChooser({
    required this.topicId,
    required this.arCapable,
    required this.hasMarker,
    required this.onPickAr,
    required this.onPick3d,
    required this.onPickMarker,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final accent = ThemeHelper.getActiveHighlight(theme);
    final textPrimary = ThemeHelper.textPrimary(theme);
    final textSecondary = ThemeHelper.textSecondary(theme);

    return Scaffold(
      backgroundColor: MitraColors.bgDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 160,
                    child: Lottie.asset(
                      'assets/lotties/Earth globe rotating with Seamless loop animation.lottie',
                      fit: BoxFit.contain,
                      repeat: true,
                      decoder: LottieComposition.decodeZip,
                      errorBuilder: (_, __, ___) => Center(
                          child: CircularProgressIndicator(color: accent)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'How would you like to view this?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 28),
                  // Room AR only on ARCore-capable phones.
                  if (arCapable) ...[
                    _choiceCard(
                      icon: Icons.view_in_ar,
                      title: 'View in your room (AR)',
                      subtitle:
                          'Place the model on the floor and walk around it.',
                      onTap: onPickAr,
                      accent: accent,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _choiceCard(
                    icon: Icons.threed_rotation,
                    title: 'View on screen (3D)',
                    subtitle: 'Spin and zoom the model right on your screen.',
                    onTap: onPick3d,
                    accent: accent,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                  // Marker AR only when this lesson has a compiled page target.
                  if (hasMarker) ...[
                    const SizedBox(height: 14),
                    _choiceCard(
                      icon: Icons.menu_book,
                      title: 'Scan textbook page',
                      subtitle:
                          'Point your camera at the page to see the model on it.',
                      onTap: onPickMarker,
                      accent: accent,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
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

  Widget _choiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color accent,
    required Color textPrimary,
    required Color textSecondary,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(color: textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accent.withValues(alpha: 0.6)),
            ],
          ),
        ),
      );
}
