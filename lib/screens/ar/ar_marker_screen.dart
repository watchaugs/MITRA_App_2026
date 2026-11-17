import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../constants/colors.dart';
import '../../services/achievement_engine.dart';
import '../../fun/fun_cards.dart';
import '../../fun/new_card_banner.dart';
import '../../theme/theme_provider.dart'; // sharedPreferencesProvider
import '../../services/ar_video_cache.dart';
import '../../services/telemetry_service.dart';
import '../../stores/ar_pack_store.dart';
import '../../stores/module_progress_store.dart';
import '../../providers/translation_provider.dart';

import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArMarkerScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? targetsUrl; // the compiled .mind target (?mind=)
  final String? modelUrl; // the model GLB (?glb=)
  // Narration, same sources as the 3D view / AR room. It plays while the model
  // is locked onto the page, and its progress unlocks the quiz.
  final String? audioUrl;
  final Map<String, String>? audios; // {lang: url}
  final Map<String, String>? audiosAac; // {lang: url} AAC fallback
  // Page video: a flat "screen" fixed over the diagram on the page. It moves
  // and tilts with the book, pauses when the page leaves the camera.
  final String? videoUrl;
  final String? videoRegion; // JSON {x,y,w,h}: 0–1 of the page from top-left
  final String? videoSound; // 'video' (its sound counts) | 'narration' (muted)
  final String? videoView; // first view when there is also a model
  final String? chromaColor; // green-screen key colour, if enabled

  const ArMarkerScreen({
    super.key,
    required this.topicId,
    required this.targetsUrl,
    required this.modelUrl,
    this.audioUrl,
    this.audios,
    this.audiosAac,
    this.videoUrl,
    this.videoRegion,
    this.videoSound,
    this.videoView,
    this.chromaColor,
  });

  @override
  ConsumerState<ArMarkerScreen> createState() => _ArMarkerScreenState();
}

class _ArMarkerScreenState extends ConsumerState<ArMarkerScreen> {
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

  WebViewController? _controller;
  String? _error;
  DateTime? _arStart; // for marker-AR duration telemetry
  bool _arStarted = false; // did we log an ar_start (so dispose logs an end)?

  // ── Narration (plays only while the model is on the page) ──────────────
  final AudioPlayer _audio = AudioPlayer();
  Duration? _audioDuration;
  bool _narrationStarted =
      false; // first targetFound starts it; later ones resume
  bool _closing = false;
  Future<void>? _narration; // in-flight start, awaited before dispose

  // ── Page video ─────────────────────────────────────────────────────────
  bool get _hasModel => (widget.modelUrl ?? '').isNotEmpty;
  bool get _hasVideo => (widget.videoUrl ?? '').isNotEmpty;
  late String _view; // '3d' | 'video'
  bool _tracking = false; // page currently in view
  // The video's own sound plays (and its watching unlocks the quiz) unless the
  // dashboard chose "narration" AND a narration file exists.
  bool get _videoSoundMode =>
      widget.videoSound != 'narration' || _pickNarration().$1 == null;
  // Narration plays while the page is in view, except over a video that has
  // its own sound.
  bool get _narrationWanted =>
      _tracking && !(_view == 'video' && _videoSoundMode);
  // Video comes off the phone when saved/cached; first time it downloads once.
  bool _videoReady = false;
  double? _videoProgress; // 0–1 while downloading
  String? _videoSrcForPage; // JS string literal, once the download is done
  // Telemetry for the page-video branch (same ar_end event as AR 3D).
  int _videoBestPct = 0; // furthest point watched
  int _viewSwitches = 0; // 3D ⇄ Video taps
  int _videoMs = 0; // time spent in Video view
  DateTime? _videoViewSince;

  void _markViewTime() {
    final now = DateTime.now();
    if (_videoViewSince != null) {
      _videoMs += now.difference(_videoViewSince!).inMilliseconds;
    }
    _videoViewSince = _view == 'video' ? now : null;
  }

  // Pick the narration in the app's language, else English, else Hindi, else
  // the single audio_url. Returns (url, aacFallback).
  (String?, String?) _pickNarration() {
    final audios = widget.audios ?? const {};
    final aac = widget.audiosAac ?? const {};
    final lang = ref.read(translationProvider).langCode.toLowerCase();
    for (final l in [lang, 'en', 'hi']) {
      final u = audios[l]?.trim();
      if (u != null && u.isNotEmpty) return (u, aac[l]?.trim());
    }
    final single = widget.audioUrl?.trim();
    return ((single?.isEmpty ?? true) ? null : single, null);
  }

