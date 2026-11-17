// ═══════════════════════════════════════════════════════════════════════════
// territory_service.dart — HOME-STATE-ONLY access for students.
//
// Rule (set by MITRA): a student may use MITRA only while the phone is inside
// an active geofence of the student's REGISTERED (home) state. Anywhere else —
// another state, even one with published content — everything is locked and
// nothing is uploaded or downloaded, until the phone is back home.
//
// How the check works (DPDP-minded):
//   • Foreground only, when the app opens or comes back, at most once a day
//     while the student is at home. Outside / unconfirmed → re-checked on
//     every open so access returns as soon as they are back.
//   • Coarse location, always a fresh reading (a saved position older than
//     10 minutes is ignored). Coordinates are never stored or sent anywhere;
//     only the result (home / outside + time) is kept on this phone.
//   • The check runs ON THE PHONE against the home state's boundary
//     (downloaded from the dashboard, refreshed daily), so it works offline.
//     If no boundary is saved yet, the server check-point is used once.
//
// Grace: when location can't be confirmed (GPS off, permission denied, no
// fix), lessons SAVED ON THE PHONE stay usable for the dashboard's grace days
// (default 7) after the last confirmed home check. During grace nothing is
// uploaded or downloaded.
//
// The static TerritoryGate below is read by the API client, telemetry,
// progress sync and media downloaders, so the rule holds at every level.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

enum TerritoryStatus {
  home, // confirmed inside the home state → everything allowed
  grace, // not confirmed now, home within grace days → saved lessons only
  outside, // confirmed outside the home state → locked
  unverified, // can't confirm and no grace left → locked (turn on location)
}

/// Process-wide gate. Off (open) for anyone who isn't a signed-in student.
class TerritoryGate {
  TerritoryGate._();

  static bool _enforce = false;
  static TerritoryStatus _status = TerritoryStatus.unverified;
  static DateTime? _lastHomeCheck;

  static bool get enforced => _enforce;
  static TerritoryStatus get status => _status;

  /// Lessons and quizzes may be opened.
  static bool get contentAllowed =>
      !_enforce ||
      _status == TerritoryStatus.home ||
      _status == TerritoryStatus.grace;

  /// Uploads / downloads (API calls, telemetry, progress, media) may run.
  static bool get syncAllowed => !_enforce || _status == TerritoryStatus.home;

  /// True when the once-a-day check is due (or the student isn't at home).
  static bool get checkDue {
    if (!_enforce) return false;
    if (_status != TerritoryStatus.home) return true;
    final t = _lastHomeCheck;
    return t == null || DateTime.now().difference(t) >= TerritoryService.recheckAfter;
  }

  /// MITRA API paths that stay open when locked: sign-in, consent (DPDP
  /// rights), and the territory check itself.
  static const _openPaths = ['/api/auth/', '/api/consent/', '/api/geofence/'];

  static bool apiAllowed(String path) {
    if (syncAllowed) return true;
    final p = path.startsWith('http') ? Uri.tryParse(path)?.path ?? path : path;
    return _openPaths.any(p.startsWith);
  }

  /// A student signed in: start enforcing from the last saved result (so
  /// nothing syncs before today's check finishes).
  static void begin(SharedPreferences prefs, String uid, String homeState) {
    _enforce = true;
    final last = TerritoryService._readResult(prefs, uid);
    if (last != null &&
        last.result == 'home' &&
        last.state == TerritoryService.norm(homeState) &&
        DateTime.now().difference(last.at) < TerritoryService.recheckAfter) {
      _status = TerritoryStatus.home;
      _lastHomeCheck = last.at;
    } else {
      _status = TerritoryStatus.unverified;
      _lastHomeCheck = last?.result == 'home' ? last!.at : null;
    }
  }

  /// Signed out (or not a student): stop enforcing.
  static void end() {
    _enforce = false;
    _status = TerritoryStatus.unverified;
    _lastHomeCheck = null;
  }

  static void _set(TerritoryStatus s, {DateTime? homeAt}) {
    _status = s;
    if (homeAt != null) _lastHomeCheck = homeAt;
  }
}

class TerritoryResult {
  final TerritoryStatus status;
  final String homeState;
  final int? graceDaysLeft; // only in grace
  final String? message;
  const TerritoryResult(this.status, this.homeState,
      {this.graceDaysLeft, this.message});
}

