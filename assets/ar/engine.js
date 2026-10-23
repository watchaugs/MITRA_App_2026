// ═══════════════════════════════════════════════════════════════════════════
// MITRA AR ENGINE  (readable, editable source — replaces the old minified bundle)
//
// This is the WebView engine used for the "Explore in your room" floor-AR path
// and for the simple 3D viewer. It is hand-written and meant to be edited.
//
// Three.js itself is loaded as a versioned module (see index.html's importmap),
// so the only thing you maintain here is MITRA's own logic: WebXR floor
// detection, world-locked anchoring, and the touch-gesture system.
//
// PUBLIC API (called by webar_viewer_screen.dart via runJavaScript) — unchanged
// from the old engine so the Dart side needs no rewrite:
//   window.mitraStart(config)   – start in the mode given by config.mode
//   window.mitraStartWorld()    – (re)enter world/floor AR (WebXR hit-test)
//   window.mitraReplay()        – replay narration/animation
//   window.mitraStop()          – stop engine, release camera + audio
//
// MESSAGES posted back to Flutter (channel "MitraAR", JSON string) — unchanged:
//   {type:'model_loaded'} {type:'ar_started'} {type:'xr_unsupported'}
//   {type:'model_placed'} {type:'fatal', message} {type:'model_error', message}
//
// GESTURES (recommended AR set, confirmed with product):
//   • 1-finger drag  → slide the model across the floor (X + Z on the ground plane)
//   • 2-finger twist / horizontal swipe → rotate the model about its vertical axis
//   • pinch          → scale the model
// World-locked: once placed, the model stays on its floor spot; the student walks
// around it. (WebXR anchors keep it fixed relative to the real room.)
// ═══════════════════════════════════════════════════════════════════════════

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { DRACOLoader } from 'three/addons/loaders/DRACOLoader.js';

import { GestureController } from './gestures.js';

// ── Engine singleton state ───────────────────────────────────────────────────
const S = {
  renderer: null,
  scene: null,
  camera: null,
  model: null,        // the loaded GLB root (THREE.Group)
  modelHolder: null,  // a parent we translate/rotate/scale via gestures
  reticle: null,      // ring shown on detected floor before placement
  xrSession: null,
  xrRefSpace: null,
  xrViewerSpace: null,
  hitTestSource: null,
  anchor: null,       // XRAnchor once placed (keeps it world-locked)
  placed: false,
  mixer: null,        // animation mixer
  clock: new THREE.Clock(),
  audio: null,        // HTMLAudioElement for narration
  config: null,
  gestures: null,
  mode: 'viewer',
  running: false,
};

// ── Flutter bridge ───────────────────────────────────────────────────────────
function post(obj) {
  try {
    if (window.MitraAR && window.MitraAR.postMessage) {
      window.MitraAR.postMessage(JSON.stringify(obj));
    }
  } catch (_) { /* channel not present (e.g. desktop test) */ }
}

function hint(text) {
  const el = document.getElementById('hint');
  if (!el) return;
  if (text) { el.textContent = text; el.classList.remove('hidden'); }
  else { el.classList.add('hidden'); }
}

// ── Basic three.js scene (shared by viewer + world AR) ───────────────────────
function initRenderer() {
  if (S.renderer) return;
  const canvas = document.createElement('canvas');
  document.getElementById('ar-container').appendChild(canvas);

  S.renderer = new THREE.WebGLRenderer({
    canvas, alpha: true, antialias: true, preserveDrawingBuffer: false,
  });
  S.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  S.renderer.setSize(window.innerWidth, window.innerHeight);
  S.renderer.outputColorSpace = THREE.SRGBColorSpace;

  S.scene = new THREE.Scene();
  S.camera = new THREE.PerspectiveCamera(
    60, window.innerWidth / window.innerHeight, 0.01, 50);

  // Lighting that reads well for school 3D content without being flat.
  const hemi = new THREE.HemisphereLight(0xffffff, 0x444466, 1.1);
  S.scene.add(hemi);
  const dir = new THREE.DirectionalLight(0xffffff, 1.0);
  dir.position.set(1, 3, 2);
  S.scene.add(dir);

  window.addEventListener('resize', onResize);
}

function onResize() {
  if (!S.renderer) return;
  S.camera.aspect = window.innerWidth / window.innerHeight;
  S.camera.updateProjectionMatrix();
  S.renderer.setSize(window.innerWidth, window.innerHeight);
}

