import 'dart:io';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Coarse device capability tier used to pick the richest AR/3D/2D experience
/// a device can deliver *flawlessly*. Computed on-device only — no network,
/// no Cloud cost. Conservative: when unsure we pick a LOWER tier so we never
/// promise an experience the phone can't honour.
enum DeviceTier {
  /// ≤ ~3GB RAM, Android < 8, 32-bit-only, or OS-flagged low-RAM device.
  /// Gets the optimised on-screen 3D model (and later a 2D fallback). No camera AR.
  low,

  /// Mainstream 2020+ budget/mid phone. Surface-placement AR + 3D both run well.
  medium,

  /// 6GB+ RAM on a modern OS. Eligible for the premium textbook image-tracking
  /// AR tier when that feature ships.
  high,
}

/// Result of probing the current device for capability tiering + telemetry.
class DeviceProbeResult {
  final String? deviceModel;
  final String? osVersion;
  final bool? isArCapable;
  final int? ramTotalMb;
  final DeviceTier tier;

  const DeviceProbeResult({
    this.deviceModel,
    this.osVersion,
    this.isArCapable,
    this.ramTotalMb,
    this.tier = DeviceTier.medium,
  });

  static const unknown = DeviceProbeResult();
}

/// Isolates platform/device probing so TelemetryService and the UI can both
/// read the device tier without duplicating logic.
class DeviceProbe {
  static const MethodChannel _channel = MethodChannel('mitra/device');

  final DeviceInfoPlugin _deviceInfo;

  DeviceProbe({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  Future<DeviceProbeResult> probe() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;

        // Native specs (total RAM + OS low-RAM flag). Degrades gracefully if
        // the platform channel isn't present (e.g. an older build).
        int? totalMemBytes;
        bool lowRamDevice = false;
        try {
          final specs =
              await _channel.invokeMapMethod<String, dynamic>('getDeviceSpecs');
          if (specs != null) {
            totalMemBytes = (specs['totalMemBytes'] as num?)?.toInt();
            lowRamDevice = (specs['lowRamDevice'] as bool?) ?? false;
          }
        } catch (_) {
          // Channel missing — tier from OS + ABI alone below.
        }

        final ramMb = totalMemBytes != null
            ? (totalMemBytes / (1024 * 1024)).round()
            : null;
        final sdkInt = info.version.sdkInt;
        final is64Bit = info.supportedAbis
            .any((a) => a.contains('arm64') || a.contains('x86_64'));

        final tier = _classify(
          ramMb: ramMb,
          sdkInt: sdkInt,
          is64Bit: is64Bit,
          lowRamDevice: lowRamDevice,
        );

        return DeviceProbeResult(
          deviceModel: info.model,
          osVersion: 'Android ${info.version.release}',
          // Still a placeholder. The real ARCore availability check lands when
          // the premium textbook image-tracking tier is built, e.g.
          //   isArCapable: (await arCoreAvailability()) == Availability.supportedInstalled
          isArCapable: null,
          ramTotalMb: ramMb,
          tier: tier,
        );
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return DeviceProbeResult(
          deviceModel: info.utsname.machine,
          osVersion: 'iOS ${info.systemVersion}',
          isArCapable: null,
          // iOS isn't our launch target; treat as medium so nothing is gated out.
          tier: DeviceTier.medium,
        );
      }
    } catch (_) {
      // Device info genuinely unavailable (emulator quirk, plugin not
      // registered). Unknown => medium, so we neither over- nor under-serve.
    }
    return DeviceProbeResult.unknown;
  }

  /// Conservative tiering for the Indian entry-level market. Tune later via
  /// Remote Config (firebase_remote_config is already a dependency) if needed.
  static DeviceTier _classify({
    int? ramMb,
    required int sdkInt,
    required bool is64Bit,
    required bool lowRamDevice,
  }) {
    // Hard LOW signals: OS says low-RAM, 32-bit-only, or Android < 8 (API 26).
    if (lowRamDevice || !is64Bit || sdkInt < 26) return DeviceTier.low;

    if (ramMb != null) {
      if (ramMb < 3072) return DeviceTier.low; // ≤ ~3 GB
      if (ramMb >= 6144 && sdkInt >= 29)
        return DeviceTier.high; // 6GB+ on Android 10+
      return DeviceTier.medium;
    }

    // RAM unknown (channel failed): OS-only fallback.
    return sdkInt >= 29 ? DeviceTier.medium : DeviceTier.low;
  }
}
