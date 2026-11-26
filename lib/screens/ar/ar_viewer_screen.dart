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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'narration_pauser.dart';
import 'narration_source.dart'; // narration saved on the phone → starts at once
import '../../services/ar_video_cache.dart'; // loopback server for kept files
import '../../services/topic_cache.dart'; // next / recent topics kept on the phone
import '../../constants/colors.dart';
import '../../services/achievement_engine.dart';
import '../../theme/theme_provider.dart';
import '../../stores/module_progress_store.dart';
import '../../services/language_options_service.dart';
import '../../services/geo_state_service.dart';
import '../../services/telemetry_batch_buffer.dart';
import '../../providers/telemetry_provider.dart';
import '../../services/telemetry_service.dart';
import '../auth/state_language_map.dart';
import '../../stores/auth_store.dart';
import '../../fun/fun_cards.dart'; // markEngaged (meets the subject hero)

import '../../providers/tr_ext.dart';
import '../../packs/pack_store.dart';

class ArViewerScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? modelUrl; // ?glb=  (Draco _lite.glb — needs a WASM decoder)
  final String? nativeModelUrl; // ?nglb=  (non-Draco _native.glb — no decoder)
  final String? targetsUrl; // ?mind=  (kept for route compatibility; unused)
  final String? audioUrl; // ?audio=
  final Map<String, String>? audios; // multi-language narration {lang: url}
  final Map<String, String>? audiosAac; // AAC fallback {lang: url}
  final String? videoUrl; // ?video=
  final String? chromaColor; // ?chroma=

  const ArViewerScreen({
    super.key,
    required this.topicId,
    this.modelUrl,
    this.nativeModelUrl,
    this.targetsUrl,
    this.audioUrl,
    this.audios,
    this.audiosAac,
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
  // The model from the phone when its topic is kept (loopback URL), checked
  // once before the viewer opens so it never starts a stream first.
  String? _localModel;
  bool _modelChecked = false;

  Future<void> _findLocalModel() async {
    String? local;
    try {
      final n = widget.nativeModelUrl?.trim();
      final d = widget.modelUrl?.trim();
      final remote = (n != null && n.isNotEmpty) ? n : d;
      final kept = await TopicCache.instance.pathFor(remote);
      if (kept != null) {
        local = await ArVideoCache.instance.urlForFile(kept);
      } else if (remote != null && remote.startsWith('/')) {
        // A lesson saved with "Save lessons offline" (the server refuses any
        // path outside the app's lesson folders).
        local = await ArVideoCache.instance.urlForFile(remote);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _localModel = local;
      _modelChecked = true;
    });
  }

  // AR-view XP through the same achievement engine as AR room (one XP path,
  // one set of analytics). Given once: when the narration (or page video) is
  // finished, or when the student has stayed 60 seconds.
  AchievementEngine? _xpEngine;
  bool _arXpGiven = false;
  void _giveArXp() {
    if (_arXpGiven) return;
    _arXpGiven = true;
    _xpEngine?.recordArView(widget.topicId);
  }

  final AudioPlayer _audio = AudioPlayer();
  // Pauses narration while the app is in the background.
  late final NarrationPauser _pauser;
  Duration? _audioDuration;
  // Set when the viewer is closing. A narration that is still buffering when
  // the student leaves would otherwise start playing AFTER the screen is gone.
  bool _closing = false;

  Future<void> _stopNarration() async {
    _closing = true;
    try {
      await _audio.stop();
    } catch (_) {}
  }

  // Multi-language narration.
  Map<String, String> _audios = const {};
  Map<String, String> _audiosAac = const {};
  List<String> _availableLangs = const [];
  String? _activeLang;

  Future<void> _resolveLanguages() async {
    if (_audios.isEmpty) return;
    final svc = ref.read(languageOptionsServiceProvider);
    await svc.ensureLoaded();
    // The state the student's lessons come from: the confirmed location, else
    // the registered state. A blank state allowed only Hindi + English, so
    // Punjabi / Gujarati / … narration was hidden even when uploaded.
    final eff = ref.read(effectiveStateProvider);
    final state = eff.isNotEmpty
        ? eff
        : (ref.read(currentUserProvider)?.assignedState ?? '');
    final allowed = svc.allowedFor(state);
    final avail = _audios.keys.where(allowed.contains).toList();
    final list = avail.isNotEmpty ? avail : _audios.keys.toList();
    final prefer = [consentLangForState(state), 'en', 'hi'];
    final active = prefer.firstWhere(list.contains, orElse: () => list.first);
    if (!mounted) return;
    setState(() {
      _availableLangs = list;
      _activeLang = active;
    });
  }

  String _langLabel(String code) {
    const m = {
      'hi': 'हिंदी',
      'en': 'English',
      'gu': 'ગુજરાતી',
      'mr': 'मराठी',
      'ta': 'தமிழ்',
      'te': 'తెలుగు',
      'kn': 'ಕನ್ನಡ',
      'ml': 'മലയാളം',
      'bn': 'বাংলা',
      'pa': 'ਪੰਜਾਬੀ',
      'or': 'ଓଡ଼ିଆ',
      'as': 'অসমীয়া',
      'ur': 'اردو',
      'sa': 'संस्कृत',
      'ne': 'नेपाली',
      'kok': 'कोंकणी',
      'mni': 'ꯃꯤꯇꯩ',
      'brx': 'बड़ो',
      'sat': 'ᱥᱟᱱᱛᱟᱲᱤ',
      'doi': 'डोगरी',
      'ks': 'کٲشُر',
      'mai': 'मैथिली',
      'sd': 'سنڌي',
    };
    return m[code] ?? code.toUpperCase();
  }

  void _onPickLanguage(String lang) {
    if (lang == _activeLang) return;
    setState(() => _activeLang = lang);
    _logLanguageChoice(lang, switched: true);
    _startNarration();
  }

  void _logLanguageChoice(String lang, {required bool switched}) {
    // Analytics run only after consent (TelemetryService exists only then).
    if (TelemetryService.current == null) return;
    try {
      final uid = ref.read(currentUserProvider)?.id ?? 'anon';
      TelemetryBatchBuffer.instance.buffer(
        collection: 'ar_language',
        studentId: uid,
        data: {
          'topicId': widget.topicId,
          'language': lang,
          'switched': switched,
          'surface': 'viewer',
          'ts': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {}
  }

  Widget _languageChip() {
    final accent = ThemeHelper.getActiveHighlight(ref.watch(themeProvider));
    return PopupMenuButton<String>(
      onSelected: _onPickLanguage,
      color: MitraColors.bgCard,
      itemBuilder: (_) => _availableLangs
          .map((l) => PopupMenuItem<String>(
                value: l,
                child: Row(children: [
                  Icon(l == _activeLang ? Icons.check : Icons.circle_outlined,
                      size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text(_langLabel(l),
                      style: const TextStyle(color: Colors.white)),
                ]),
              ))
          .toList(),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.language, color: accent, size: 16),
          const SizedBox(width: 6),
          Text(_langLabel(_activeLang ?? ''),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w700)),
          const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 16),
        ]),
      ),
    );
  }

  DateTime? _arStart; // AR view duration telemetry
  TelemetryService? _telemetry; // captured in initState; safe to use in dispose

  // Finger-gesture guide (turn / zoom / move). Shows by itself on the first
  // few opens, hides after a few seconds, and the "?" button re-shows it.
  static const String _gestureHintKey = 'ar_viewer_gesture_hint_count_v1';
  static const int _gestureHintAutoTimes = 3;
  bool _showGestures = false;
  Timer? _gestureTimer;

  void _showGestureGuide({bool auto = false}) {
    if (auto) {
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        final n = prefs.getInt(_gestureHintKey) ?? 0;
        // A settings pack can change how many times it opens by itself.
        if (n >=
            PackStore.instance.setting<int>(
                'ar_gesture_hint_auto_times', _gestureHintAutoTimes)) {
          return;
        }
        prefs.setInt(_gestureHintKey, n + 1);
      } catch (_) {
        return; // prefs unavailable → skip the hint, never block the model
      }
    }
    _gestureTimer?.cancel();
    if (mounted) setState(() => _showGestures = true);
    final secs = PackStore.instance
        .setting<int>('ar_gesture_hint_seconds', 8)
        .clamp(2, 60)
        .toInt();
    _gestureTimer = Timer(Duration(seconds: secs), _hideGestureGuide);
  }

  void _hideGestureGuide() {
    _gestureTimer?.cancel();
    if (mounted && _showGestures) setState(() => _showGestures = false);
  }

  @override
  void initState() {
    super.initState();
    _pauser = NarrationPauser(_audio); // watch app background/foreground
    try {
      _xpEngine = ref.read(achievementEngineProvider);
    } catch (_) {/* XP store unavailable → no XP, the lesson still opens */}
    markEngaged(ref, widget.topicId);
    _arStart = DateTime.now();
    _telemetry = ref.read(telemetryServiceProvider);
    _telemetry?.logArStart(
      arId: widget.topicId,
      topicId: widget.topicId,
      moduleTitle: widget.topicId,
      preModuleScore: 0,
    );
    debugPrint('🟣 ArViewerScreen OPENED — topicId=${widget.topicId} '
        'nativeUrl=${widget.nativeModelUrl} modelUrl=${widget.modelUrl}');
    // Track narration progress → credit the AR module toward the ≥80% quiz gate,
    // exactly like ArRoomScreen. Without this, students who watch via the 3D
    // viewer (every non-ARCore phone) never unlock the quiz.
    // Position updates stop just short of the end (~98-99%), so a full
    // listen never reached 100%. Finishing the track counts as 100%.
    _audio.onPlayerComplete.listen((_) {
      if (!mounted) return;
      ref
          .read(moduleProgressStoreProvider)
          .recordArProgress(widget.topicId, 100);
      _giveArXp();
    });
    _audio.onDurationChanged.listen((d) => _audioDuration = d);
    _audio.onPositionChanged.listen((pos) {
      final dur = _audioDuration;
      if (dur == null || dur.inMilliseconds <= 0 || !mounted) return;
      final pct = ((pos.inMilliseconds / dur.inMilliseconds) * 100).round();
      ref
          .read(moduleProgressStoreProvider)
          .recordArProgress(widget.topicId, pct);
    });
    _findLocalModel();
    _audios = widget.audios ?? const {};
    _audiosAac = widget.audiosAac ?? const {};
    // Fetch every language's narration now (one small file each), so the
    // first play and a language switch don't wait on the network.
    NarrationSource.prefetch(_audios, _audiosAac, single: widget.audioUrl);
    // Start once the student's language is known. It used to start at once
    // with the lesson's default audio, before the language was picked.
    _resolveLanguages().whenComplete(() {
      if (mounted && !_closing) _startNarration();
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showGestureGuide(auto: true));
  }

  // Narration: prefer the chosen-language audio; fall back to single audioUrl.
  // The in-flight narration start (buffering can take seconds on a slow
  // network). dispose() waits for it before releasing the player.
  Future<void>? _narration;
  Future<void> _startNarration() => _narration = _startNarrationImpl();

  Future<void> _startNarrationImpl() async {
    final chosen = _activeLang != null ? _audios[_activeLang] : null;
    final url = (chosen ?? widget.audioUrl)?.trim();
    if (url == null || url.isEmpty || _closing) return;
    if (_activeLang != null) _logLanguageChoice(_activeLang!, switched: false);
    final fallback =
        _activeLang != null ? _audiosAac[_activeLang]?.trim() : null;
    // Saved copy (instant) → else streamed; AAC first on phones without Opus.
    await NarrationSource.play(_audio,
        url: url, fallback: fallback, closing: () => _closing);
    // The student closed the viewer while the audio was still loading.
    if (_closing) {
      try {
        await _audio.stop();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    // Stop the narration FIRST — covers the close button and the phone's back
    // button / gesture. `ref` can't be used in dispose (Riverpod throws "Cannot
    // use ref after the widget was disposed"); that error used to abort this
    // method before the stop, so the audio kept playing after leaving.
    _closing = true;
    final player = _audio;
    player.stop().catchError((_) {});
    _gestureTimer?.cancel();
    _pauser.dispose();
    if (_arStart != null &&
        DateTime.now().difference(_arStart!).inSeconds >= 60) {
      _giveArXp();
    }
    final secs =
        _arStart == null ? 0 : DateTime.now().difference(_arStart!).inSeconds;
    _telemetry?.logArEnd(
      arId: widget.topicId,
      topicId: widget.topicId,
      moduleTitle: widget.topicId,
      durationSeconds: secs,
      completed: secs >= 10, // viewed for a meaningful duration
      isReplay: false,
      preModuleScore: 0,
      postModuleScore: 0,
      renderMode: 'interactive3d',
    );
    // Release only after any buffering play() settles, so a late-prepared
    // track can't start on a half-released player.
    (_narration ?? Future<void>.value())
        .catchError((_) {})
        .whenComplete(() => player.stop().catchError((_) {}))
        .whenComplete(() => player.dispose());
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
    // Only web links (or the bundled demo) may be opened here: a file:// or
    // content:// link — e.g. from a crafted mitra:// link — would make the
    // viewer's local server hand app files to other apps.
    String? web(String? s) {
      final v = s?.trim();
      return (v != null &&
              (v.startsWith('https://') || v.startsWith('http://')))
          ? v
          : null;
    }

    final nativeSrc = web(widget.nativeModelUrl);
    final dracoSrc = web(widget.modelUrl);
    final src = _localModel ??
        ((nativeSrc != null && nativeSrc.isNotEmpty)
            ? nativeSrc
            : (dracoSrc != null && dracoSrc.isNotEmpty
                ? dracoSrc
                : ArViewerScreen._bundledDemoGlb));

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
                child: !_modelChecked
                    ? const SizedBox.shrink()
                    : ModelViewer(
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
                            _stopNarration();
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/student/learn');
                            }
                          },
                        ),
                        const Spacer(),
                        // "?" shows the finger-gesture guide again.
                        _RoundIconButton(
                          icon: Icons.help_outline,
                          onTap: () => _showGestures
                              ? _hideGestureGuide()
                              : _showGestureGuide(),
                        ),
                        const SizedBox(width: 10),
                        if (_availableLangs.length >= 2) ...[
                          _languageChip(),
                          const SizedBox(width: 10),
                        ],
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
                              Text(
                                context.tr(ref, 'ar_ar_lesson', 'AR Lesson'),
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

              // ── Finger-gesture guide (bottom card, doesn't block the model) ─
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _showGestures
                          ? _gestureGuide(context, accent)
                          : const SizedBox.shrink(),
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

  Widget _gestureGuide(BuildContext context, Color accent) {
    Widget tip(IconData icon, String title, String body) => Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(height: 6),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Baloo2',
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      color: Colors.white70,
                      fontSize: 11,
                      height: 1.25)),
            ],
          ),
        );

    return Container(
      key: const ValueKey('gesture-guide'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tip(
                  Icons.touch_app,
                  context.tr(ref, 'ar_rotate', 'Rotate'),
                  context.tr(ref, 'ar_gesture_turn_body',
                      'Drag with one finger to turn it around.')),
              tip(
                  Icons.pinch,
                  context.tr(ref, 'ar_gesture_zoom_title', 'Zoom'),
                  context.tr(ref, 'ar_gesture_zoom_body',
                      'Pinch with two fingers to make it bigger or smaller.')),
              tip(
                  Icons.open_with,
                  context.tr(ref, 'ar_move', 'Move'),
                  context.tr(ref, 'ar_gesture_move_body',
                      'Drag with two fingers to move it on the screen.')),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _hideGestureGuide,
              child: Text(context.tr(ref, 'ar_got_it', 'Got it'),
                  style: TextStyle(
                      fontFamily: 'Baloo2',
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ),
          ),
        ],
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
