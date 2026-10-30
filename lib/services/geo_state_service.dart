// ═══════════════════════════════════════════════════════════════════════════
// geo_state_service.dart — GPS-primary state detection + territory licensing.
//
// The dashboard geofences entire states (real boundaries). On the app we:
//   1. read the device GPS,
//   2. ask the backend /geofence/check-point which licensed state the point is in,
//   3. use THAT state as the primary source for content/quizzes (falls back to
//      the student's onboarding assigned_state only when GPS is truly usable but
//      returns no state — never to silently widen access).
//
// Licensing is STRICT: a student physically OUTSIDE every geofenced state gets
// no content (status = outsideTerritory). The one safety valve is when GPS is
// unavailable/denied/off — then status = gpsUnavailable and the UI shows an
// "enable location" screen instead of a permanent lock-out (so a declined
// permission or a dead GPS chip is a fixable prompt, not a support ticket).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import '../stores/auth_store.dart';

enum GeoStatus {
  insideTerritory, // GPS resolved to a licensed state → content allowed
  outsideTerritory, // GPS valid but in no licensed state → content blocked
  gpsUnavailable, // GPS off/denied/error → prompt to enable, not a hard block
}

@immutable
class GeoState {
  final GeoStatus status;
  final String? detectedState; // e.g. "Gujarat" (null unless insideTerritory)
  final String? message;
  const GeoState(this.status, {this.detectedState, this.message});

  bool get allowed => status == GeoStatus.insideTerritory;
}

class GeoStateService {
  static const Duration _timeout = Duration(seconds: 20);

  // Resolve the student's licensed state from live GPS.
  static Future<GeoState> resolve() async {
    // 1. Location services on?
    bool serviceOn;
    try {
      serviceOn = await Geolocator.isLocationServiceEnabled().timeout(_timeout);
    } catch (_) {
      serviceOn = false;
    }
    if (!serviceOn) {
      return const GeoState(GeoStatus.gpsUnavailable,
          message: 'Turn on location to access your state\'s lessons.');
    }

    // 2. Permission.
    try {
      var perm = await Geolocator.checkPermission().timeout(_timeout);
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission().timeout(_timeout);
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return const GeoState(GeoStatus.gpsUnavailable,
            message: 'Allow location access to continue.');
      }
    } catch (_) {
      return const GeoState(GeoStatus.gpsUnavailable,
          message: 'Allow location access to continue.');
    }

    // 3. Get a fix — cached first (instant), then a fresh COARSE read.
    // Approximate accuracy only (DPDP data-minimisation): a state is hundreds
    // of km wide, so precise/fine location would collect more than the purpose
    // needs. LocationAccuracy.reduced maps to ACCESS_COARSE_LOCATION.
    Position? pos;
    try {
      pos = await Geolocator.getLastKnownPosition();
    } catch (_) {/* no cached fix */}
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.reduced,
        ).timeout(_timeout);
      } catch (_) {
        return const GeoState(GeoStatus.gpsUnavailable,
            message: 'Could not get your location. Try again outdoors.');
      }
    }

    // 4. Ask the backend which licensed state this point is in.
    try {
      final res = await GeofenceAPI.checkPoint(pos.latitude, pos.longitude);
      final data = res.data;
      final insideAny = data['inside_any'] == true;
      final matches = (data['matches'] as List?) ?? const [];
      if (insideAny && matches.isNotEmpty) {
        final state = (matches.first['state'] ?? '').toString();
        if (state.isNotEmpty) {
          return GeoState(GeoStatus.insideTerritory, detectedState: state);
        }
      }
      // GPS is fine but the point is in no geofenced/licensed state.
      return const GeoState(GeoStatus.outsideTerritory,
          message: 'MITRA is not yet available in your location.');
    } catch (_) {
      // Backend/network error — treat as GPS-unavailable (fixable), not a block.
      return const GeoState(GeoStatus.gpsUnavailable,
          message: 'Could not verify your location. Check your connection.');
    }
  }
}

// One resolution per launch (refreshable). Content providers watch this.
final geoStateProvider = FutureProvider<GeoState>((ref) async {
  return GeoStateService.resolve();
});

// Effective state for content/quiz scoping, shared across the app: GPS-detected
// licensed state is PRIMARY; the onboarding assigned_state is used only when GPS
// is unavailable (never to widen access). Outside every licensed state → ''.
final effectiveStateProvider = Provider<String>((ref) {
  final geo = ref.watch(geoStateProvider).valueOrNull;
  final profileState = ref.watch(currentUserProvider)?.assignedState ?? '';
  if (geo == null) return profileState;
  switch (geo.status) {
    case GeoStatus.insideTerritory:
      return geo.detectedState ?? profileState;
    case GeoStatus.outsideTerritory:
      return '';
    case GeoStatus.gpsUnavailable:
      return profileState;
  }
});