class _Saved {
  final String result; // 'home' | 'outside'
  final String state; // normalised home state
  final DateTime at;
  const _Saved(this.result, this.state, this.at);
}

class TerritoryService {
  TerritoryService._();

  static const Duration recheckAfter = Duration(hours: 24);
  static const Duration _boundaryMaxAge = Duration(hours: 24);
  static const Duration _freshFix = Duration(minutes: 10);
  static const Duration _timeout = Duration(seconds: 20);
  static const int _defaultGraceDays = 7;

  // "Jammu & Kashmir" == "jammu and kashmir" (case, spaces, & vs and).
  static String norm(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  static String _resultKey(String uid) => 'territory_result_$uid';

  static _Saved? _readResult(SharedPreferences prefs, String uid) {
    try {
      final raw = prefs.getString(_resultKey(uid));
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map;
      return _Saved('${m['r']}', '${m['s']}',
          DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeResult(
      SharedPreferences prefs, String uid, String result, String state) async {
    await prefs.setString(
        _resultKey(uid),
        jsonEncode({
          'r': result,
          's': norm(state),
          't': DateTime.now().millisecondsSinceEpoch,
        }));
  }

  /// Decides the student's status. [force] skips the once-a-day reuse
  /// ("Check again" button).
  static Future<TerritoryResult> resolve({
    required String uid,
    required String homeState,
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final home = norm(homeState);
    if (uid.isEmpty || home.isEmpty) {
      TerritoryGate._set(TerritoryStatus.unverified);
      return TerritoryResult(TerritoryStatus.unverified, homeState,
          message: 'Your home state is not set.');
    }
    final last = _readResult(prefs, uid);
    final lastHome =
        (last != null && last.result == 'home' && last.state == home) ? last : null;

    // Once a day while at home: reuse today's confirmation, no GPS.
    if (!force &&
        lastHome != null &&
        DateTime.now().difference(lastHome.at) < recheckAfter) {
      TerritoryGate._set(TerritoryStatus.home, homeAt: lastHome.at);
      return TerritoryResult(TerritoryStatus.home, homeState);
    }

    final boundary = await _boundary(home, homeState);
    final graceDays = boundary?.graceDays ?? _defaultGraceDays;

    final inside = await _checkNow(home, homeState, boundary);
    if (inside == true) {
      await _writeResult(prefs, uid, 'home', homeState);
      TerritoryGate._set(TerritoryStatus.home, homeAt: DateTime.now());
      return TerritoryResult(TerritoryStatus.home, homeState);
    }
    if (inside == false) {
      await _writeResult(prefs, uid, 'outside', homeState);
      TerritoryGate._set(TerritoryStatus.outside);
      return TerritoryResult(TerritoryStatus.outside, homeState,
          message: 'You are outside $homeState.');
    }

    // Couldn't confirm → grace from the last confirmed home check.
    if (lastHome != null) {
      final used = DateTime.now().difference(lastHome.at);
      final left = graceDays - used.inDays;
      if (used < Duration(days: graceDays)) {
        TerritoryGate._set(TerritoryStatus.grace);
        return TerritoryResult(TerritoryStatus.grace, homeState,
            graceDaysLeft: left < 1 ? 1 : left);
      }
    }
    TerritoryGate._set(TerritoryStatus.unverified);
    return TerritoryResult(TerritoryStatus.unverified, homeState,
        message: 'Turn on location to confirm you are in $homeState.');
  }

  // true = inside home, false = outside, null = couldn't tell.
  static Future<bool?> _checkNow(
      String home, String homeState, _Boundary? boundary) async {
    final pos = await _freshPosition();
    if (pos == null) return null;
    if (boundary != null && boundary.shapes.isNotEmpty) {
      return boundary.contains(pos.latitude, pos.longitude);
    }
    // No saved boundary yet → ask the server once (point is not stored).
    try {
      final res = await GeofenceAPI.checkPoint(pos.latitude, pos.longitude);
      final matches = (res.data is Map ? res.data['matches'] as List? : null) ??
          const [];
      return matches.any((m) => m is Map && norm('${m['state'] ?? ''}') == home);
    } catch (e) {
      debugPrint('📍 Territory: server check failed: $e');
      return null;
    }
  }

  static Future<Position?> _freshPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled().timeout(_timeout)) {
        return null;
      }
      var perm = await Geolocator.checkPermission().timeout(_timeout);
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission().timeout(_timeout);
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null &&
            DateTime.now().difference(last.timestamp).abs() <= _freshFix) {
          return last;
        }
      } catch (_) {}
      // Coarse only (DPDP data-minimisation): a state is hundreds of km wide.
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.reduced,
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('📍 Territory: no fix: $e');
      return null;
    }
  }

