// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: In-app 3D/AR viewer — hosts the offline-bundled three.js + MindAR
// engine (assets/ar/index.html) in a WebView. One engine, three modes:
//   marker  — textbook-page image tracking (needs a .mind target)
//   overlay — model over the live camera feed (no tracking)
//   viewer  — model on a backdrop (no camera; the weakest-phone floor)
// Model + narration play in one process, so audio is always perfectly in sync.
//
// It steps DOWN gracefully on failure (marker → overlay → viewer) and never
// dead-ends. `allowExplore` adds a silent Google Scene Viewer "Explore in your
// room" bonus for capable phones (spatial AR, no narration — tapped after the
// lesson).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../constants/colors.dart';
import '../../providers/telemetry_provider.dart';
import '../../services/achievement_engine.dart';

enum ArMode { marker, overlay, viewer }

String _modeName(ArMode m) =>
    m == ArMode.marker ? 'marker' : (m == ArMode.overlay ? 'overlay' : 'viewer');

class WebArViewerScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String modelUrl; // GLB (remote R2 URL)
  final String? targetsUrl; // compiled MindAR .mind (marker mode)
  final String? audioUrl; // narration for the current language
  final ArMode mode;
  final bool allowExplore;

  const WebArViewerScreen({
    super.key,
    required this.topicId,
    required this.modelUrl,
    this.targetsUrl,
    this.audioUrl,
    this.mode = ArMode.viewer,
    this.allowExplore = false,
  });

  @override
  ConsumerState<WebArViewerScreen> createState() => _WebArViewerScreenState();
}

class _WebArViewerScreenState extends ConsumerState<WebArViewerScreen> {
  WebViewController? _controller;
  late ArMode _mode;
  String? _error;
  final DateTime _openedAt = DateTime.now();
  dynamic _telemetry;
  dynamic _achievement;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _telemetry = ref.read(telemetryServiceProvider);
    _achievement = ref.read(achievementEngineProvider);
  }

  @override
  void dispose() {
    final secs = DateTime.now().difference(_openedAt).inSeconds;
    if (secs >= 60) _achievement?.recordArView(widget.topicId);
    _telemetry?.logArEnd(
      arId: widget.topicId,
      topicId: widget.topicId,
      moduleTitle: widget.topicId,
      durationSeconds: secs,
      completed: true,
      isReplay: false,
      preModuleScore: 0.0,
      postModuleScore: 0.0,
    );
    _controller?.runJavaScript('window.mitraStop && window.mitraStop();');
    super.dispose();
  }

  bool get _needsCamera => _mode == ArMode.marker || _mode == ArMode.overlay;

  Future<void> _init() async {
    // Marker needs a target; without one, start at overlay.
    if (_mode == ArMode.marker &&
        (widget.targetsUrl == null || widget.targetsUrl!.isEmpty)) {
      _mode = ArMode.overlay;
    }
    // Camera-using modes need the runtime permission; if denied, fall to viewer.
    if (_needsCamera) {
      final st = await Permission.camera.request();
      if (!st.isGranted) _mode = ArMode.viewer;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('MitraAR', onMessageReceived: _onEngineMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectConfig(),
          onWebResourceError: (e) => _stepDown(e.description),
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      await android.setMediaPlaybackRequiresUserGesture(false);
      android.setOnPlatformPermissionRequest((req) => req.grant());
    }

    await controller.loadFlutterAsset('assets/ar/index.html');
    if (mounted) setState(() => _controller = controller);
  }

  void _injectConfig() {
    final cfg = jsonEncode({
      'mode': _modeName(_mode),
      'modelUrl': widget.modelUrl,
      if (widget.targetsUrl != null) 'targetsUrl': widget.targetsUrl,
      if (widget.audioUrl != null) 'audioUrl': widget.audioUrl,
      'scale': 0.5,
    });
    _controller?.runJavaScript('window.MITRA_CONFIG = $cfg;');
  }

  void _onEngineMessage(JavaScriptMessage message) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = msg['type'];
    if (type == 'fatal') {
      // Engine/camera/tracking failure — a lower mode may still work.
      _stepDown((msg['message'] ?? 'AR error').toString());
    } else if (type == 'model_error') {
      // The model itself failed to load — changing mode won't help.
      if (mounted) setState(() => _error = (msg['message'] ?? 'Model error').toString());
    }
    // 'ar_started' | 'target_found' | 'target_lost' | 'model_loaded' |
    // 'audio_blocked' are available here for analytics later.
  }

  // Graceful degradation: marker → overlay → viewer. Viewer failing is terminal.
  void _stepDown(String msg) {
    if (!mounted) return;
    if (_mode == ArMode.marker) {
      setState(() => _mode = ArMode.overlay);
      _reloadEngine();
    } else if (_mode == ArMode.overlay) {
      setState(() => _mode = ArMode.viewer);
      _reloadEngine();
    } else {
      setState(() => _error = msg);
    }
  }

  void _reloadEngine() {
    // A fresh asset load resets the engine; config is re-injected on finish.
    _controller?.loadFlutterAsset('assets/ar/index.html');
  }

  Future<void> _exploreInAR() async {
    // Silent spatial bonus — Google Scene Viewer (ar_preferred degrades to 3D).
    final enc = Uri.encodeComponent(widget.modelUrl);
    final url =
        'https://arvr.google.com/scene-viewer/1.0?file=$enc&mode=ar_preferred&title=${Uri.encodeComponent('MITRA')}';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* stays on the in-app lesson */}
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: MitraColors.bgCard,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('This lesson could not be shown on your device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MitraColors.textPrimary, fontSize: 15)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!)
          else
            const Center(child: CircularProgressIndicator(color: MitraColors.saffron)),

          // Close
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _RoundBtn(
                  icon: Icons.close,
                  onTap: () {
                    _controller?.runJavaScript('window.mitraStop && window.mitraStop();');
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
            ),
          ),

          // Bottom controls
          if (_controller != null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PillBtn(
                            label: '🔊 Replay',
                            onTap: () => _controller
                                ?.runJavaScript('window.mitraReplay && window.mitraReplay();'),
                          ),
                          if (widget.allowExplore && Platform.isAndroid) ...[
                            const SizedBox(width: 10),
                            _PillBtn(label: '🧭 Explore in your room', onTap: _exploreInAR),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      _PillBtn(
                        label: '✅ Finish → Quiz',
                        filled: true,
                        onTap: () => context.push('/quiz/${widget.topicId}'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});
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

class _PillBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;
  const _PillBtn({required this.label, required this.onTap, this.filled = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: filled ? null : Colors.black.withValues(alpha: 0.55),
            gradient: filled
                ? const LinearGradient(colors: MitraColors.gradientSaffron)
                : null,
            borderRadius: BorderRadius.circular(999),
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      );
}
