import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../constants/colors.dart';
import '../../services/telemetry_service.dart';
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

  const ArMarkerScreen({
    super.key,
    required this.topicId,
    required this.targetsUrl,
    required this.modelUrl,
    this.audioUrl,
    this.audios,
    this.audiosAac,
  });

  @override
  ConsumerState<ArMarkerScreen> createState() => _ArMarkerScreenState();
}

class _ArMarkerScreenState extends ConsumerState<ArMarkerScreen> {
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

  // Messages from marker_player.html: 'found' / 'lost'.
  void _onMarkerEvent(String msg) {
    if (_closing || !mounted) return;
    if (msg == 'found') {
      if (!_narrationStarted) {
        _narrationStarted = true;
        _narration = _startNarration();
      } else {
        _audio.resume().catchError((_) {});
      }
    } else if (msg == 'lost') {
      _audio.pause().catchError((_) {});
    }
  }

  @override
  void initState() {
    super.initState();
    if ((widget.targetsUrl ?? '').isEmpty || (widget.modelUrl ?? '').isEmpty) {
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
    });
    _initWebView();
  }

  @override
  void dispose() {
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

  void _initWebView() {
    final params = Uri(queryParameters: {
      'mind': widget.targetsUrl!,
      'model': widget.modelUrl!,
    }).query;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setOnConsoleMessage((_) {})
      ..addJavaScriptChannel('MitraAR',
          onMessageReceived: (m) => _onMarkerEvent(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (err) {
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
    }

    controller.loadFlutterAsset('assets/ar/marker_player.html?$params');
    _controller = controller;
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
          ],
        ),
      ),
    );
  }
}
