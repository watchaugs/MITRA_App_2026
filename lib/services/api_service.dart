// ═══════════════════════════════════════════════════════
// MITRA API Service — Dio client with auth + auto-refresh
// Mirrors services/api.ts from Expo project
// ═══════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import 'territory_service.dart'; // TerritoryGate (home-state rule)
import 'dart:convert';
import 'dart:io';

const _storage = FlutterSecureStorage();

// ── Dio singleton ──────────────────────────────────────
class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  static ApiService get instance => _instance;

  late final Dio _dio;

  // Origin header derived from the API base URL (or overridden via env),
  // so changing the dashboard URL never needs a code change.
  static String get _origin {
    final override = dotenv.env['API_ORIGIN'];
    if (override != null && override.isNotEmpty) return override;
    final base = dotenv.env['API_BASE_URL'] ?? '';
    try {
      final u = Uri.parse(base);
      if (u.hasScheme && u.host.isNotEmpty) return '${u.scheme}://${u.host}';
    } catch (_) {}
    return base;
  }

  void init() {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // 🚨 FIX 1: The CORS Disguise to bypass the 403 Forbidden error
        'Origin': _origin,
      },
    ));

    // ── Request interceptor: attach JWT & Compress Payload ──────────────
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Home-state rule: while a student is outside their home state (or
        // it can't be confirmed), nothing goes to or comes from MITRA except
        // sign-in, consent/data-rights and the location check itself.
        if (!TerritoryGate.apiAllowed(options.path)) {
          return handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: 'outside_home_state',
          ));
        }
        final token = await _storage.read(key: 'mitra_access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        // ✨ BANDWIDTH FIX: Gzip outgoing batches
        // Only compress POST/PUT requests with payloads larger than 1KB
        // Skip bodies already gzipped (a 401-retry re-runs this interceptor on
        // the same options — compressing twice corrupts the payload).
        if ((options.method == 'POST' || options.method == 'PUT') &&
            options.data != null &&
            options.headers['Content-Encoding'] != 'gzip') {
          try {
            final jsonString = jsonEncode(options.data);
            final bytes = utf8.encode(jsonString);

            if (bytes.length > 1024) {
              final compressedBytes = gzip.encode(bytes);
              options.data = compressedBytes;
              options.headers['Content-Encoding'] = 'gzip';
              // Dio will automatically calculate the new, much smaller Content-Length
            }
          } catch (e) {
            // If encoding fails for any reason, it silently falls back to sending raw JSON
            // debugPrint('Payload compression failed: $e');
          }
        }

        handler.next(options);
      },

      // ── Response interceptor: auto-refresh on 401 ──
      onError: (error, handler) async {
        final response = error.response;
        if (response?.statusCode == 401) {
          final code = response?.data?['code'];

          if (code == 'ACCOUNT_INACTIVE') {
            await _storage.delete(key: 'mitra_access_token');
            await _storage.delete(key: 'mitra_refresh_token');
            handler.reject(error);
            return;
          }

          // Already retried once with a new token → give up on this call.
          final opts = error.requestOptions;
          if (opts.extra['mitra_retried'] == true) {
            handler.reject(error);
            return;
          }
          // Another call may have renewed the tokens while this one was in
          // flight: then just retry with the new token (no second refresh —
          // the server treats a reused refresh token as theft and ends the
          // whole session, which used to leave the app signed in with no
          // token and stuck on the location screen).
          final sent = '${opts.headers['Authorization'] ?? ''}';
          final current = await _storage.read(key: 'mitra_access_token');
          final renewal = (current != null &&
                  current.isNotEmpty &&
                  sent != 'Bearer $current')
              ? (token: current, signedOut: false)
              : await renewTokens();
          final token = renewal.token;

          if (token == null && !renewal.signedOut) {
            // No network for the renewal: keep the tokens, fail this call.
            handler.reject(error);
            return;
          }
          if (token == null) {
            // Signed out for real (refresh and Firebase session both
            // rejected): wipe the dead tokens and go to sign-in.
            await _storage.delete(key: 'mitra_access_token');
            await _storage.delete(key: 'mitra_refresh_token');
            if (rootNavigatorKey.currentContext != null) {
              rootNavigatorKey.currentContext!.go('/login');
            }
            handler.reject(error);
            return;
          }

          // Retry the original request once with the new token. A failure
          // here is that request's own error — the tokens stay.
          opts.headers['Authorization'] = 'Bearer $token';
          opts.extra['mitra_retried'] = true;
          try {
            handler.resolve(await _dio.fetch(opts));
          } on DioException catch (e) {
            handler.reject(e);
          }
          return;
        }
        handler.reject(error);
      },
    ));
  }

  // One renewal at a time: calls that fail together share it.
  Future<({String? token, bool signedOut})>? _renewing;

  /// New MITRA tokens for the signed-in student: first the refresh token,
  /// then — if that is gone or rejected — the Firebase sign-in the phone
  /// still holds (the same exchange as signing in). `token` is the new access
  /// token; when it is null, `signedOut` says the server rejected both (true)
  /// rather than the phone being offline (false: keep the old tokens).
  Future<({String? token, bool signedOut})> renewTokens() =>
      _renewing ??= _renew().whenComplete(() => _renewing = null);

  Future<({String? token, bool signedOut})> _renew() async {
    final plain = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Origin': _origin},
    ));
    Future<String?> save(Response res) async {
      final at = res.data is Map ? res.data['access_token'] as String? : null;
      if (at == null || at.isEmpty) return null;
      await _storage.write(key: 'mitra_access_token', value: at);
      // The server ROTATES the refresh token on every use and revokes the
      // old one, so the new one must be saved.
      final rt = res.data['refresh_token'] as String?;
      if (rt != null && rt.isNotEmpty) {
        await _storage.write(key: 'mitra_refresh_token', value: rt);
      }
      return at;
    }

    // The server answered (any HTTP status) = a real rejection; no answer =
    // offline / timeout.
    bool answered(Object e) => e is DioException && e.response != null;
    var offline = false;
    try {
      final rt = await _storage.read(key: 'mitra_refresh_token');
      if (rt != null && rt.isNotEmpty) {
        final t = await save(
            await plain.post('/api/auth/refresh', data: {'refresh_token': rt}));
        if (t != null) return (token: t, signedOut: false);
      }
    } catch (e) {
      debugPrint('🔑 Token refresh failed: $e');
      if (!answered(e)) offline = true;
    }
    final fu = FirebaseAuth.instance.currentUser;
    if (fu == null) return (token: null, signedOut: !offline);
    try {
      final idToken = await fu.getIdToken();
      final t = await save(await plain.post('/api/auth/firebase',
          data: {'id_token': idToken, 'role': 'student'}));
      if (t != null) {
        debugPrint('🔑 New sign-in token from the Firebase session');
      }
      return (token: t, signedOut: t == null && !offline);
    } catch (e) {
      debugPrint('🔑 Firebase token exchange failed: $e');
      return (token: null, signedOut: !offline && answered(e));
    }
  }

  Dio get dio => _dio;
}