  // ── Home-state boundary, saved on the phone ────────────────────────────────
  static Future<File> _boundaryFile(String home) async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/territory');
    if (!d.existsSync()) d.createSync(recursive: true);
    final safe = home.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return File('${d.path}/$safe.json');
  }

  static Future<_Boundary?> _boundary(String home, String homeState) async {
    final f = await _boundaryFile(home);
    Map<String, dynamic>? saved;
    try {
      if (f.existsSync()) {
        saved = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    final savedAt = DateTime.tryParse('${saved?['saved_at'] ?? ''}');
    final stale = savedAt == null ||
        DateTime.now().difference(savedAt) >= _boundaryMaxAge;
    if (stale) {
      try {
        final res = await GeofenceAPI.territory(homeState);
        if (res.data is Map) {
          final m = Map<String, dynamic>.from(res.data as Map);
          m['saved_at'] = DateTime.now().toIso8601String();
          await f.writeAsString(jsonEncode(m));
          saved = m;
        }
      } catch (e) {
        debugPrint('📍 Territory: boundary refresh failed: $e');
      }
    }
    return saved == null ? null : _Boundary.fromJson(saved);
  }
}

// One state's active geofences: polygons (GeoJSON) and/or circles.
class _Boundary {
  final List<Object> shapes; // List<List<List<double>>> rings, or _Circle
  final int graceDays;
  const _Boundary(this.shapes, this.graceDays);

  factory _Boundary.fromJson(Map<String, dynamic> m) {
    final shapes = <Object>[];
    for (final g in (m['geofences'] as List? ?? const [])) {
      if (g is! Map) continue;
      if (g['type'] == 'circle') {
        final lat = (g['lat'] as num?)?.toDouble();
        final lng = (g['lng'] as num?)?.toDouble();
        final r = (g['radius_km'] as num?)?.toDouble();
        if (lat != null && lng != null && r != null) {
          shapes.add(_Circle(lat, lng, r));
        }
        continue;
      }
      final geo = g['geometry'];
      if (geo is! Map) continue;
      final coords = geo['coordinates'];
      final polys = geo['type'] == 'MultiPolygon'
          ? (coords as List? ?? const [])
          : [coords];
      for (final p in polys) {
        if (p is! List || p.isEmpty || p.first is! List) continue;
        final ring = <List<double>>[];
        for (final pt in p.first as List) {
          if (pt is List && pt.length >= 2) {
            ring.add([(pt[0] as num).toDouble(), (pt[1] as num).toDouble()]);
          }
        }
        if (ring.length >= 3) shapes.add(ring);
      }
    }
    final grace = (m['grace_days'] as num?)?.toInt();
    return _Boundary(shapes, (grace == null || grace < 0) ? 7 : grace);
  }

  bool contains(double lat, double lng) {
    for (final s in shapes) {
      if (s is _Circle) {
        if (s.contains(lat, lng)) return true;
      } else if (s is List<List<double>> && _inRing(lat, lng, s)) {
        return true;
      }
    }
    return false;
  }

  // Ray casting; GeoJSON points are [lng, lat] (same as the server check).
  static bool _inRing(double lat, double lng, List<List<double>> ring) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i][0], yi = ring[i][1];
      final xj = ring[j][0], yj = ring[j][1];
      final cross = ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (cross) inside = !inside;
    }
    return inside;
  }
}

class _Circle {
  final double lat, lng, radiusKm;
  const _Circle(this.lat, this.lng, this.radiusKm);

  // Haversine distance, same as the server's circle check.
  bool contains(double la, double ln) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(la - lat), dLng = rad(ln - lng);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(la)) * math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c <= radiusKm;
  }
}
