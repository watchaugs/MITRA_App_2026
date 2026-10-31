// ═══════════════════════════════════════════════════════
// MITRA Auth State — Riverpod Provider
// ═══════════════════════════════════════════════════════
//
// SESSION PERSISTENCE (fixes "logs out when idle / re-enter name+class+language")
//   The profile (name / class / language …) is cached ON THE DEVICE as JSON and
//   restored instantly on launch, so the app does NOT depend on a live Firestore
//   fetch to know who the student is. Firebase Auth already persists the session
//   locally on mobile; we mirror the profile next to it. On launch:
//     • if Firebase still has a session AND we have a cached profile → the user
//       is logged in immediately (no re-login, no re-entering details), and the
//       fresh profile is fetched in the background to refresh it;
//     • a failed/absent Firestore fetch no longer wipes the session — the cached
//       profile is kept.
//   The cache is cleared only on an explicit logout.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../services/telemetry_service.dart';
import '../providers/telemetry_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

const _kCachedUserKey = 'mitra_cached_user_json';

// The cached profile contains a minor's PII (name, phone, gender, state/district),
// so it is stored ENCRYPTED via flutter_secure_storage, not plaintext SharedPreferences.
const _secureProfileStore = FlutterSecureStorage();

// ── Auth State class ───────────────────────────────────
class AuthState {
  final MitraUser? user;
  final bool isLoggedIn;
  final bool isLoading;

  const AuthState({
    this.user,
    this.isLoggedIn = false,
    this.isLoading = true,
  });

  AuthState copyWith({
    MitraUser? user,
    bool? isLoggedIn,
    bool? isLoading,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ── Auth Notifier ──────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;

  AuthNotifier({required this.ref}) : super(const AuthState()) {
    // Defer all Firebase access off the construction path. Touching
    // FirebaseAuth.instance synchronously here can block when Play Services is
    // slow/unavailable, which froze the whole app before the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreCachedSession();
      _listenToFirebaseAuth();
    });
  }

