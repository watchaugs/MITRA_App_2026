import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../constants/colors.dart';
import '../../services/telemetry_service.dart';

import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
class ArMarkerScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? targetsUrl; // the compiled .mind target (?mind=)
  final String? modelUrl; // the model GLB (?glb=)

  const ArMarkerScreen({
    super.key,
    required this.topicId,
    required this.targetsUrl,
    required this.modelUrl,
  });

  @override
  ConsumerState<ArMarkerScreen> createState() => _ArMarkerScreenState();
}

class _ArMarkerScreenState extends ConsumerState<ArMarkerScreen> {
  WebViewController? _controller;
  String? _error;
  DateTime? _arStart; // for marker-AR duration telemetry
  bool _arStarted = false; // did we log an ar_start (so dispose logs an end)?

  @override
  void initState() {
    super.initState();
    if ((widget.targetsUrl ?? '').isEmpty || (widget.modelUrl ?? '').isEmpty) {
      _error = ref.trNow('ar_this_lesson_has_no_textbook_page', 'This lesson has no textbook-page target to scan.');
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
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (err) {
          if (mounted) {
            setState(() => _error = ref.trpNow('ar_could_not_start_ar_description', 'Could not start AR: {description}', {'description': '${err.description}'}));
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
                  onPressed: () => context.pop(),
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
                  context.tr(ref, 'ar_scan_textbook_page_2', '📄 Scan textbook page'),
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
