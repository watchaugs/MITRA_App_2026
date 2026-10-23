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

class ArEntryScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? modelUrl;
  final String? audioUrl;
  final String? targetsUrl;
  final String? videoUrl;
  final String? chromaColor;

  const ArEntryScreen({
    super.key,
    required this.topicId,
    this.modelUrl,
    this.audioUrl,
    this.targetsUrl,
    this.videoUrl,
    this.chromaColor,
  });

  @override
  ConsumerState<ArEntryScreen> createState() => _ArEntryScreenState();
}

class _ArEntryScreenState extends ConsumerState<ArEntryScreen> {
  static const _ch = MethodChannel('mitra/device');
  bool _arCapable = false;
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
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: MitraColors.saffron),
        ),
      );
    }

    if (_arCapable) {
      return ArRoomScreen(
        topicId: widget.topicId,
        modelUrl: widget.modelUrl,
        audioUrl: widget.audioUrl,
      );
    }

    // Non-ARCore phone → on-screen 3D viewer (model_viewer).
    return ArViewerScreen(
      topicId: widget.topicId,
      modelUrl: widget.modelUrl,
      targetsUrl: widget.targetsUrl,
      audioUrl: widget.audioUrl,
      videoUrl: widget.videoUrl,
      chromaColor: widget.chromaColor,
    );
  }
}