  // Restore the cached profile instantly on launch so the router never bounces a
  // genuinely-logged-in student to the login/setup screens while the network
  // profile fetch is still in flight. Only trusts the cache when Firebase still
  // holds a session for the same user.
  Future<void> _restoreCachedSession() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        // No Firebase session → genuinely logged out. Stop the loading spinner
        // so the router can route to onboarding/login.
        state = const AuthState(isLoggedIn: false, isLoading: false);
        return;
      }
      final raw = await _secureProfileStore.read(key: _kCachedUserKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final cached = MitraUser.fromJson(map);
        // Only use the cache if it belongs to the signed-in Firebase user.
        if (cached.id == firebaseUser.uid) {
          state =
              state.copyWith(user: cached, isLoggedIn: true, isLoading: false);
        }
      }
    } catch (e) {
      debugPrint('⚠️  Cached-session restore failed: $e');
    }
  }

  void _listenToFirebaseAuth() {
    FirebaseAuth.instance.authStateChanges().listen((firebaseUser) async {
      if (firebaseUser != null) {
        try {
          // Refresh the profile from Firestore (app_users = the student table).
          final doc = await FirebaseFirestore.instance
              .collection('app_users')
              .doc(firebaseUser.uid)
              .get();

          if (doc.exists) {
            final data = doc.data()!;

            final realUser = MitraUser(
              id: firebaseUser.uid,
              fullName: data['full_name'] ?? data['name'] ?? 'Student',
              phone: data['phone'] ?? '',
              role: data['role'] ?? 'student',
            ).copyWith(
              classGrade: data['class_grade'],
              assignedState: data['assigned_state'],
              assignedDistrict: data['assigned_district'],
              avatarEmoji: data['avatar_emoji'] ?? '⚡',
              languagePreference: data['language_preference'] ?? 'en',
              gender: data['gender'],
              mobileBelongsTo: data['mobile_belongs_to'],
            );

            await setUser(realUser);
          } else {
            // Firebase Auth is valid but no Firestore profile. If we already have
            // a cached/restored user, KEEP them logged in (don't wipe the
            // session over a missing/slow fetch). Only a brand-new account with
            // no cache needs setup, which the router handles via classGrade.
            if (state.user == null) {
              debugPrint("⚠️  No profile for ${firebaseUser.uid}; needs setup");
              state = state.copyWith(isLoading: false);
            }
          }
        } catch (e) {
          // Network/Firestore error: do NOT log the student out. Keep whatever
          // cached user we restored; just stop the loading spinner.
          debugPrint("🚨 BACKGROUND FETCH ERROR (keeping cached session): $e");
          state = state.copyWith(isLoading: false);
        }
      } else {
        // Genuine sign-out.
        await _clearCachedUser();
        state = const AuthState(isLoggedIn: false, isLoading: false);
      }
    });
  }

  Future<void> _cacheUser(MitraUser user) async {
    try {
      await _secureProfileStore.write(
          key: _kCachedUserKey, value: jsonEncode(user.toJson()));
    } catch (e) {
      debugPrint('⚠️  Cache user failed: $e');
    }
  }

  Future<void> _clearCachedUser() async {
    try {
      await _secureProfileStore.delete(key: _kCachedUserKey);
    } catch (_) {}
  }

  Future<void> setUser(MitraUser user) async {
    state = state.copyWith(user: user, isLoggedIn: true, isLoading: false);
    await _cacheUser(user); // persist so the next launch restores instantly
    await _initializeTelemetry();
    _subscribeFCMTopics(user);
  }

  void _subscribeFCMTopics(MitraUser user) {
    final state = user.assignedState?.toLowerCase().replaceAll(' ', '_') ?? '';
    final cls = user.classGrade?.toLowerCase().replaceAll(' ', '_') ?? '';

    FirebaseMessaging.instance.subscribeToTopic('mitra_all');
    if (state.isNotEmpty) {
      FirebaseMessaging.instance.subscribeToTopic('mitra_$state');
      if (cls.isNotEmpty) {
        FirebaseMessaging.instance.subscribeToTopic('mitra_${state}_$cls');
      }
    }
    debugPrint('✅ FCM topics subscribed for $state / $cls');
  }

  Future<void> _initializeTelemetry() async {
    try {
      final outcome = await TelemetryService.create();
      if (outcome.isUsable && outcome.service != null) {
        ref.read(telemetryServiceProvider.notifier).state = outcome.service;
        final launchedAt = gAppLaunchedAt;
        if (launchedAt != null) {
          await outcome.service!.logColdStart(
            coldStartMs: DateTime.now().difference(launchedAt).inMilliseconds,
          );
        }
        debugPrint('✅ TelemetryService initialized');
      } else {
        debugPrint('⚠️  TelemetryService init failed: ${outcome.result}');
      }
    } catch (error) {
      debugPrint('❌ TelemetryService init error: $error');
    }
  }

  void updateUser(MitraUser updated) {
    state = state.copyWith(user: updated);
    unawaited(_cacheUser(updated)); // keep the cache in sync with edits
  }

  void addXP(int amount) {
    final current = state.user;
    if (current != null) {
      final next = current.copyWith(totalXp: (current.totalXp ?? 0) + amount);
      state = state.copyWith(user: next);
      unawaited(_cacheUser(next));
    }
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  Future<void> logout() async {
    final user = state.user;
    if (user != null) {
      final st = user.assignedState?.toLowerCase().replaceAll(' ', '_') ?? '';
      final cls = user.classGrade?.toLowerCase().replaceAll(' ', '_') ?? '';
      FirebaseMessaging.instance.unsubscribeFromTopic('mitra_all');
      if (st.isNotEmpty) {
        FirebaseMessaging.instance.unsubscribeFromTopic('mitra_$st');
        if (cls.isNotEmpty) {
          FirebaseMessaging.instance.unsubscribeFromTopic('mitra_${st}_$cls');
        }
      }
    }
    await _clearCachedUser();
    await FirebaseAuth.instance.signOut();
    state = const AuthState(isLoggedIn: false, isLoading: false);
  }
}

// ── Provider ───────────────────────────────────────────
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref: ref),
);

// Convenience providers
final currentUserProvider = Provider<MitraUser?>((ref) {
  return ref.watch(authProvider).user;
});

final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});
