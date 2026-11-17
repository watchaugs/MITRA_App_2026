// ═══════════════════════════════════════════════════════════════════════════
// geo_state_service.dart — GPS-primary state detection + territory licensing.
//
// NOW: students are checked against their HOME state only — see
// territory_service.dart (geoStateProvider below calls it). The server-based
// GeoStateService.resolve() further down is no longer used by the app.
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
import 'territory_service.dart';
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
  final bool inGrace; // location not confirmed now; saved lessons only
  final int? graceDaysLeft;
  const GeoState(this.status,
      {this.detectedState,
      this.message,
      this.inGrace = false,
      this.graceDaysLeft});

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
    } catch (e) {
      debugPrint('📍 GeoState: location-service check failed: $e');
      serviceOn = false;
    }
    if (!serviceOn) {
      debugPrint('📍 GeoState: location services OFF → gpsUnavailable');
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
        debugPrint('📍 GeoState: permission $perm → gpsUnavailable');
        return const GeoState(GeoStatus.gpsUnavailable,
            message: 'Allow location access to continue.');
      }
    } catch (e) {
      debugPrint('📍 GeoState: permission request failed: $e');
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
      } catch (e) {
        debugPrint('📍 GeoState: no GPS fix: $e');
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
      // Coordinates are rounded to 2 decimals (~1 km) so logs never hold a
      // precise location; debugPrint is silent in release builds anyway.
      debugPrint('📍 GeoState: check-point '
          '${pos.latitude.toStringAsFixed(2)},${pos.longitude.toStringAsFixed(2)} '
          '→ inside_any=$insideAny, matches=${matches.map((m) => m['state']).toList()}');
      if (insideAny && matches.isNotEmpty) {
        final state = (matches.first['state'] ?? '').toString();
        if (state.isNotEmpty) {
          return GeoState(GeoStatus.insideTerritory, detectedState: state);
        }
      }
      // GPS is fine but the point is in no geofenced/licensed state.
      return const GeoState(GeoStatus.outsideTerritory,
          message: 'MITRA is not yet available in your location.');
    } catch (e) {
      debugPrint('📍 GeoState: check-point call failed: $e');
      // Backend/network error — treat as GPS-unavailable (fixable), not a block.
      return const GeoState(GeoStatus.gpsUnavailable,
          message: 'Could not verify your location. Check your connection.');
    }
  }
}

bool _forceTerritoryCheck = false;

/// "Check again": re-reads location now, ignoring today's saved result.
void recheckTerritory(WidgetRef ref) {
  _forceTerritoryCheck = true;
  ref.invalidate(geoStateProvider);
}

// Home-state check (territory_service.dart). Re-runs when the signed-in
// student changes, on "Check again", and when the app returns after 24 h.
final geoStateProvider = FutureProvider<GeoState>((ref) async {
  final who = ref.watch(currentUserProvider.select(
      (u) => (u?.id ?? '', u?.assignedState ?? '', u?.isStudent ?? false)));
  if (who.$1.isEmpty || !who.$3) {
    // Not a signed-in student: the home-state rule doesn't apply.
    TerritoryGate.end();
    return GeoState(GeoStatus.insideTerritory, detectedState: who.$2);
  }
  final force = _forceTerritoryCheck;
  _forceTerritoryCheck = false;
  final r = await TerritoryService.resolve(
      uid: who.$1, homeState: who.$2, force: force);
  switch (r.status) {
    case TerritoryStatus.home:
      return GeoState(GeoStatus.insideTerritory, detectedState: r.homeState);
    case TerritoryStatus.grace:
      return GeoState(GeoStatus.insideTerritory,
          detectedState: r.homeState,
          inGrace: true,
          graceDaysLeft: r.graceDaysLeft);
    case TerritoryStatus.outside:
      return GeoState(GeoStatus.outsideTerritory, message: r.message);
    case TerritoryStatus.unverified:
      return GeoState(GeoStatus.gpsUnavailable, message: r.message);
  }
});

// Effective state for content/quiz scoping: the student's HOME state while
// they are confirmed there (or in grace); '' when locked, so nothing loads.
final effectiveStateProvider = Provider<String>((ref) {
  final geo = ref.watch(geoStateProvider).valueOrNull;
  final profileState =
      ref.watch(currentUserProvider.select((u) => u?.assignedState ?? ''));
  if (geo == null) return TerritoryGate.contentAllowed ? profileState : '';
  return geo.status == GeoStatus.insideTerritory
      ? (geo.detectedState ?? profileState)
      : '';
});