// ── Convenience getter ─────────────────────────────────
Dio get api => ApiService.instance.dio;

// ═══════════════════════════════════════════════════════
// API Methods by Domain — mirrors Expo authAPI, usersAPI, etc.
// ═══════════════════════════════════════════════════════

class AuthAPI {
  static Future<Response> login(String phone, String role) =>
      api.post('/api/auth/login', data: {
        'phone': phone,
        'role': role,
        'method':
            'sms', // 🚨 FIX 4: Forces the backend into the "Mobile OTP" lane
      });

  static Future<Response> me() => api.get('/api/auth/me');

  static Future<Response> logout() => api.post('/api/auth/logout');

  static Future<Response> refresh(String refreshToken) =>
      api.post('/api/auth/refresh', data: {
        'refresh_token': refreshToken // Matches the backend requirement
      });
}

class UsersAPI {
  static Future<Response> update(String id, Map<String, dynamic> data) =>
      api.put('/api/users/$id', data: data);
}

class CurriculumAPI {
  static Future<Response> tree({String? state}) => api.get(
        '/api/curriculum/tree',
        queryParameters:
            (state != null && state.isNotEmpty) ? {'state': state} : null,
      );

  static Future<Response> arTopics(Map<String, String> params) =>
      api.get('/api/curriculum/ar-topics', queryParameters: params);

