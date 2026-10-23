// ═══════════════════════════════════════════════════════════════════════════
// MITRA — Native ARCore capability + launcher bridge  (Kotlin)
//
// File: android/app/src/main/kotlin/in/gov/mitra/student/ArLauncherPlugin.kt
// Package MUST match MainActivity.kt → `in`.gov.mitra.student
//
// WHAT THIS DOES
//   The app needs true ground-anchoring on phones that support it, and a safe
//   fallback on phones that don't. Writing a full OpenGL ARCore renderer by hand
//   is thousands of lines and a maintenance burden. Instead this module:
//
//     1. getArTier()  — reports the device's AR capability:
//          "arcore"       → ARCore is installed & supported  (best: anchored AR)
//          "arcore_needs" → supported but ARCore app must be installed/updated
//          "none"         → no ARCore (fall back to the in-app WebXR/viewer)
//
//     2. launchSceneViewer(glbUrl, title) — opens Google Scene Viewer, which is
//        ARCore-backed: real plane detection, world-locked anchoring, and the
//        standard 1-finger drag / 2-finger rotate / pinch gestures, all handled
//        natively by Google. This gives the "anchored to the floor, walk around
//        it" experience on every ARCore phone, with zero custom GL code.
//
//     3. ensureArCore() — triggers the ARCore install/update flow when needed.
//
// WHY SCENE VIEWER FOR THE ANCHORED PATH
//   It is the Google-maintained ARCore surface. It already does exactly the
//   gestures the product asked for (drag on floor, two-finger rotate, pinch
//   scale) and true anchoring, and it is the lowest-risk way for a non-developer
//   to ship reliable ground AR. The in-app WebXR engine (engine.js) remains the
//   fallback for phones where you prefer to stay inside the app UI.
//
// INTEGRATION
//   Registered from MainActivity.configureFlutterEngine (see the MainActivity
//   snippet in the instructions doc). Channel name: "mitra/ar".
// ═══════════════════════════════════════════════════════════════════════════

package `in`.gov.mitra.student

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.plugin.common.MethodChannel

object ArLauncherPlugin {

    const val CHANNEL = "mitra/ar"

    fun handle(activity: Activity, call: String, args: Map<*, *>?, result: MethodChannel.Result) {
        when (call) {
            "getArTier" -> result.success(getArTier(activity))
            "launchSceneViewer" -> {
                val url = (args?.get("glbUrl") as? String).orEmpty()
                val title = (args?.get("title") as? String) ?: "MITRA AR"
                if (url.isEmpty()) {
                    result.error("NO_URL", "glbUrl is required", null)
                } else {
                    val ok = launchSceneViewer(activity, url, title)
                    result.success(ok)
                }
            }
            "ensureArCore" -> {
                // Opens the Play Store page for Google Play Services for AR so the
                // user can install/update it, then the next getArTier() returns
                // "arcore". We don't block the UI thread waiting for it.
                openArCoreInstall(activity)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ── Capability detection ────────────────────────────────────────────────
    // We detect ARCore without compiling against the ARCore SDK, by checking for
    // the Google Play Services for AR package. This keeps the build light; if you
    // later add the com.google.ar:core dependency you can replace this with
    // ArCoreApk.getInstance().checkAvailability(activity) for a richer result.
    private const val AR_PACKAGE = "com.google.ar.core"

    private fun getArTier(activity: Activity): String {
        val pm = activity.packageManager
        // Does the phone even advertise AR capability? (feature flag set by OEMs
        // on ARCore-certified devices.)
        val hasFeature = pm.hasSystemFeature("android.hardware.camera.ar") ||
            isArCoreInstalled(pm)
        if (!hasFeature) return "none"
        return if (isArCoreInstalled(pm)) "arcore" else "arcore_needs"
    }

    private fun isArCoreInstalled(pm: PackageManager): Boolean {
        return try {
            pm.getPackageInfo(AR_PACKAGE, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    // ── Scene Viewer (ARCore-backed anchored AR) ────────────────────────────
    private fun launchSceneViewer(activity: Activity, glbUrl: String, title: String): Boolean {
        return try {
            // mode=3d_preferred (NOT ar_preferred): open in 3D and let the user tap
            // Scene Viewer's own AR button. ar_preferred auto-launches AR and, on
            // some devices, crash-loops ViewerActivity (StackOverflow in Google's
            // code), freezing the screen. 3d_preferred is the safe entry point.
            val sceneUri = Uri.parse(
                "https://arvr.google.com/scene-viewer/1.0?file=" +
                    Uri.encode(glbUrl) +
                    "&mode=3d_preferred&title=" + Uri.encode(title)
            )
            val intent = Intent(Intent.ACTION_VIEW, sceneUri).apply {
                setPackage("com.google.android.googlequicksearchbox")
                // resizable & enabled gestures are Scene Viewer defaults:
                // 1-finger drag on the floor, 2-finger rotate, pinch scale.
            }
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            // No Scene Viewer host → let the caller fall back to WebXR/viewer.
            false
        }
    }

    private fun openArCoreInstall(activity: Activity) {
        try {
            val uri = Uri.parse("market://details?id=$AR_PACKAGE")
            activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
        } catch (e: Exception) {
            try {
                val web = Uri.parse(
                    "https://play.google.com/store/apps/details?id=$AR_PACKAGE")
                activity.startActivity(Intent(Intent.ACTION_VIEW, web))
            } catch (_: Exception) { /* give up silently */ }
        }
    }
}
