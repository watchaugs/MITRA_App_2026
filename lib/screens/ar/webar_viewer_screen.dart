// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: In-app 3D/AR viewer — hosts the offline-bundled three.js + MindAR
// engine (assets/ar/index.html) in a WebView. One engine, three modes:
//   marker  — textbook-page image tracking (needs a .mind target)
//   overlay — model over the live camera feed (no tracking)
//   viewer  — model on a backdrop (no camera; the weakest-phone floor)
// Model + narration play in one process, so audio is always perfectly in sync.
//
// Everything stays IN THE APP — there is no Google Scene Viewer / external
// launcher any more. "Explore in your room" uses in-app WebXR floor AR, with
// camera-overlay view. The engine steps DOWN gracefully on failure
// (marker → overlay → viewer) and never dead-ends.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../constants/colors.dart';
import '../../providers/telemetry_provider.dart';
import '../../services/api_service.dart';
import '../../services/achievement_engine.dart';
import '../../services/ar_launcher.dart';
import '../../stores/module_progress_store.dart';

enum ArMode { marker, overlay, viewer }

String _modeName(ArMode m) => m == ArMode.marker
    ? 'marker'
    : (m == ArMode.overlay ? 'overlay' : 'viewer');

class WebArViewerScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String modelUrl; // GLB (remote R2 URL)
  final String? targetsUrl; // compiled MindAR .mind (marker mode)
  final String? audioUrl; // narration for the current language
  final String? videoUrl; // mp4 that plays on an AR plane
  final String? chromaColor; // hex key colour; non-null = green-screen on
  final ArMode mode;
  final bool allowExplore;

  const WebArViewerScreen({
    super.key,
    required this.topicId,
    required this.modelUrl,
    this.targetsUrl,
    this.audioUrl,
    this.videoUrl,
    this.chromaColor,
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
  bool _stopped = false; // guards against a double teardown
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

  // Stop the engine (releases the camera + audio) while the WebView is still
  // alive. Called on the user-initiated exit (back / close) BEFORE we pop, so
  // the camera surface is gone before Android tears the platform view down.
  // Calling runJavaScript inside dispose() is what crashed the app, so we do it
  // here and never in dispose.
  Future<void> _stopEngine() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _controller
          ?.runJavaScript('window.mitraStop && window.mitraStop();');
    } catch (_) {/* WebView may already be gone — safe to ignore */}
  }

  @override
  void dispose() {
    // Telemetry only — NO runJavaScript here (the platform WebView may already
    // be detached, which was the crash). The engine was stopped in _stopEngine
    // on the way out; the WebView itself is disposed natively by the plugin.
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
    super.dispose();
  }

  // Exit the AR screen cleanly: stop the engine (frees the camera) then pop.
  Future<void> _exit() async {
    await _stopEngine();
    if (mounted) Navigator.of(context).maybePop();
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
          onPageFinished: (_) => _injectConfigAndStart(),
          onWebResourceError: (e) => _stepDown(e.description),
          // Defense-in-depth: the engine lives in a bundled asset and only ever
          // fetches model/media over https. Allow the local asset + our API +
          // CDN hosts; block any attempt to navigate the webview elsewhere.
          onNavigationRequest: (req) {
            final u = req.url;
            final ok = u.startsWith('file:') ||
                u.startsWith('about:') ||
                u.startsWith('https://') ||
                u == 'about:blank';
            return ok
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
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

  // The dashboard returns a RELATIVE model URL (/api/ar/file/<id>_lite.glb).
  // The in-app WebView engine needs an ABSOLUTE https URL, so we prefix it with
  // the API base. Absolute URLs (e.g. an R2 CDN) pass through unchanged.
  String get _absoluteModelUrl {
    final raw = widget.modelUrl;
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = ApiService.instance.dio.options.baseUrl;
    if (base.isEmpty) return raw;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return raw.startsWith('/') ? '$b$raw' : '$b/$raw';
  }

  // Same treatment for the optional narration / marker / video files.
  String? _absolute(String? raw) {
    if (raw == null || raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = ApiService.instance.dio.options.baseUrl;
    if (base.isEmpty) return raw;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return raw.startsWith('/') ? '$b$raw' : '$b/$raw';
  }

  // Inject the config AND start the engine. The old "Begin" splash is gone, so
  // Flutter starts the live view itself the moment the page is ready — one tap
  // from the Learn card and the camera is live.
  void _injectConfigAndStart() {
    final cfg = jsonEncode({
      'mode': _modeName(_mode),
      'modelUrl': _absoluteModelUrl,
      if (widget.targetsUrl != null) 'targetsUrl': _absolute(widget.targetsUrl),
      if (widget.audioUrl != null) 'audioUrl': _absolute(widget.audioUrl),
      if (widget.videoUrl != null) 'videoUrl': _absolute(widget.videoUrl),
      if (widget.chromaColor != null && widget.chromaColor!.isNotEmpty)
        'chromaKey': {'color': widget.chromaColor},
      'scale': 0.5,
    });
    _controller?.runJavaScript(
        'window.MITRA_CONFIG = $cfg; window.mitraStart && window.mitraStart(window.MITRA_CONFIG);');
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
      _stepDown((msg['message'] ?? 'AR error').toString());
    } else if (type == 'model_error') {
      if (mounted) {
        setState(() => _error = (msg['message'] ?? 'Model error').toString());
      }
    } else if (type == 'model_loaded' || type == 'ar_started') {
      // The student has reached the AR lesson → unlock its quiz as a list item.
      ref.read(moduleProgressStoreProvider).markArWatched(widget.topicId);
      ref.read(moduleProgressTickProvider.notifier).state++;
    } else if (type == 'xr_unsupported') {
      // This phone has no WebXR/ARCore for in-app floor AR. The engine already
      // fell back to the overlay view; offer Google Scene Viewer (which uses
      // ARCore) so the student can still place the model on the real floor.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Floor AR needs Google Play Services for AR. Open in your room instead?'),
            action:
                SnackBarAction(label: 'Open', onPressed: _exploreInSceneViewer),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
    // 'target_found' | 'target_lost' | 'model_placed' are available here.
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
    _controller?.loadFlutterAsset('assets/ar/index.html');
  }

  void _replay() {
    _controller?.runJavaScript('window.mitraReplay && window.mitraReplay();');
  }

  // "Explore in your room" — TRUE floor AR. Tries the in-app WebXR engine first
  // (real ground/plane detection + walk-around, ARCore phones). If the phone
  // lacks WebXR/ARCore the engine emits 'xr_unsupported' and we offer Google
  // Scene Viewer as the fallback (see _onEngineMessage).
  // "Explore in your room" — TRUE floor AR, tiered by device capability:
  //   • ARCore present  → native Scene Viewer (reliable ground-lock + gestures)
  //   • ARCore needed   → offer to install Play Services for AR, then Scene Viewer
  //   • no ARCore       → in-app WebXR engine (mitraStartWorld), which itself
  //                       falls back to the overlay viewer if WebXR is absent.
  Future<void> _exploreInRoom() async {
    final tier = await ArLauncher.instance.tier();
    if (tier == ArTier.arcore) {
      await _stopEngine(); // free the camera before the external AR app opens
      final ok = await ArLauncher.instance.launchSceneViewer(
        glbUrl: _absoluteModelUrl,
        title: 'MITRA',
      );
      if (ok) return;
      // Scene Viewer failed to open → fall through to in-app WebXR.
    } else if (tier == ArTier.arcoreNeeds) {
      await ArLauncher.instance.ensureArCore();
      // After install the student can tap again; meanwhile try in-app WebXR.
    }
    _controller
        ?.runJavaScript('window.mitraStartWorld && window.mitraStartWorld();');
  }

  // Fallback: Google Scene Viewer (external ARCore app). Only reached when the
  // phone can't do in-app WebXR floor AR. Needs a public https model URL — the
  // dashboard file route is public, so this works.
  Future<void> _exploreInSceneViewer() async {
    final enc = Uri.encodeComponent(_absoluteModelUrl);
    final url =
        'https://arvr.google.com/scene-viewer/1.0?file=$enc&mode=ar_preferred'
        '&title=${Uri.encodeComponent('MITRA')}';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* stays on the in-app lesson */}
  }

  void _showMoreOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MitraColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Text('🔊', style: TextStyle(fontSize: 22)),
              title: const Text('Replay voiceover',
                  style: TextStyle(color: MitraColors.textPrimary)),
              onTap: () {
                Navigator.of(ctx).pop();
                _replay();
              },
            ),
            ListTile(
              leading: const Text('🧭', style: TextStyle(fontSize: 22)),
              title: const Text('Explore in your room',
                  style: TextStyle(color: MitraColors.textPrimary)),
              subtitle: const Text(
                  'Place the model on your floor and walk around it',
                  style: TextStyle(color: MitraColors.textSecondary)),
              onTap: () {
                Navigator.of(ctx).pop();
                _exploreInRoom();
              },
            ),
            ListTile(
              leading: const Text('✅', style: TextStyle(fontSize: 22)),
              title: const Text('Finish → Quiz',
                  style: TextStyle(color: MitraColors.textPrimary)),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _stopEngine();
                if (mounted) context.push('/quiz/${widget.topicId}');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                    style: TextStyle(
                        color: MitraColors.textPrimary, fontSize: 15)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _exit,
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Intercept the hardware/system back button so we stop the engine (free the
    // camera) before the route pops — this is the other half of the crash fix.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_controller != null)
              WebViewWidget(controller: _controller!)
            else
              const Center(
                  child: CircularProgressIndicator(color: MitraColors.saffron)),

            // Top-left back arrow — returns to the previous screen.
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _RoundBtn(
                    icon: Icons.arrow_back,
                    onTap: _exit,
                  ),
                ),
              ),
            ),

            // Bottom controls: a single "More options" button (no launch splash).
            if (_controller != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _PillBtn(
                      label: '⋯ More options',
                      onTap: _showMoreOptions,
                    ),
                  ),
                ),
              ),
          ],
        ),
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
  const _PillBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ),
      );
}
