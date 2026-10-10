// ═══════════════════════════════════════════════════════
// MITRA Auth State — Riverpod Provider
// ═══════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../services/telemetry_service.dart';
import '../providers/telemetry_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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
  final Ref ref; // ✨ ADD THIS

  AuthNotifier({required this.ref}) : super(const AuthState()) {
    _listenToFirebaseAuth();
  }

  void _listenToFirebaseAuth() {
    FirebaseAuth.instance.authStateChanges().listen((firebaseUser) async {
      if (firebaseUser != null) {
        try {
          // ✨ Fetch the real profile data from Firestore automatically
          final doc = await FirebaseFirestore.instance
              .collection('users')
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
            // Firebase Auth succeeded but no Firestore profile yet
            // (e.g. brand-new signup, doc not yet created). Surface this
            // rather than silently doing nothing.
            debugPrint("⚠️  No user profile found for ${firebaseUser.uid}");
          }
        } catch (e) {
          debugPrint("🚨 BACKGROUND FETCH ERROR: $e");
        }
      } else {
        // User logged out
        state = const AuthState(isLoggedIn: false, isLoading: false);
      }
    });
  }

  Future<void> setUser(MitraUser user) async {
    state = state.copyWith(user: user, isLoggedIn: true, isLoading: false);
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
        // Cold-start time: process launch → telemetry ready (Table A).
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
  }

  void addXP(int amount) {
    final current = state.user;
    if (current != null) {
      state = state.copyWith(
        user: current.copyWith(totalXp: (current.totalXp ?? 0) + amount),
      );
    }
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  Future<void> logout() async {
    // Unsubscribe FCM topics before sign-out
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
