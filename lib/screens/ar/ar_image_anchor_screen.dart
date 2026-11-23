// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: Scan page — native ARCore image tracking (ARCore phones only).
//
// The dashboard stores the textbook page image (target_image_url). Here ARCore
// learns that one image (Augmented Images), finds it through the camera, and
// anchors the lesson's 3D model at the centre of the page. The model stays
// where the page was even if the page later leaves the view.
//
// Narration follows the same rules as the web scanner (ArMarkerScreen): it
// starts the first time the page is found, pauses while the page is out of
// view, resumes when it's back, and its progress unlocks the quiz.
//
// Phones without ARCore never reach this screen (ArEntryScreen sends them to
// the MindAR web scanner). If ARCore can't use this page image, the student
// can switch to the web scanner via [onFallback].
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'narration_pauser.dart';
import 'narration_source.dart'; // narration saved on the phone → starts at once
import '../../constants/colors.dart';
import '../../services/achievement_engine.dart';
import '../../fun/fun_cards.dart';
import '../../fun/new_card_banner.dart';
import '../../theme/theme_provider.dart'; // sharedPreferencesProvider
import '../../providers/tr_ext.dart';
import '../../providers/translation_provider.dart';
import '../../services/geo_state_service.dart'; // effectiveStateProvider
import '../../stores/auth_store.dart'; // currentUserProvider
import '../auth/state_language_map.dart'; // consentLangForState
import '../../services/ar_model_cache.dart';
import '../../services/topic_cache.dart'; // next / recent topics kept on the phone
import '../../services/telemetry_service.dart';
import '../../stores/module_progress_store.dart';

class ArImageAnchorScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String imageUrl; // the page image (JPG/PNG) ARCore should find
  final String modelUrl; // non-Draco GLB (native Filament can't decode Draco)
  final String? audioUrl;
  final Map<String, String>? audios; // {lang: url}
  final Map<String, String>? audiosAac; // {lang: url} AAC fallback
  /// Switch to the MindAR web scanner (null when the lesson has no .mind).
  final VoidCallback? onFallback;

  const ArImageAnchorScreen({
    super.key,
    required this.topicId,
    required this.imageUrl,
    required this.modelUrl,
    this.audioUrl,
    this.audios,
    this.audiosAac,
    this.onFallback,
  });

  @override
  ConsumerState<ArImageAnchorScreen> createState() =>
      _ArImageAnchorScreenState();
}

class _ArImageAnchorScreenState extends ConsumerState<ArImageAnchorScreen> {
  // AR-view XP through the same achievement engine as AR room (one XP path,
  // one set of analytics). Given once: when the narration (or page video) is
  // finished, or when the student has stayed 60 seconds.
  // First time this lesson's page is found, its hero card unlocks.
  bool _newCard = false, _cardChecked = false;
  Future<void> _checkCard() async {
    if (_cardChecked) return;
    _cardChecked = true;
    final isNew = await unlockHeroCard(
        ref.read(sharedPreferencesProvider), widget.topicId);
    if (!mounted || !isNew) return;
    ref.read(cardTickProvider.notifier).state++;
    setState(() => _newCard = true);
  }

  AchievementEngine? _xpEngine;
  bool _arXpGiven = false;
  void _giveArXp() {
    if (_arXpGiven) return;
    _arXpGiven = true;
    _xpEngine?.recordArView(widget.topicId);
  }

  ARSessionManager? _session;
  ARObjectManager? _objects;

  String? _hint;
  String? _error;
  bool _placed = false;
  bool _placing = false;

  DateTime? _arStart;
  bool _arStarted = false;

  // ── Narration (same behaviour as ArMarkerScreen) ────────────────────────
  final AudioPlayer _audio = AudioPlayer();
  // Pauses narration while the app is in the background.
  late final NarrationPauser _pauser;
  Duration? _audioDuration;
  bool _narrationStarted = false;
  bool _closing = false;
  Future<void>? _narration;