// ── Model loading ────────────────────────────────────────────────────────────
function loadModel(url) {
  return new Promise((resolve, reject) => {
    const loader = new GLTFLoader();
    const draco = new DRACOLoader();
    // Draco decoder is bundled offline next to the engine.
    draco.setDecoderPath('./draco/');
    loader.setDRACOLoader(draco);

    loader.load(
      url,
      (gltf) => {
        const root = gltf.scene || gltf.scenes[0];
        // Normalise: center the model and scale it to a sensible ~0.4 m height
        // so it sits naturally on the floor regardless of its authored size.
        const box = new THREE.Box3().setFromObject(root);
        const size = new THREE.Vector3();
        const center = new THREE.Vector3();
        box.getSize(size);
        box.getCenter(center);
        root.position.sub(center);                 // center at origin
        const maxDim = Math.max(size.x, size.y, size.z) || 1;
        const target = 0.4;                        // 40 cm default
        const k = target / maxDim;
        root.scale.setScalar(k);
        // Lift so the model's base sits on y=0 (the floor), not through it.
        const box2 = new THREE.Box3().setFromObject(root);
        root.position.y -= box2.min.y;

        // Animations
        if (gltf.animations && gltf.animations.length) {
          S.mixer = new THREE.AnimationMixer(root);
          gltf.animations.forEach((clip) => S.mixer.clipAction(clip).play());
        }
        resolve(root);
      },
      undefined,
      (err) => reject(err),
    );
  });
}

