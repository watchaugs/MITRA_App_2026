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
import '../../services/achievement_engine.dart';
import '../../services/ar_model_cache.dart';
import '../../stores/module_progress_store.dart';

class ArRoomScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String? modelUrl; // https GLB from the catalog/backend (preferred)
  final String? audioUrl; // https narration audio (synced on placement)
  final VoidCallback? onNativeLoadFailed;

  const ArRoomScreen({
    super.key,
    required this.topicId,
    this.modelUrl,
    this.audioUrl,
    this.onNativeLoadFailed,
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
  ARNode? _placedNode; // the current model, for resize buttons
  double _modelScale = 0.3; // current uniform scale (matches placement)
  double _modelY = 0.0; // vertical offset above the floor (metres)
  double _modelZ = 0.0; // depth offset: + = farther, − = nearer (metres)
  double _rotY = 0.0; // rotation about the vertical (Y) axis, in radians
  final List<ARAnchor> _anchors = [];
  bool _placed = false;
  String _hint = 'Move your phone slowly to find the floor…';

  @override
  void initState() {
    super.initState();
    // Track narration progress → unlock the quiz once ≥80% is heard.
    _audio.onPositionChanged.listen((pos) {
      final dur = _audioDuration;
      if (dur == null || dur.inMilliseconds <= 0) return;
      final pct = ((pos.inMilliseconds / dur.inMilliseconds) * 100).round();
      ref
          .read(moduleProgressStoreProvider)
          .recordArProgress(widget.topicId, pct);
    });
    _audio.onDurationChanged.listen((d) => _audioDuration = d);
  }

  Duration? _audioDuration;

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
            // Detect floors AND walls/tables → a trackable surface is found
            // sooner, so placement feels faster.
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
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
          // Resize controls — appear once the model is placed.
          if (_placed)
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roundBtn(Icons.add, () => _resizeBy(1.2)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(MitraRadius.pill),
                      ),
                      child: Text(
                        '${(_modelScale * 100).round()}%',
                        style: const TextStyle(
                            fontFamily: 'Mukta',
                            color: Colors.white,
                            fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _roundBtn(Icons.remove, () => _resizeBy(1 / 1.2)),
                    const SizedBox(height: 18),
                    // Lift the model up / down off the floor (Y axis).
                    _roundBtn(Icons.keyboard_arrow_up, () => _moveY(0.05)),
                    const SizedBox(height: 10),
                    _roundBtn(Icons.keyboard_arrow_down, () => _moveY(-0.05)),
                    const SizedBox(height: 18),
                    // Rotate about Y
                    _roundBtn(Icons.rotate_left, () => _rotateY(-0.3)),
                    const SizedBox(height: 10),
                    _roundBtn(Icons.rotate_right, () => _rotateY(0.3)),
                    const SizedBox(height: 18),
                    // Near / far (depth)
                    _roundBtn(Icons.zoom_out_map, () => _moveZ(-0.1)), // nearer
                    const SizedBox(height: 10),
                    _roundBtn(Icons.zoom_in_map, () => _moveZ(0.1)), // farther
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
      // ONE guide only: the blue plane grid. Feature points (the white/yellow
      // dots) are turned OFF so the student doesn't see two confusing kinds of
      // markers. The plane grid alone is the clear "tap here" cue.
      showFeaturePoints: false,
      showAnimatedGuide: true,
      showPlanes: true,
      showWorldOrigin: false,
      handleTaps: true,
      // handlePans ON keeps the node transformable so the buttons work; it also
      // allows a one-finger MOVE (no tumbling). handleRotation OFF removes the
      // free-axis finger rotation (the somersault). Rotation is ONLY via the
      // ⟲/⟳ buttons → Matrix3.rotationY = spinning-top (single Y axis).
      handlePans: true,
      handleRotation: false,
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
    // Remote models: try the on-device cache first. ArModelCache downloads the
    // model ONCE, keeps the newest 5 on disk (FIFO), and serves them from a tiny
    // loopback server — so the plugin still STREAMS a URL (its only reliable
    // load path via webGLB), but a repeat view pays NO network egress. If the
    // cache can't produce a local URL, we fall back to the plain remote URL so
    // AR never breaks because of caching.
    String nodeUri;
    NodeType nodeType;
    if (isRemote) {
      final localUrl =
          await ArModelCache.instance.localUrlFor(widget.modelUrl!);
      nodeUri = (localUrl != null && localUrl.isNotEmpty)
          ? localUrl
          : widget.modelUrl!;
      nodeType = NodeType.webGLB;
    } else {
      nodeUri = await _ensureLocalModel();
      nodeType = NodeType.fileSystemAppFolderGLB;
    }
    final node = ARNode(
      type: nodeType,
      uri: nodeUri,
      scale: vm.Vector3(_modelScale, _modelScale, _modelScale),
      position: vm.Vector3(0, _modelY, _modelZ),
      rotation:
          vm.Vector4(0, 1, 0, _rotY), // axis = Y, angle = _rotY (spinning top)
    );

    final okNode = await _objectManager.addNode(node, planeAnchor: anchor);
    if (okNode == true) {
      _placedNode = node;
      // Model is down — hide ALL placement guides (plane grid, feature points,
      // animated guide) so the student sees only the model on a clean floor.
      // Gestures stay enabled so they can still move/rotate it.
      _sessionManager.onInitialize(
        showFeaturePoints: false,
        showAnimatedGuide: false,
        showPlanes: false,
        showWorldOrigin: false,
        handleTaps: true,
        // handlePans ON keeps the node transformable so the buttons work; it also
        // allows a one-finger MOVE (slide on the floor — no tumbling).
        // handleRotation OFF removes the free-axis finger rotation (the somersault).
        // Rotation is ONLY via the ⟲/⟳ buttons → Matrix3.rotationY = spinning-top.
        handlePans: true,
        handleRotation: false,
      );
      // Award AR-view XP through the single growth engine (also advances the
      // daily streak). Fire-and-forget; topicId identifies the module.
      ref.read(achievementEngineProvider).recordArView(widget.topicId);
      _nodes.add(node);
      _startNarration(); // auto-start audio on placement
      setState(() {
        _placed = true;
        _hint =
            'Placed! Walk around it. Tap it to replay · use the buttons to move & rotate.';
      });
    } else {
      // Native Filament couldn't load this model (too heavy for the device, or a
      // mis-tiered/Draco GLB slipped through). Rather than a dead end, offer the
      // on-screen 3D viewer, which uses a full WebGL renderer (model_viewer_plus)
      // that handles larger/compressed models far more gracefully than Filament.
      if (mounted) {
        setState(() =>
            _hint = 'This model is heavy for live AR — switching to 3D view…');
        await _anchorManager.removeAnchor(anchor);
        _anchors.remove(anchor);
        if (widget.onNativeLoadFailed != null) {
          widget.onNativeLoadFailed!();
        } else {
          setState(() => _hint =
              'Could not load the model in AR. Try the 3D view from the lesson, or re-upload a lighter model.');
        }
      }
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

  // Resize the placed model by a factor (buttons). Sets node.scale directly —
  // the simplest reliable path. Clamped so it can't vanish or fill the room.
  void _resizeBy(double factor) {
    final node = _placedNode;
    if (node == null) return;
    final next = (_modelScale * factor).clamp(0.05, 2.0);
    _modelScale = next;
    node.scale = vm.Vector3(next, next, next);
    setState(() {}); // refresh the on-screen % label
  }

  // Lift the model up / down off the floor (Y axis). Clamped so it can't fly
  // away or sink through the ground.
  void _moveY(double deltaMetres) {
    final node = _placedNode;
    if (node == null) return;
    _modelY = (_modelY + deltaMetres).clamp(-0.5, 2.0);
    node.position = vm.Vector3(0, _modelY, _modelZ);
    setState(() {});
  }

  // Move the model nearer / farther (depth, Z axis).
  void _moveZ(double deltaMetres) {
    final node = _placedNode;
    if (node == null) return;
    _modelZ = (_modelZ + deltaMetres).clamp(-1.5, 1.5);
    node.position = vm.Vector3(0, _modelY, _modelZ);
    setState(() {});
  }

  // Rotate the model about its vertical (Y) axis.
  void _rotateY(double deltaRadians) {
    final node = _placedNode;
    if (node == null) return;
    _rotY = (_rotY + deltaRadians) % (2 * 3.14159265);
    node.rotation = vm.Matrix3.rotationY(_rotY);
    setState(() {});
  }

  Future<String> _ensureLocalModel() async {
    const fileName = 'mitra_demo_spin.glb';
    final dir = await getApplicationDocumentsDirectory();
    final out = File('${dir.path}/$fileName');
    // Always rewrite from the bundled asset so a stale/old copy from a previous
    // run can never shadow an updated model (that caused "could not load").
    final bytes = await rootBundle.load(ArRoomScreen._bundledAsset);
    await out.writeAsBytes(bytes.buffer.asUint8List());
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
