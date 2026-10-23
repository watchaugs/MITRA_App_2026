// ═══════════════════════════════════════════════════════════════════════════
// MITRA — AR tier launcher (Dart side of the native "mitra/ar" channel)
//
// File: lib/services/ar_launcher.dart
//
// Decides, per device, HOW to show anchored AR and launches it:
//   tier "arcore"       → launchSceneViewer(): true ARCore floor-anchored AR
//                         (drag/rotate/pinch handled natively by Scene Viewer)
//   tier "arcore_needs" → offer to install Google Play Services for AR, then
//                         Scene Viewer
//   tier "none"         → caller should use the in-app WebXR/viewer engine
//
// The WebView engine (assets/ar/engine.js) remains the in-app fallback and the
// simple 3D viewer; this service is only the NATIVE anchored path.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart';

enum ArTier { arcore, arcoreNeeds, none }

class ArLauncher {
  ArLauncher._();
  static final ArLauncher instance = ArLauncher._();

  static const MethodChannel _ch = MethodChannel('mitra/ar');

  /// Ask the native side what AR this device can do.
  Future<ArTier> tier() async {
    try {
      final String t = await _ch.invokeMethod('getArTier') as String? ?? 'none';
      switch (t) {
        case 'arcore':
          return ArTier.arcore;
        case 'arcore_needs':
          return ArTier.arcoreNeeds;
        default:
          return ArTier.none;
      }
    } on PlatformException {
      return ArTier.none;
    } on MissingPluginException {
      // Native channel not wired (e.g. iOS or older build) → fall back.
      return ArTier.none;
    }
  }

  /// Launch Google Scene Viewer (ARCore-backed, anchored to the floor).
  /// Returns true if it opened; false means the caller should fall back.
  Future<bool> launchSceneViewer({
    required String glbUrl,
    String title = 'MITRA AR',
  }) async {
    try {
      final bool ok = await _ch.invokeMethod('launchSceneViewer', {
        'glbUrl': glbUrl,
        'title': title,
      }) as bool? ?? false;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Kick off the ARCore (Play Services for AR) install/update flow.
  Future<void> ensureArCore() async {
    try {
      await _ch.invokeMethod('ensureArCore');
    } catch (_) {/* best-effort */}
  }
}