  // Cost-shield: one hard-cached read per state per launch, instead of a
  // Firestore collection scan. Superset of /ar-topics (adds class/subject/topic
  // structure). The app prefers this and falls back to arTopics() if empty.
  static Future<Response> manifest(String state, {String? stateName}) =>
      api.get('/api/curriculum/manifest/$state', queryParameters: {
        if (stateName != null && stateName.isNotEmpty) 'state_name': stateName,
      });

  static Future<Response> hierarchy(String stateCode) =>
      api.get('/api/curriculum/hierarchy/$stateCode');

  // Real subject tiles for Home, derived from published AR assets, state-scoped.
  static Future<Response> subjects(String state) => api.get(
      '/api/curriculum/subjects/${Uri.encodeComponent(state.isEmpty ? "ALL" : state)}');

  // Learning rules set on the dashboard (e.g. ar_watch_threshold). Cheap read;
  // the app falls back to safe defaults if this fails.
  static Future<Response> learningSettings() =>
      api.get('/api/curriculum/learning-settings');
}

class ArAPI {
  static Future<Response> assets(Map<String, String> params) =>
      api.get('/api/ar/assets', queryParameters: params);

  static Future<Response> asset(String id) => api.get('/api/ar/assets/$id');

  static Future<Response> links(String nodeId) =>
      api.get('/api/ar/links/$nodeId');
}

class GeofenceAPI {
  // Resolve which licensed state a GPS point falls in.
  static Future<Response> checkPoint(double lat, double lng) =>
      api.get('/api/geofence/check-point',
          queryParameters: {'lat': lat, 'lng': lng});

  // The home state's active geofence boundaries + offline grace days, for
  // the on-phone location check (territory_service.dart). No location sent.
  static Future<Response> territory(String state) =>
      api.get('/api/geofence/territory', queryParameters: {'state': state});
}

/// Quiz data access. This is now an INJECTABLE INSTANCE class (it takes its Dio
/// client in the constructor) so it can be mocked in tests and swapped via
/// Riverpod — while the original `QuizAPI.list(...)` static calls keep working
/// through a shared default instance, so existing deep callers don't change.
class QuizApiClient {
  final Dio _dio;
  const QuizApiClient(this._dio);

  Future<Response> list(Map<String, String> params) =>
      _dio.get('/api/quiz', queryParameters: params);

  Future<Response> questions(String id) => _dio.get('/api/quiz/$id/questions');

  // Download the per-state quiz pack ONCE (questions are fixed for the year).
  // The app caches it on the device and reads quizzes locally thereafter.
  // rounds=1 → include picture and sequence rounds (this app can play them).
  Future<Response> pack(String state) => _dio.get(
      '/api/quiz/pack/${Uri.encodeComponent(state.isEmpty ? 'ALL' : state)}',
      queryParameters: {'rounds': '1'});

  Future<Response> submit(Map<String, dynamic> payload) =>
      _dio.post('/api/quiz/attempts', data: payload);

  // Batched version — sends many attempts in one request instead of
  // one request per quiz. Needs a matching backend endpoint (see below).
  Future<Response> submitBatch(List<Map<String, dynamic>> attempts) =>
      _dio.post('/api/quiz/attempts/batch', data: {'attempts': attempts});

  // Student's own attempt history — used in profile + ranks screens
  Future<Response> attempts(String studentId, {int page = 1, int limit = 20}) =>
      _dio.get('/api/quiz/attempts', queryParameters: {
        'student_id': studentId,
        'page': '$page',
        'limit': '$limit',
      });

