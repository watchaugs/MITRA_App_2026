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
import 'package:isar_community/isar.dart' show Isar;
import '../fun/fun_cards.dart'; // cardTickProvider
import '../services/achievement_engine.dart'; // isarProvider
import '../services/api_service.dart'; // ConsentAPI (pending consent retry)
import '../services/progress_sync_service.dart';
import '../services/telemetry_batch_buffer.dart';
import '../services/territory_service.dart'; // TerritoryGate (home-state rule)
import '../theme/theme_provider.dart'; // sharedPreferencesProvider
import 'device_owner.dart';
import 'module_progress_store.dart'; // moduleProgressTickProvider

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
          _beginTerritory(cached); // before any screen or sync runs
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
    // Shared phones: make THIS student's progress the live set before any
    // screen shows it or any sync runs (stores/device_owner.dart).
    await _switchProgressOwner(user.id);
    _beginTerritory(user); // home-state rule, before any screen or sync runs
    state = state.copyWith(user: user, isLoggedIn: true, isLoading: false);
    await _cacheUser(user); // persist so the next launch restores instantly
    await startTelemetryIfConsented(user.id);
    unawaited(syncTopicsWithTerritory()); // topics only while allowed
    // Cloud copy of progress: every 10 days (and first merge if never done).
    try {
      unawaited(ref.read(progressSyncServiceProvider).pushIfDue(user.id));
    } catch (_) {/* Isar unavailable → no progress sync */}
  }

  // Students: enforce the home-state rule from the last saved check until
  // today's check finishes (territory_service.dart). Others: no rule.
  void _beginTerritory(MitraUser user) {
    if (user.isStudent) {
      TerritoryGate.begin(ref.read(sharedPreferencesProvider), user.id,
          user.assignedState ?? '');
    } else {
      TerritoryGate.end();
    }
  }

  /// Called whenever the location check finishes. Back in the home state →
  /// run the cloud progress merge/push that was held (e.g. at sign-in, before
  /// the check had finished, the merge was skipped).
  void onTerritoryResolved() {
    final user = state.user;
    if (user == null || !user.isStudent || !TerritoryGate.syncAllowed) return;
    unawaited(_sendPendingConsent(user.id));
    try {
      unawaited(ref.read(progressSyncServiceProvider).pushIfDue(user.id));
    } catch (_) {/* Isar unavailable → no progress sync */}
  }

  // A consent given offline is on the phone but not on the server yet; send it.
  Future<void> _sendPendingConsent(String uid) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString('consentPendingGrant');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map;
      if ('${m['uid']}' != uid) return;
      final consents =
          ((m['consents'] as List?) ?? const []).map((e) => '$e').toList();
      await ConsentAPI.grant(uid, consents, verifiedParental: m['vp'] == true);
      await prefs.remove('consentPendingGrant');
    } catch (_) {/* still offline / server error → next check */}
  }

  /// FCM topics follow the home-state rule: unsubscribed while the student
  /// is locked out (nothing shows up outside the home state), back on return.
  Future<void> syncTopicsWithTerritory() async {
    final user = state.user;
    if (user == null) return;
    if (!user.isStudent || TerritoryGate.contentAllowed) {
      _subscribeFCMTopics(user);
    } else {
      await _unsubscribeFCMTopics(user);
    }
  }

  Future<void> _unsubscribeFCMTopics(MitraUser user) async {
    final st = user.assignedState?.toLowerCase().replaceAll(' ', '_') ?? '';
    final cls = user.classGrade?.toLowerCase().replaceAll(' ', '_') ?? '';
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('mitra_all');
      if (st.isNotEmpty) {
        await FirebaseMessaging.instance.unsubscribeFromTopic('mitra_$st');
        if (cls.isNotEmpty) {
          await FirebaseMessaging.instance
              .unsubscribeFromTopic('mitra_${st}_$cls');
        }
      }
    } catch (e) {
      debugPrint('⚠️ FCM unsubscribe: $e');
    }
  }

  Future<void> _switchProgressOwner(String uid) async {
    try {
      Isar? isar;
      try {
        isar = ref.read(isarProvider);
      } catch (_) {/* Isar failed to open → prefs only */}
      final changed = await DeviceOwner.switchTo(uid,
          prefs: ref.read(sharedPreferencesProvider), isar: isar);
      if (changed) {
        // Screens that read progress from prefs rebuild with this student's.
        ref.read(moduleProgressTickProvider.notifier).state++;
        ref.read(cardTickProvider.notifier).state++;
      }
    } catch (e) {
      debugPrint('⚠️ Progress owner switch failed: $e');
    }
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

  /// Learning analytics start only after this student's consent is saved
  /// (DPDP). Called at sign-in and again by the consent screen.
  Future<void> startTelemetryIfConsented(String? uid) async {
    if (uid == null || uid.isEmpty) return;
    final cur = ref.read(telemetryServiceProvider);
    if (cur != null && cur.context.studentId == uid) return; // already on
    if (cur != null) {
      // Another student's service (shared phone): never tag this one's events.
      TelemetryService.current = null;
      ref.read(telemetryServiceProvider.notifier).state = null;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    final consented = prefs.getBool('consentGiven') ?? false;
    if (!consented || (prefs.getBool('consentWithdrawn') ?? false)) return;
    await _initializeTelemetry();
  }

  /// Consent given (consent screen) or given again (Profile → re-grant):
  /// analytics may run for this student.
  Future<void> onConsentGranted(String? uid) async {
    await ref.read(sharedPreferencesProvider).remove('consentWithdrawn');
    await startTelemetryIfConsented(uid);
  }

  /// Consent withdrawn (Profile → data rights): stop analytics now, and keep
  /// them off on later sign-ins until consent is given again (DPDP).
  Future<void> onConsentWithdrawn() async {
    await ref.read(sharedPreferencesProvider).setBool('consentWithdrawn', true);
    TelemetryService.current = null;
    ref.read(telemetryServiceProvider.notifier).state = null;
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
      // While this student is still signed in: send their queued telemetry and
      // save their progress to the cloud. Best-effort and capped at a few
      // seconds; offline, Firestore keeps the writes for their next sign-in.
      try {
        await TelemetryBatchBuffer.instance
            .flushNow()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      try {
        await ref
            .read(progressSyncServiceProvider)
            .push(user.id)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
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
    // Drop backend JWTs so a shared device never calls the API as the previous student.
    try {
      await _secureProfileStore.delete(key: 'mitra_access_token');
      await _secureProfileStore.delete(key: 'mitra_refresh_token');
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    // Stop tagging events with the student who just left.
    TelemetryService.current = null;
    TerritoryGate.end();
    ref.read(telemetryServiceProvider.notifier).state = null;
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
