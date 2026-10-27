// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: In-app ground-plane AR (embedded ARCore via ar_flutter_plugin_2).
//
// ARLoopa-style experience: ARCore runs INSIDE the app. Camera opens, planes are
// detected, tapping a plane places the animated 3D model anchored to the real
// floor — walk around it. Narration audio (a SEPARATE file — glTF can't carry
// audio) starts in sync when the model is placed. Tapping the model replays.
//
// Plugin: ar_flutter_plugin_2 (maintained fork, sceneview_android backend).
// Audio:  audioplayers.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/glb_cache_manager.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';

import '../../constants/colors.dart';

class ArRoomScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? modelUrl; // https GLB from the catalog/backend (preferred)
  final String? audioUrl; // https narration audio (synced on placement)

  const ArRoomScreen({
    super.key,
    required this.topicId,
    this.modelUrl,
    this.audioUrl,
  });

  static const String _bundledAsset = 'assets/ar/models/mitra_demo_spin.glb';

  @override
  ConsumerState<ArRoomScreen> createState() => _ArRoomScreenState();
}

class _ArRoomScreenState extends ConsumerState<ArRoomScreen> {
  late ARSessionManager _sessionManager;
  late ARObjectManager _objectManager;
  late ARAnchorManager _anchorManager;

  final AudioPlayer _audio = AudioPlayer();
  final List<ARNode> _nodes = [];
  final List<ARAnchor> _anchors = [];
  bool _placed = false;
  String _hint = 'Move your phone slowly to find the floor…';

  @override
  void dispose() {
    _sessionManager.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _roundBtn(Icons.close, () {
                    _audio.stop();
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/student/learn');
                    }
                  }),
                  const Spacer(),
                  if (_placed) _roundBtn(Icons.refresh, _reset),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(MitraRadius.pill),
                  ),
                  child: Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Mukta', color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;

    _sessionManager.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      showWorldOrigin: false,
      handleTaps: true,
    );
    _objectManager.onInitialize();

    _sessionManager.onPlaneOrPointTap = _onPlaneTap;
    // Tapping the placed model replays its animation + narration.
    _objectManager.onNodeTap = (nodes) => _replay();
  }

  Future<void> _onPlaneTap(List<ARHitTestResult> hits) async {
    if (_placed) return;
    if (hits.isEmpty) return;
    final hit = hits.firstWhere(
      (h) => h.type == ARHitTestResultType.plane,
      orElse: () => hits.first,
    );

    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    final okAnchor = await _anchorManager.addAnchor(anchor);
    if (okAnchor != true) {
      setState(() => _hint = 'Could not anchor here — try another spot.');
      return;
    }
    _anchors.add(anchor);

    final isRemote =
        widget.modelUrl != null && widget.modelUrl!.startsWith('http');
    // Remote models are cached on-device (download once, reuse for 30 days) and
    // then loaded from the app folder, so re-opening a lesson is instant and we
    // don't re-pay egress on every view. Falls back to streaming if caching fails.
    String nodeUri;
    NodeType nodeType;
    if (isRemote) {
      final cachedName = await _cacheRemoteModel(widget.modelUrl!);
      if (cachedName != null) {
        nodeUri = cachedName;
        nodeType = NodeType.fileSystemAppFolderGLB;
      } else {
        nodeUri = widget.modelUrl!;
        nodeType = NodeType.webGLB; // fallback: stream directly
      }
    } else {
      nodeUri = await _ensureLocalModel();
      nodeType = NodeType.fileSystemAppFolderGLB;
    }
    final node = ARNode(
      type: nodeType,
      uri: nodeUri,
      scale: vm.Vector3(0.3, 0.3, 0.3),
      position: vm.Vector3(0, 0, 0),
      rotation: vm.Vector4(1, 0, 0, 0),
    );

    final okNode = await _objectManager.addNode(node, planeAnchor: anchor);
    if (okNode == true) {
      _nodes.add(node);
      _startNarration(); // auto-start audio on placement
      setState(() {
        _placed = true;
        _hint = 'Placed! Walk around it. Tap it to replay · ⟳ to move it.';
      });
    } else {
      setState(() => _hint = 'Could not load the model. Check the model file.');
    }
  }

  // Narration: a SEPARATE audio file (glTF cannot carry audio). Starts when the
  // model is placed, and again when the model is tapped.
  Future<void> _startNarration() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _audio.stop();
      if (url.startsWith('http')) {
        await _audio.play(UrlSource(url));
      } else {
        await _audio.play(AssetSource(url)); // e.g. 'ar/audio/xxx.mp3'
      }
    } catch (_) {/* narration is best-effort; never block the model */}
  }

  void _replay() {
    // Re-trigger narration. (The model's own animation loops via the GLB.)
    _startNarration();
  }

  // Downloads (or reuses) the remote GLB via GlbCacheManager, copies it into the
  // app documents folder under a stable name, and returns that filename for
  // NodeType.fileSystemAppFolderGLB. Returns null on any failure so the caller
  // can fall back to streaming.
  Future<String?> _cacheRemoteModel(String url) async {
    try {
      final file = await GlbCacheManager.instance.getSingleFile(url);
      if (!await file.exists()) return null;
      // ar_flutter_plugin_2 wants a name relative to the app documents dir.
      final docs = await getApplicationDocumentsDirectory();
      final fileName =
          'ar_${url.hashCode.toUnsigned(32).toRadixString(16)}.glb';
      final dest = File('${docs.path}/$fileName');
      if (!await dest.exists()) {
        await dest.writeAsBytes(await file.readAsBytes());
      }
      return fileName;
    } catch (_) {
      return null; // caller streams via webGLB instead
    }
  }

  Future<String> _ensureLocalModel() async {
    const fileName = 'mitra_demo_spin.glb';
    final dir = await getApplicationDocumentsDirectory();
    final out = File('${dir.path}/$fileName');
    if (!await out.exists()) {
      final bytes = await rootBundle.load(ArRoomScreen._bundledAsset);
      await out.writeAsBytes(bytes.buffer.asUint8List());
    }
    return fileName;
  }

  Future<void> _reset() async {
    await _audio.stop();
    for (final n in _nodes) {
      await _objectManager.removeNode(n);
    }
    for (final a in _anchors) {
      await _anchorManager.removeAnchor(a);
    }
    _nodes.clear();
    _anchors.clear();
    setState(() {
      _placed = false;
      _hint = 'Tap the floor to place the model.';
    });
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => GestureDetector(
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
