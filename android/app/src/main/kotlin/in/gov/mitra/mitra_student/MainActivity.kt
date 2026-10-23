package `in`.gov.mitra.student

import android.app.ActivityManager
import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "mitra/device"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots, screen recording, and hide app content in the
        // recents/app-switcher preview. OS-enforced.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

     
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceSpecs" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE)
                            as ActivityManager
                        val mi = ActivityManager.MemoryInfo()
                        am.getMemoryInfo(mi)
                        result.success(
                            hashMapOf(
                                "totalMemBytes" to mi.totalMem,
                                "lowRamDevice" to am.isLowRamDevice,
                                "processors" to Runtime.getRuntime().availableProcessors()
                            )
                        )
                    }
                    "checkArCore" -> {
                        val a = com.google.ar.core.ArCoreApk.getInstance()
                            .checkAvailability(this)
                        val s = when (a) {
                            com.google.ar.core.ArCoreApk.Availability.SUPPORTED_INSTALLED -> "supported_installed"
                            com.google.ar.core.ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD -> "supported_apk_too_old"
                            com.google.ar.core.ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> "supported_not_installed"
                            com.google.ar.core.ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> "unsupported"
                            com.google.ar.core.ArCoreApk.Availability.UNKNOWN_CHECKING,
                            com.google.ar.core.ArCoreApk.Availability.UNKNOWN_TIMED_OUT,
                            com.google.ar.core.ArCoreApk.Availability.UNKNOWN_ERROR -> "unknown"
                            else -> "unknown"
                        }
                        result.success(s)
                    }
                    "requestArCoreInstall" -> {
                        try {
                            val st = com.google.ar.core.ArCoreApk.getInstance()
                                .requestInstall(this, true)
                            // INSTALLED → ready now; INSTALL_REQUESTED → user is
                            // completing the Play flow (treat as not-yet-ready).
                            result.success(
                                st == com.google.ar.core.ArCoreApk.InstallStatus.INSTALLED
                            )
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}