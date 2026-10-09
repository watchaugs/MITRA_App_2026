// ═══════════════════════════════════════════════════════
// MITRA API Service — Dio client with auth + auto-refresh
// Mirrors services/api.ts from Expo project
// ═══════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:isar/isar.dart'; // ✨ Added for Piggyback Sync
import '../models/achievement_models.dart'; // ✨ Added for Piggyback Sync
import 'package:go_router/go_router.dart';
import '../router.dart';
import 'dart:convert';
import 'dart:io';

const _storage = FlutterSecureStorage();

// ── Dio singleton ──────────────────────────────────────
class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  static ApiService get instance => _instance;

  late final Dio _dio;

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
        'Origin': 'https://watchaugs-mitra.web.app',
      },
    ));

    // ── Request interceptor: attach JWT & Compress Payload ──────────────
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'mitra_access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        // ✨ BANDWIDTH FIX: Gzip outgoing batches
        // Only compress POST/PUT requests with payloads larger than 1KB
        if ((options.method == 'POST' || options.method == 'PUT') &&
            options.data != null) {
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

          // Try silent token refresh
          try {
            final refreshToken =
                await _storage.read(key: 'mitra_refresh_token');

            // ✨ PERMANENT FIX 1: Don't ping the server if the refresh token is completely gone
            if (refreshToken == null || refreshToken.isEmpty) {
              throw Exception('Refresh token missing or expired');
            }

            // 🚨 FIX 2: Added the CORS Disguise to the refresh mechanism as well
            final refreshDio = Dio(BaseOptions(headers: {
              'Content-Type': 'application/json',
              'Origin': 'https://watchaugs-mitra.web.app',
            }));

            final res = await refreshDio.post(
              '$baseUrl/api/auth/refresh',
              // 🚨 FIX 3: Changed 'refreshToken' to 'refresh_token' to match backend requirements
              data: {'refresh_token': refreshToken},
            );

            final newToken = res.data?['access_token'] as String?;
            if (newToken == null) {
              throw Exception('Invalid token received');
            }
            await _storage.write(key: 'mitra_access_token', value: newToken);

            // Retry original request with new token
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newToken';
            final retryRes = await _dio.fetch(opts);
            handler.resolve(retryRes);
            return;
          } catch (_) {
            // ✨ PERMANENT FIX 2: Graceful Session Expiration (Auto-Logout)
            // Wipe the dead tokens so the app knows we are unauthenticated
            await _storage.delete(key: 'mitra_access_token');
            await _storage.delete(key: 'mitra_refresh_token');

            // Force the app back to the login screen using your global router key!
            if (rootNavigatorKey.currentContext != null) {
              rootNavigatorKey.currentContext!.go('/login');
            }

            handler.reject(error);
            return;
          }
        }
        handler.reject(error);
      },
    ));
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

  static Future<Response> verifyOTP(String phone, String otp, String role) =>
      api.post('/api/auth/verify-otp',
          data: {'phone': phone, 'otp': otp, 'role': role});

  static Future<Response> me() => api.get('/api/auth/me');

  static Future<Response> logout() => api.post('/api/auth/logout');

  static Future<Response> refresh(String refreshToken) =>
      api.post('/api/auth/refresh', data: {
        'refresh_token': refreshToken // Matches the backend requirement
      });
}

class UsersAPI {
  static Future<Response> me() => api.get('/api/users/me');

  static Future<Response> update(String id, Map<String, dynamic> data) =>
      api.put('/api/users/$id', data: data);
}

class CurriculumAPI {
  static Future<Response> tree() => api.get('/api/curriculum/tree');

  static Future<Response> arTopics(Map<String, String> params) =>
      api.get('/api/curriculum/ar-topics', queryParameters: params);

  static Future<Response> hierarchy(String stateCode) =>
      api.get('/api/curriculum/hierarchy/$stateCode');
}

class ArAPI {
  static Future<Response> assets(Map<String, String> params) =>
      api.get('/api/ar/assets', queryParameters: params);

  static Future<Response> asset(String id) => api.get('/api/ar/assets/$id');

  static Future<Response> links(String nodeId) =>
      api.get('/api/ar/links/$nodeId');
}

class QuizAPI {
  static Future<Response> list(Map<String, String> params) =>
      api.get('/api/quiz', queryParameters: params);

  static Future<Response> questions(String id) =>
      api.get('/api/quiz/$id/questions');

  static Future<Response> submit(Map<String, dynamic> payload) =>
      api.post('/api/quiz/attempts', data: payload);

  // Batched version — sends many attempts in one request instead of
  // one request per quiz. Needs a matching backend endpoint (see below).
  static Future<Response> submitBatch(List<Map<String, dynamic>> attempts) =>
      api.post('/api/quiz/attempts/batch', data: {'attempts': attempts});

  // Student's own attempt history — used in profile + ranks screens
  static Future<Response> attempts(String studentId,
          {int page = 1, int limit = 20}) =>
      api.get('/api/quiz/attempts', queryParameters: {
        'student_id': studentId,
        'page': '$page',
        'limit': '$limit',
      });

  // Quiz-level analytics — used in ranks screen for class leaderboard
  static Future<Response> analytics(Map<String, String> params) =>
      api.get('/api/quiz/analytics', queryParameters: params);
}

class TelemetryAPI {
  /// Unauthenticated PostgreSQL path — fires even before login
  static Future<Response> send(Map<String, dynamic> payload) =>
      api.post('/api/analytics/telemetry', data: payload);

  /// Primary telemetry path — writes to Firestore `telemetry_sessions`.
  /// The Dio interceptor adds the Bearer token automatically.
  static Future<Response> sync(Map<String, dynamic> payload) =>
      api.post('/api/analytics/telemetry', data: payload);

  // ✨ 3. The Piggyback Payload Generator
  // Your background offline-sync service can call this to inject the
  // student's current XP and Badge state into the master JSON payload
  // before calling TelemetryAPI.sync() above.
  static Future<Map<String, dynamic>> buildPiggybackSyncPayload(
      Isar isar) async {
    // ✨ FIX: Explicitly target the collections by type to bypass pluralization errors
    final profileCollection = isar.collection<StudentProfile>();
    final topicCollection = isar.collection<TopicProgress>();

    final profile =
        await profileCollection.where().findFirst() ?? StudentProfile();
    final allTopics = await topicCollection.where().findAll();

    return {
      "achievement_sync": {
        "total_xp":
            profile.totalXp.toInt(), // ✨ FIX: Enforce safe integer types
        "current_tier": profile.currentTier,
        "unlocked_badges": profile.unlockedBadges,
      },
      "completed_summary_ledger": allTopics
          .map((t) => {
                "topic_id": t.topicId,
                "ar_completed": t.hasViewedAr,
                "quiz_completed": t.hasPassedQuiz,
                "synergy_achieved": t.synergyApplied
              })
          .toList()
    };
  }
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
    List<String> consents,
  ) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return api.post(
      '/api/consent/grant',
      data: {
        'student_id': studentId,
        'consents': consents,
        'version': consentVersion,
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
