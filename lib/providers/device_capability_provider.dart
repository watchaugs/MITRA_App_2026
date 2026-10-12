import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/device_probe.dart';

/// Probes the device once and caches the capability result for the whole app.
/// Drives AR/3D/2D tiering. On-device only — no network, no Cloud cost.
final deviceCapabilityProvider = FutureProvider<DeviceProbeResult>((ref) async {
  return DeviceProbe().probe();
});
