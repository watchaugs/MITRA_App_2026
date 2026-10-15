// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: AR Viewer — device-tier ROUTER.
// Picks the richest experience the phone can deliver flawlessly, then hands off
// to the one engine (WebArViewerScreen):
//   • low tier                    → viewer  (on-screen 3D, no camera)
//   • medium/high + .mind target  → marker  (textbook-page AR)
//   • medium/high, no target      → overlay (model over the live camera)
// Capable phones also get a silent Scene Viewer "Explore in your room" bonus.
//
// Asset URLs arrive as query params on the route, mirroring the existing ?glb=:
//   /student/ar/<topicId>?glb=<model>&mind=<target>&audio=<narration>
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/device_capability_provider.dart';
import '../../services/device_probe.dart';
import 'webar_viewer_screen.dart';

class ArViewerScreen extends ConsumerWidget {
  final String topicId;
  final String? modelUrl; // ?glb=
  final String? targetsUrl; // ?mind=  (compiled MindAR target)
  final String? audioUrl; // ?audio=
  final String? videoUrl; // ?video=
  final String? chromaColor; // ?chroma=  (hex; non-null = green-screen on)

  const ArViewerScreen({
    super.key,
    required this.topicId,
    this.modelUrl,
    this.targetsUrl,
    this.audioUrl,
    this.videoUrl,
    this.chromaColor,
  });

  // Bundled sample used only when no real model URL is supplied (demo mode).
  static const String _fallbackGlb =
      'https://modelviewer.dev/shared-assets/models/Astronaut.glb';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(deviceCapabilityProvider).maybeWhen(
          data: (r) => r.tier,
          orElse: () => DeviceTier.medium,
        );

    final model =
        (modelUrl != null && modelUrl!.isNotEmpty) ? modelUrl! : _fallbackGlb;
    final hasTarget = targetsUrl != null && targetsUrl!.isNotEmpty;

    final ArMode mode;
    if (tier == DeviceTier.low) {
      mode = ArMode.viewer; // weakest phones: on-screen 3D, no camera AR
    } else if (hasTarget) {
      mode = ArMode.marker; // textbook-page tracking
    } else {
      mode = ArMode.overlay; // camera passthrough
    }

    return WebArViewerScreen(
      topicId: topicId,
      modelUrl: model,
      targetsUrl: targetsUrl,
      audioUrl: audioUrl,
      videoUrl: videoUrl,
      chromaColor: chromaColor,
      mode: mode,
      allowExplore: tier != DeviceTier.low, // silent Scene Viewer bonus
    );
  }
}