// ── Narration audio (kept in sync — one process, same as before) ─────────────
function startAudio(url) {
  if (!url) return;
  try {
    stopAudio();
    S.audio = new Audio(url);
    S.audio.crossOrigin = 'anonymous';
    S.audio.play().catch(() => { /* autoplay guarded; tap already granted it */ });
  } catch (_) {}
}
function stopAudio() {
  if (S.audio) { try { S.audio.pause(); } catch (_) {} S.audio = null; }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODE 1 — simple VIEWER (no camera): model on a dark backdrop, orbit-ish.
// This is the weakest-phone floor and the default.
// ═══════════════════════════════════════════════════════════════════════════
async function startViewer(config) {
  initRenderer();
  S.mode = 'viewer';
  S.scene.background = new THREE.Color(0x0b0b12);
  S.camera.position.set(0, 0.3, 1.2);
  S.camera.lookAt(0, 0.2, 0);

  try {
    const root = await loadModel(config.modelUrl);
    S.model = root;
    S.modelHolder = new THREE.Group();
    S.modelHolder.add(root);
    S.scene.add(S.modelHolder);
    post({ type: 'model_loaded' });
  } catch (e) {
    post({ type: 'model_error', message: String(e && e.message || e) });
    return;
  }

  startAudio(config.audioUrl);
  attachGestures(/* worldLocked */ false);
  renderLoopViewer();
}

function renderLoopViewer() {
  if (!S.running) return;
  const dt = S.clock.getDelta();
  if (S.mixer) S.mixer.update(dt);
  S.renderer.render(S.scene, S.camera);
  requestAnimationFrame(renderLoopViewer);
}

// ═══════════════════════════════════════════════════════════════════════════
// MODE 2 — WORLD / FLOOR AR via WebXR hit-test + anchors (true ground-lock).
// Only works where the WebView exposes WebXR immersive-ar + hit-test (few
// Android WebViews do). If unsupported we tell Flutter → it offers Scene Viewer
// or the native ARCore path instead.
// ═══════════════════════════════════════════════════════════════════════════
async function startWorld() {
  initRenderer();
  S.mode = 'world';

  if (!navigator.xr) { post({ type: 'xr_unsupported' }); return; }
  let supported = false;
  try { supported = await navigator.xr.isSessionSupported('immersive-ar'); }
  catch (_) { supported = false; }
  if (!supported) { post({ type: 'xr_unsupported' }); return; }

  try {
    const session = await navigator.xr.requestSession('immersive-ar', {
      requiredFeatures: ['hit-test', 'local-floor'],
      optionalFeatures: ['anchors', 'dom-overlay'],
      domOverlay: { root: document.body },
    });
    S.xrSession = session;
    S.renderer.xr.enabled = true;
    await S.renderer.xr.setReferenceSpaceType('local-floor');
    await S.renderer.xr.setSession(session);

    // Reticle: a ring that sits on the detected floor until the user taps.
    const ringGeo = new THREE.RingGeometry(0.07, 0.09, 32).rotateX(-Math.PI / 2);
    const ringMat = new THREE.MeshBasicMaterial({ color: 0xffb300 });
    S.reticle = new THREE.Mesh(ringGeo, ringMat);
    S.reticle.matrixAutoUpdate = false;
    S.reticle.visible = false;
    S.scene.add(S.reticle);

    S.xrViewerSpace = await session.requestReferenceSpace('viewer');
    S.xrRefSpace = await session.requestReferenceSpace('local-floor');
    S.hitTestSource = await session.requestHitTestSource({ space: S.xrViewerSpace });

    // Pre-load the model now (invisible) so placement is instant on tap.
    if (!S.model) {
      try {
        const root = await loadModel(S.config.modelUrl);
        S.model = root;
        S.modelHolder = new THREE.Group();
        S.modelHolder.visible = false;
        S.modelHolder.add(root);
        S.scene.add(S.modelHolder);
        post({ type: 'model_loaded' });
      } catch (e) {
        post({ type: 'model_error', message: String(e && e.message || e) });
      }
    }

    hint('Point at the floor, then tap to place');
    // Tap to place / re-place.
    session.addEventListener('select', onXRSelect);
    session.addEventListener('end', () => { S.xrSession = null; });

    post({ type: 'ar_started' });
    S.renderer.setAnimationLoop(onXRFrame);
  } catch (e) {
    post({ type: 'xr_unsupported' }); // treat any session failure as "unsupported"
  }
}

function onXRSelect() {
  if (!S.reticle || !S.reticle.visible || !S.modelHolder) return;
  // Place the model where the reticle is. Use an XRAnchor when available so the
  // model stays world-locked (fixed to the real floor spot) as the user walks.
  const m = new THREE.Matrix4().fromArray(S.reticle.matrix.elements);
  const pos = new THREE.Vector3();
  const quat = new THREE.Quaternion();
  const scl = new THREE.Vector3();
  m.decompose(pos, quat, scl);

  S.modelHolder.position.copy(pos);
  S.modelHolder.quaternion.identity();   // keep upright; gestures rotate from here
  S.modelHolder.visible = true;
  S.placed = true;
  hint('');

  attachGestures(/* worldLocked */ true);
  post({ type: 'model_placed' });

  // Anchor (optional feature) — keeps the spot stable over time.
  if (S.xrSession && S.xrSession.requestHitTestSource && S.reticle.xrHitPose) {
    // Anchors are created in onXRFrame from the latest hit result.
    S._wantAnchor = true;
  }
}

function onXRFrame(timestamp, frame) {
  if (!frame) return;
  const dt = S.clock.getDelta();
  if (S.mixer) S.mixer.update(dt);

  if (!S.placed && S.hitTestSource) {
    const results = frame.getHitTestResults(S.hitTestSource);
    if (results.length) {
      const pose = results[0].getPose(S.xrRefSpace);
      if (pose) {
        S.reticle.visible = true;
        S.reticle.matrix.fromArray(pose.transform.matrix);
        S.reticle.xrHitPose = pose; // stash for anchor creation
      }
    } else {
      S.reticle.visible = false;
    }
  }

  // Create an anchor once, right after placement, to world-lock the model.
  if (S._wantAnchor && S.placed && frame.createAnchor && S.reticle.xrHitPose) {
    S._wantAnchor = false;
    try {
      frame.createAnchor(S.reticle.xrHitPose.transform, S.xrRefSpace)
        .then((anchor) => { S.anchor = anchor; })
        .catch(() => { /* anchors optional; hit-pose placement already holds */ });
    } catch (_) {}
  }
  // Keep the model glued to its anchor if we have one.
  if (S.anchor && S.placed && S.modelHolder) {
    const aPose = frame.getPose(S.anchor.anchorSpace, S.xrRefSpace);
    if (aPose) {
      S.modelHolder.position.set(
        aPose.transform.position.x,
        aPose.transform.position.y,
        aPose.transform.position.z);
    }
  }

  S.renderer.render(S.scene, S.camera);
}

// ── Gesture wiring ───────────────────────────────────────────────────────────
// The GestureController reads raw touch events and calls back with deltas; we
// apply them to S.modelHolder. In world mode, rotation/scale/drag operate on the
// placed model while it stays anchored to the floor spot.
function attachGestures(worldLocked) {
  if (S.gestures) S.gestures.dispose();
  S.gestures = new GestureController(document.getElementById('ar-container'), {
    onDrag: (dx, dz) => {
      if (!S.modelHolder) return;
      // Slide across the ground plane. Scale factor keeps it comfortable on phone.
      const k = 0.0016;
      S.modelHolder.position.x += dx * k;
      S.modelHolder.position.z += dz * k;
    },
    onRotate: (radians) => {
      if (!S.modelHolder) return;
      S.modelHolder.rotation.y += radians;
    },
    onScale: (factor) => {
      if (!S.modelHolder) return;
      const s = THREE.MathUtils.clamp(S.modelHolder.scale.x * factor, 0.1, 6);
      S.modelHolder.scale.setScalar(s);
    },
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════════════════════
window.mitraStart = async function (config) {
  try {
    S.config = config || window.MITRA_CONFIG || {};
    S.running = true;
    const mode = S.config.mode || 'viewer';
    if (mode === 'world') { await startWorld(); }
    else { await startViewer(S.config); } // marker/overlay collapse to viewer here;
    // true camera-overlay + marker tracking remain in the bundled MindAR path if
    // you keep it; this rebuilt engine focuses on viewer + world AR.
  } catch (e) {
    post({ type: 'fatal', message: String(e && e.message || e) });
  }
};

window.mitraStartWorld = async function () {
  try {
    S.running = true;
    S.placed = false;
    S.anchor = null;
    await startWorld();
  } catch (e) {
    post({ type: 'xr_unsupported' });
  }
};

window.mitraReplay = function () {
  if (S.mixer) {
    S.mixer.stopAllAction();
    S.mixer._actions.forEach((a) => { a.reset(); a.play(); });
  }
  if (S.config && S.config.audioUrl) startAudio(S.config.audioUrl);
};

window.mitraStop = function () {
  S.running = false;
  try { if (S.gestures) S.gestures.dispose(); } catch (_) {}
  stopAudio();
  try {
    if (S.xrSession) { S.xrSession.end().catch(() => {}); S.xrSession = null; }
  } catch (_) {}
  try { if (S.renderer) S.renderer.setAnimationLoop(null); } catch (_) {}
};
