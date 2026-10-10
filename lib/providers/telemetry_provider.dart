import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/telemetry_service.dart';

/// Set once at process start in main(); used to compute cold-start time.
DateTime? gAppLaunchedAt;

/// Provider for TelemetryService instance. Initialized after auth succeeds.
///
/// Usage in widgets:
///   final telemetry = ref.watch(telemetryServiceProvider);
///   await telemetry?.logQuizSubmit(...);
final telemetryServiceProvider = StateProvider<TelemetryService?>((ref) {
  return null; // starts null, set by auth flow
});