  // Quiz-level analytics — used in ranks screen for class leaderboard
  Future<Response> analytics(Map<String, String> params) =>
      _dio.get('/api/quiz/analytics', queryParameters: params);
}

/// Backwards-compatible static facade over a shared default instance, so the
/// existing `QuizAPI.list(...)` call sites in the stores/services keep working
/// unchanged. New code should inject a [QuizApiClient] instead (see
/// quizApiClientProvider in learn_screen.dart).
class QuizAPI {
  static final QuizApiClient _default = QuizApiClient(api);
  static Future<Response> list(Map<String, String> params) =>
      _default.list(params);
  static Future<Response> questions(String id) => _default.questions(id);
  static Future<Response> pack(String state) => _default.pack(state);
  static Future<Response> submit(Map<String, dynamic> payload) =>
      _default.submit(payload);
  static Future<Response> submitBatch(List<Map<String, dynamic>> attempts) =>
      _default.submitBatch(attempts);
  static Future<Response> attempts(String studentId,
          {int page = 1, int limit = 20}) =>
      _default.attempts(studentId, page: page, limit: limit);
  static Future<Response> analytics(Map<String, String> params) =>
      _default.analytics(params);
}

class ConsentAPI {
  /// Current consent policy version the app presents. Bump this string
  /// whenever the consent wording changes so re-consent is triggered.
  static const String consentVersion = '1.0';

  /// Check consent status for a student. Passing student_id makes the
  /// backend return THIS student's real record (not a generic default).
  static Future<Response> status({String? studentId}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return api.get(
      '/api/consent/status',
      queryParameters: studentId != null ? {'student_id': studentId} : null,
      options: Options(headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      }),
    );
  }

  /// Grant DPDPA consents. student_id + version are REQUIRED by the backend.
  static Future<Response> grant(
    String studentId,
    List<String> consents, {
    bool verifiedParental = false,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return api.post(
      '/api/consent/grant',
      data: {
        'student_id': studentId,
        'consents': consents,
        'version': consentVersion,
        'verified_parental': verifiedParental,
      },
      options: Options(headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      }),
    );
  }

  /// Withdraw (revoke) consent. Flips granted=false on the backend —
  /// this is reversible and does NOT delete the account.
  static Future<Response> withdraw(String studentId) =>
      api.post('/api/consent/revoke', data: {'student_id': studentId});

  /// Alias kept for the onboarding consent flow that reads status.
  static Future<Response> parentalStatus(String studentId) =>
      status(studentId: studentId);
}

class AdsAPI {
  static Future<Response> list(Map<String, String> params) =>
      api.get('/api/ads', queryParameters: params);

  static Future<Response> impression(Map<String, dynamic> payload) =>
      api.post('/api/ads/impressions', data: payload);

  /// Ad frequency cap set on the dashboard: { cap, window_hours }.
  static Future<Response> frequency() => api.get('/api/ads/frequency');

  /// Ad engagement depth (Table A): view-time, completion, media type.
  /// Receiver: POST /api/ads/engagement on the dashboard.
  static Future<Response> engagement(Map<String, dynamic> payload) =>
      api.post('/api/ads/engagement', data: payload);
}

class FeedbackAPI {
  /// Submit feedback / NPS (Table A). Receiver: POST /api/feedback.
  static Future<Response> submit(Map<String, dynamic> payload) =>
      api.post('/api/feedback', data: payload);
}

class NotificationsAPI {
  static Future<Response> list({String? status}) =>
      api.get('/api/notifications',
          queryParameters: status != null ? {'status': status} : null);
}

class DashboardAPI {
  static Future<Response> summary() => api.get('/api/dashboard/summary');

  static Future<Response> overview(Map<String, String> params) =>
      api.get('/api/analytics/overview', queryParameters: params);

  static Future<Response> classroom(Map<String, String> params) =>
      api.get('/api/analytics/classroom', queryParameters: params);
}
