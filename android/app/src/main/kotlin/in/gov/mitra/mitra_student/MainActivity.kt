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
                    else -> result.notImplemented()
                }
            }
    }
}