  (String?, String?) _pickNarration() {
    final audios = widget.audios ?? const {};
    final aac = widget.audiosAac ?? const {};
    // The state's own language first (Punjab → Punjabi), as in the 3D viewer
    // and AR room; then the app's language, English, Hindi. It used to start
    // with the app's language, so an English app never played Punjabi here.
    final eff = ref.read(effectiveStateProvider);
    final state = eff.isNotEmpty
        ? eff
        : (ref.read(currentUserProvider)?.assignedState ?? '');
    final lang = ref.read(translationProvider).langCode.toLowerCase();
    for (final l in [consentLangForState(state), lang, 'en', 'hi']) {
      final u = audios[l]?.trim();
      if (u != null && u.isNotEmpty) return (u, aac[l]?.trim());
    }
    final single = widget.audioUrl?.trim();
    return ((single?.isEmpty ?? true) ? null : single, null);
  }

  Future<void> _startNarration() async {
    final (url, fallback) = _pickNarration();
    if (url == null || _closing) return;
    // Saved copy (instant) → else streamed; AAC first on phones without Opus.
    await NarrationSource.play(_audio,
        url: url, fallback: fallback, closing: () => _closing);
    if (_closing) {
      try {
        await _audio.stop();
      } catch (_) {}
    }
  }

