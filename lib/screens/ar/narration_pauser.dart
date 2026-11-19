// Pauses an AR lesson's narration while MITRA is not on screen (phone Home
// button, app switcher, screen off) and resumes it when the student comes
// back. Used by every AR screen so narration never plays from the background.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

class NarrationPauser with WidgetsBindingObserver {
  NarrationPauser(this.player) {
    WidgetsBinding.instance.addObserver(this);
  }

  final AudioPlayer player;
  bool _pausedByUs = false;
  bool _off = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_off) return;
    switch (state) {
      case AppLifecycleState.inactive:
        break; // brief (pull-down shade, dialogs) — keep playing
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Remember only if it was actually playing (hidden → paused both
        // arrive; the second must not clear the flag).
        if (player.state == PlayerState.playing) {
          _pausedByUs = true;
          player.pause().catchError((_) {});
        }
        break;
      case AppLifecycleState.resumed:
        if (_pausedByUs) {
          _pausedByUs = false;
          player.resume().catchError((_) {});
        }
        break;
    }
  }

  /// Call from the screen's dispose(), before the player is released.
  void dispose() {
    _off = true;
    WidgetsBinding.instance.removeObserver(this);
  }
}
