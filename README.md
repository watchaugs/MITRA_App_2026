# MITRA AR engine — SOURCE (editable)

This folder holds the **editable source** of the in-app AR engine. The app does
**not** run these files directly — it runs the built bundle at
`assets/ar/ar_engine.js`.

```
MITRA_App_2026/
├── ar_engine_src/          ← YOU ARE HERE (source, NOT shipped in the app)
│   ├── engine.js           ← AR engine logic (WebXR, anchoring, model loading)
│   ├── gestures.js         ← touch gestures (1-finger drag, 2-finger rotate, pinch)
│   ├── package.json        ← pins esbuild + three@0.160.0
│   └── README.md           ← this file
└── assets/ar/
    ├── ar_engine.js        ← the BUILT bundle (THIS is what the app runs)
    ├── index.html          ← loads ar_engine.js as a classic <script>
    └── draco/              ← Draco decoders (loaded by the engine)
```

## Does keeping this folder affect the app?
No. It lives at the repo root and is **not** listed under `assets:` in
`pubspec.yaml`, so Flutter never bundles it into the APK. It is build-time source
only — zero effect on app size, behaviour, or features.

## Why a bundle instead of plain scripts?
Android WebView **blocks ES modules** (`import`/`export`, import maps) when a page
is loaded from a `file://` asset — it fails with a CORS error and the AR screen
shows "This lesson could not be shown". So the engine must be ONE **classic**
script. esbuild compiles `engine.js` + `gestures.js` + Three.js into that single
classic IIFE (`ar_engine.js`). **Never hand-edit `assets/ar/ar_engine.js`** — it
is minified build output.

## How to change the engine or the gestures
1. Edit `engine.js` (engine/anchoring) or `gestures.js` (touch mapping) here.
2. From THIS folder, build the bundle:

       npm install      # first time only — pulls esbuild + three@0.160.0
       npm run build    # writes ../assets/ar/ar_engine.js

   (`npm run build` runs:
   `esbuild engine.js --bundle --format=iife --minify --target=es2019 --outfile=../assets/ar/ar_engine.js`)
3. Rebuild/run the Flutter app. `index.html` never changes.

### Gesture tuning quick reference (in gestures.js / engine.js)
- `swipeRot` (gestures.js) — rotation per px of 2-finger horizontal swipe.
- `attachGestures` `k` factor (engine.js) — 1-finger drag speed on the floor.
- scale clamp (engine.js `onScale`) — min/max pinch zoom.

## Requirements
- Node.js (any recent LTS) and npm. `npm install` here pulls everything else
  (esbuild + three) locally into this folder's `node_modules`, which is
  gitignored and never shipped.