  void _onTracking(String state) {
    if (_closing || !mounted) return;
    if (state == 'found') {
      if (_placed) setState(() => _hint = null);
      if (!_narrationStarted) {
        _narrationStarted = true;
        _narration = _startNarration();
      } else {
        _audio.resume().catchError((_) {});
      }
    } else {
      _audio.pause().catchError((_) {});
      if (_placed) {
        setState(() =>
            _hint = ref.trNow('ar_keep_page_in_view', 'Keep the page in view'));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pauser = NarrationPauser(_audio); // watch app background/foreground
    // Fetch the narration now, so it starts at once when the page is found.
    final (nUrl, nAac) = _pickNarration();
    if (nUrl != null) {
      NarrationSource.prefetch(
          {'n': nUrl}, {if (nAac != null && nAac.isNotEmpty) 'n': nAac});
    }
    try {
      _xpEngine = ref.read(achievementEngineProvider);
    } catch (_) {/* XP store unavailable → no XP, the lesson still opens */}
    markEngaged(ref, widget.topicId);
    _hint = ref.trNow(
        'ar_point_camera_at_page', 'Point the camera at the textbook page');
    _arStart = DateTime.now();
    _arStarted = true;
    TelemetryService.current?.logArStart(
      arId: widget.topicId,
      topicId: widget.topicId,
      moduleTitle: widget.topicId,
      preModuleScore: 0,
    );
    _audio.onDurationChanged.listen((d) => _audioDuration = d);
    _audio.onPositionChanged.listen((pos) {
      final dur = _audioDuration;
      if (dur == null || dur.inMilliseconds <= 0 || !mounted) return;
      final pct = ((pos.inMilliseconds / dur.inMilliseconds) * 100).round();
      ref
          .read(moduleProgressStoreProvider)
          .recordArProgress(widget.topicId, pct);
    });
    _audio.onPlayerComplete.listen((_) {
      if (!mounted) return;
      ref
          .read(moduleProgressStoreProvider)
          .recordArProgress(widget.topicId, 100);
      _giveArXp();
    });
  }

  @override
  void dispose() {
    _pauser.dispose();
    if (_arStart != null &&
        DateTime.now().difference(_arStart!).inSeconds >= 60) {
      _giveArXp();
    }
    if (_arStarted) {
      final secs =
          _arStart == null ? 0 : DateTime.now().difference(_arStart!).inSeconds;
      TelemetryService.current?.logArEnd(
        arId: widget.topicId,
        topicId: widget.topicId,
        moduleTitle: widget.topicId,
        durationSeconds: secs,
        completed: _placed && secs >= 10,
        isReplay: false,
        preModuleScore: 0,
        postModuleScore: 0,
        renderMode: 'marker_native',
      );
    }
    _closing = true;
    final player = _audio;
    player.stop().catchError((_) {});
    (_narration ?? Future<void>.value())
        .catchError((_) {})
        .whenComplete(() => player.stop().catchError((_) {}))
        .whenComplete(() => player.dispose());
    _session?.dispose();
    super.dispose();
  }

  void _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _session = sessionManager;
    _objects = objectManager;
    sessionManager.onInitialize(
      showFeaturePoints: false,
      showAnimatedGuide: false, // the "move your phone" hand is for floors
      showPlanes: false,
      showWorldOrigin: false,
      handleTaps: false,
    );
    objectManager.onInitialize();
    // The plugin calls these for every plane/tap; leaving them unset throws
    // LateInitializationError.
    sessionManager.onPlaneDetected = (_) {};
    sessionManager.onPlaneOrPointTap = (_) {};
    sessionManager.onImageTargetAnchored = _onAnchored;
    sessionManager.onImageTracking = _onTracking;
    _registerTarget();
  }

  // Download the page image and hand it to ARCore. NO_SESSION just means the
  // camera session isn't up yet → retry a few times.
  Future<void> _registerTarget() async {
    final Uint8List bytes;
    try {
      // The page image from the phone when the topic is kept.
      final kept = await TopicCache.instance.pathFor(widget.imageUrl);
      bytes = kept != null
          ? await File(kept).readAsBytes()
          : await _download(widget.imageUrl);
    } catch (_) {
      _fail(ref.trNow('ar_could_not_load_page_image',
          'Couldn\'t load the page image. Check your connection.'));
      return;
    }
    for (var attempt = 0; attempt < 12; attempt++) {
      if (_closing || !mounted) return;
      try {
        await _session!.setImageTarget(bytes);
        return;
      } on PlatformException catch (e) {
        if (e.code == 'NO_SESSION') {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        _fail(e.code == 'IMAGE_QUALITY'
            ? ref.trNow('ar_page_image_not_trackable',
                'ARCore can\'t recognise this page image (too few details).')
            : ref.trpNow(
                'ar_could_not_start_ar_description',
                'Could not start AR: {description}',
                {'description': e.message ?? e.code}));
        return;
      } on MissingPluginException {
        _fail(ref.trpNow('ar_could_not_start_ar_description',
            'Could not start AR: {description}', {'description': 'plugin'}));
        return;
      }
    }
    _fail(ref.trpNow('ar_could_not_start_ar_description',
        'Could not start AR: {description}', {'description': 'camera'}));
  }

  Future<Uint8List> _download(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await consolidateHttpClientResponseBytes(res);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _onAnchored(
      String anchorName, double extentX, double extentZ) async {
    if (_placed || _placing || _closing || !mounted) return;
    _placing = true;
    setState(() => _hint =
        ref.trNow('ar_page_found_placing', 'Page found, placing the model…'));

    // Same model source as the AR room: the on-device cache (served on a
    // loopback URL) when it can, else the remote URL.
    String uri = widget.modelUrl;
    if (uri.startsWith('http')) {
      final local = await ArModelCache.instance.localUrlFor(uri);
      if (local != null && local.isNotEmpty) uri = local;
    }
    if (_closing || !mounted) return;

    // The plugin scales the model to fit a cube of `scale` metres. Size it to
    // the page ARCore measured (a textbook page ≈ 0.2 m), within sane bounds.
    final size = (extentX > 0 ? extentX : 0.2).clamp(0.1, 0.4).toDouble();
    final node = ARNode(
      type: NodeType.webGLB,
      uri: uri,
      scale: vm.Vector3(size, size, size),
    );
    final ok = await _objects!.addNode(
      node,
      planeAnchor: ARPlaneAnchor(
          name: anchorName, transformation: vm.Matrix4.identity()),
    );
    if (_closing || !mounted) return;
    _placing = false;
    if (ok == true) {
      setState(() {
        _placed = true;
        _hint = null;
      });
      _checkCard();
    } else {
      _fail(ref.trNow(
          'ar_model_could_not_load', 'The 3D model could not be loaded.'));
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _hint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: ARView(
                onARViewCreated: _onARViewCreated,
                planeDetectionConfig: PlaneDetectionConfig.none,
              ),
            ),
            if (_error != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 15),
                      ),
                      if (widget.onFallback != null) ...[
                        const SizedBox(height: 18),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: MitraColors.saffron,
                              foregroundColor: Colors.black87),
                          onPressed: widget.onFallback,
                          child: Text(context.tr(ref, 'ar_use_web_scanner',
                              'Use the web scanner')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_error == null && _hint != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 32,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _hint!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            // "New hero card!" the first time this page is found.
            if (_newCard)
              Positioned(
                top: 60,
                left: 16,
                right: 16,
                child: Center(
                  child: NewCardBanner(
                      onDone: () => setState(() => _newCard = false)),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    _closing = true;
                    _audio.stop().catchError((_) {});
                    context.pop();
                  },
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 56,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MitraColors.saffron.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  context.tr(
                      ref, 'ar_scan_textbook_page_2', '📄 Scan textbook page'),
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