  Future<void> _startNarration() async {
    final (url, fallback) = _pickNarration();
    if (url == null || _closing) return;
    try {
      await _audio.play(UrlSource(url));
    } catch (_) {
      if (fallback != null && fallback.isNotEmpty && !_closing) {
        try {
          await _audio.play(UrlSource(fallback));
        } catch (_) {/* best-effort; never block the AR */}
      }
    }
    if (_closing) {
      try {
        await _audio.stop();
      } catch (_) {}
    }
  }

  // Play or pause the narration to match the page + current view.
  void _syncNarration() {
    if (_closing) return;
    if (_narrationWanted) {
      if (!_narrationStarted) {
        _narrationStarted = true;
        _narration = _startNarration();
      } else {
        _audio.resume().catchError((_) {});
      }
    } else {
      _audio.pause().catchError((_) {});
    }
  }

  // Messages from marker_player.html: 'found' / 'lost', and for the page
  // video 'vprog:<0-100>' (highest point watched) and 'verr'.
  void _onMarkerEvent(String msg) {
    if (_closing || !mounted) return;
    if (msg == 'found') {
      _tracking = true;
      _syncNarration();
      _checkCard();
    } else if (msg == 'lost') {
      _tracking = false;
      _syncNarration();
    } else if (msg.startsWith('vprog:')) {
      // Video progress counts toward the quiz only when its sound is the
      // lesson's voice (otherwise the narration's progress counts).
      final pct = int.tryParse(msg.substring(6));
      if (pct != null && pct > _videoBestPct) _videoBestPct = pct;
      if (pct != null && _videoSoundMode) {
        ref
            .read(moduleProgressStoreProvider)
            .recordArProgress(widget.topicId, pct);
        if (pct >= 100) _giveArXp();
      }
    } else if (msg == 'vwant') {
      _pushVideoSrc();
    } else if (msg == 'verr') {
      TelemetryService.current
          ?.logArInitFailure(arId: widget.topicId, reason: 'page_video_error');
      if (_hasModel && _view == 'video') _setView('3d');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(ref.trNow('ar_video_could_not_play',
              'The video could not be played. Check your internet.'))));
    }
  }

  void _setView(String v) {
    if (!_hasVideo || (!_hasModel && v == '3d')) return;
    if (v != _view) _viewSwitches++;
    setState(() => _view = v);
    _markViewTime();
    final muted = _videoSoundMode ? 'false' : 'true';
    _controller
        ?.runJavaScript("window.setView && setView('$v', $muted);")
        .catchError((_) {});
    _syncNarration();
  }

  @override
  void initState() {
    super.initState();
    _xpEngine = ref.read(achievementEngineProvider);
    markEngaged(ref, widget.topicId);
    _view = !_hasModel
        ? 'video'
        : (_hasVideo && widget.videoView == 'video' ? 'video' : '3d');
    if ((widget.targetsUrl ?? '').isEmpty || (!_hasModel && !_hasVideo)) {
      _error = ref.trNow('ar_this_lesson_has_no_textbook_page',
          'This lesson has no textbook-page target to scan.');
      return;
    }
    // Marker-AR session telemetry → feeds the report's MARKER_* tokens.
    _arStart = DateTime.now();
    _arStarted = true;
    TelemetryService.current?.logArStart(
      arId: widget.topicId,
      topicId: widget.topicId,
      moduleTitle: widget.topicId,
      preModuleScore: 0,
    );
    // Same progress rule as the 3D view / AR room: highest % of narration
    // heard; finishing the track = 100%.
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
    _markViewTime();
    _prepareAndLoad();
  }

  // Model/video sources for the scanner WebView. It can't open phone files by
  // path, so saved/cached files go through the loopback server (as in AR room).
  Future<void> _prepareAndLoad() async {
    String? model = widget.modelUrl;
    if (model != null && model.startsWith('/')) {
      model = await ArVideoCache.instance.urlForFile(model);
    }
    String? video;
    if (_hasVideo) {
      final remote = widget.videoUrl!;
      final saved =
          ArPackStore.instance.localVideo(widget.topicId, url: remote);
      video = saved != null
          ? await ArVideoCache.instance.urlForFile(saved)
          : await ArVideoCache.instance.cachedUrl(remote);
      if (video == null) _downloadVideo(remote); // scanner starts meanwhile
    }
    if (!mounted || _closing) return;
    setState(() => _videoReady = video != null);
    _initWebView(model, video);
  }

  // First play: download once, then hand the WebView the on-phone copy. If
  // the download fails, stream it instead (as before caching existed).
  Future<void> _downloadVideo(String remote) async {
    final job = ArVideoCache.instance.fetch(remote);
    final p = ArVideoCache.instance.progressFor(remote);
    void onP() {
      if (mounted) setState(() => _videoProgress = p?.value);
    }

    p?.addListener(onP);
    final local = await job;
    p?.removeListener(onP);
    if (!mounted || _closing) return;
    setState(() {
      _videoReady = true;
      _videoProgress = null;
    });
    _videoSrcForPage = jsonEncode(local ?? remote);
    _pushVideoSrc();
  }

  // Hands the finished video to the page. Also called when the page asks
  // ('vwant'), in case the download finished before the page was ready.
  void _pushVideoSrc() {
    final src = _videoSrcForPage;
    if (src == null) return;
    _controller
        ?.runJavaScript('window.setVideoSrc && setVideoSrc($src);')
        .catchError((_) {});
  }

  @override
  void dispose() {
    if (_arStart != null &&
        DateTime.now().difference(_arStart!).inSeconds >= 60) {
      _giveArXp();
    }
    // Log the marker-AR end with render_mode 'marker' so the dashboard can
    // break AR engagement down by render mode. completed = the WebView loaded
    // without an init error and the student stayed a meaningful duration.
    if (_arStarted) {
      final secs =
          _arStart == null ? 0 : DateTime.now().difference(_arStart!).inSeconds;
      TelemetryService.current?.logArEnd(
        arId: widget.topicId,
        topicId: widget.topicId,
        moduleTitle: widget.topicId,
        durationSeconds: secs,
        completed: _error == null && secs >= 10,
        isReplay: false,
        preModuleScore: 0,
        postModuleScore: 0,
        renderMode: 'marker',
        // Page-video branch: furthest % watched, seconds in Video view,
        // 3D ⇄ Video switches (null when the lesson has no video).
        videoWatchedPct: _hasVideo ? _videoBestPct : null,
        videoSeconds: _hasVideo ? _videoSecondsNow() : null,
        viewSwitches: _hasVideo ? _viewSwitches : null,
      );
    }
    // Stop the narration (also on the hardware back button), then release the
    // player once any buffering start has settled.
    _closing = true;
    final player = _audio;
    player.stop().catchError((_) {});
    (_narration ?? Future<void>.value())
        .catchError((_) {})
        .whenComplete(() => player.stop().catchError((_) {}))
        .whenComplete(() => player.dispose());
    super.dispose();
  }

  int _videoSecondsNow() {
    var ms = _videoMs;
    if (_videoViewSince != null) {
      ms += DateTime.now().difference(_videoViewSince!).inMilliseconds;
    }
    return (ms / 1000).round();
  }

  void _initWebView(String? model, String? video) {
    final params = Uri(queryParameters: {
      'mind': widget.targetsUrl!,
      if (model != null && model.isNotEmpty) 'model': model,
      if (_hasVideo) ...{
        // Not on the phone yet → the page waits; setVideoSrc() follows.
        if (video != null) 'video': video else 'vpending': '1',
        if ((widget.videoRegion ?? '').isNotEmpty)
          'vregion': widget.videoRegion!,
        'vmute': _videoSoundMode ? '0' : '1',
        'view': _view,
        if ((widget.chromaColor ?? '').isNotEmpty)
          'chroma': widget.chromaColor!,
      },
    }).query;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setOnConsoleMessage((_) {})
      ..addJavaScriptChannel('MitraAR',
          onMessageReceived: (m) => _onMarkerEvent(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (err) {
          // Only a failed page load is fatal; a model/video error is not.
          if (err.isForMainFrame == false) return;
          if (mounted) {
            setState(() => _error = ref.trpNow(
                'ar_could_not_start_ar_description',
                'Could not start AR: {description}',
                {'description': err.description.toString()}));
          }
        },
      ));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnPlatformPermissionRequest((request) => request.grant());
      // The page video starts when the page is found — no tap needed.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    controller.loadFlutterAsset('assets/ar/marker_player.html?$params');
    setState(() => _controller = controller);
  }

  Widget _viewChip(String v, IconData icon, String label) {
    final on = _view == v;
    return GestureDetector(
      onTap: () => _setView(v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? MitraColors.saffron : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: on ? Colors.black87 : Colors.white),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: on ? Colors.black87 : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ),
              )
            else if (_controller != null)
              WebViewWidget(controller: _controller!),
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
                  style: TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            // First play: the video is downloading to the phone.
            if (_error == null && _hasVideo && !_videoReady)
              Positioned(
                top: (_hasModel ? 56 : 8),
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '🎬 ${context.tr(ref, 'ar_video_preparing', 'Preparing video')}'
                    '${_videoProgress != null ? ' ${(_videoProgress! * 100).round()}%' : '…'}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
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
            // 3D ⇄ Video switch (only when the lesson has both).
            if (_error == null && _hasVideo && _hasModel)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _viewChip('3d', Icons.view_in_ar,
                          context.tr(ref, 'ar_view_3d', '3D')),
                      _viewChip('video', Icons.ondemand_video,
                          context.tr(ref, 'ar_view_video', 'Video')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
