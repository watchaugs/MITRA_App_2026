# ═══════════════════════════════════════════════════════════════════════════
# MITRA — R8 / ProGuard keep-rules for RELEASE builds.
# The release build minifies; R8 would strip the reflectively-loaded native AR
# stack (ARCore + sceneview + Filament) → AR crashes in release only. Keep them.
# ═══════════════════════════════════════════════════════════════════════════

# ── ARCore + sceneview (ar_flutter_plugin_2) + Filament ──
-keep class com.google.ar.** { *; }
-keep class io.github.sceneview.** { *; }
-keep class com.google.android.filament.** { *; }
-keep class dev.romainguy.kotlin.math.** { *; }
-dontwarn com.google.ar.**
-dontwarn io.github.sceneview.**
-dontwarn com.google.android.filament.**

# ── Flutter embedding ──
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# ── Isar (native bindings + reflection) ──
-keep class dev.isar.** { *; }
-dontwarn dev.isar.**