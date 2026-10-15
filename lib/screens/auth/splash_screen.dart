// ═══════════════════════════════════════════════════════
// SCREEN S-01: Splash — Pure Full-Screen Lottie
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

// import '../../services/api_service.dart'; // Unused: kept for reference
import '../../stores/auth_store.dart';
import '../../models/user.dart';
import '../../widgets/mitra_scaffold.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

// 🚨 Added TickerProviderStateMixin to drive the custom Lottie controller
class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _lottieController;

  String? _nextRoute; // Holds the destination route once backend replies
  bool _animationDone =
      false; // Tracks if the animation reached its final frame

  @override
  void initState() {
    super.initState();
    // Initialize the controller that will manage the Lottie playback speeds
    _lottieController = AnimationController(vsync: this);

    // Kick off the background authentication verification instantly
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    debugPrint("🚨 SPLASH: Checking native Firebase Auth...");

    try {
      // 1. Ask Firebase natively if someone is logged in (100x more reliable than local storage)
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser != null) {
        debugPrint(
            "🚨 SPLASH: User found! Fetching full profile from database...");

        // 2. Fetch their complete profile so GoRouter's Rule 3 doesn't block them
        final doc = await FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: '(default)',
        ).collection('app_users').doc(firebaseUser.uid).get();

        if (doc.exists) {
          final data = doc.data()!;

          // 3. Rebuild the user with all their data (especially class_grade!)
          final consumerUser = MitraUser(
            id: firebaseUser.uid,
            fullName: data['name'] ?? 'Student',
            phone: data['phone'] ?? '',
            role: data['role'] ?? 'student',
          ).copyWith(
            classGrade: data['class_grade'],
            assignedState: data['assigned_state'],
            assignedDistrict: data['assigned_district'],
            avatarEmoji: data['avatar_emoji'] ?? '🎒',
            languagePreference: data['language_preference'] ?? 'en',
          );

          ref.read(authProvider.notifier).setUser(consumerUser);

          // 4. Check consent — gate home screen behind it (DPDPA)
          final prefs = await SharedPreferences.getInstance();
          final bool consentGiven = prefs.getBool('consentGiven') ?? false;
          final String homeRoute =
              data['role'] == 'teacher' ? '/teacher/home' : '/student/home';
          // Route to the personalized animated greeting instead of straight to dashboard
          _nextRoute = consentGiven
              ? '/greeting?next=$homeRoute'
              : '/consent?next=$homeRoute';
        } else {
          // They authenticated via OTP but never finished the setup screen
          _nextRoute = '/setup';
        }
      } else {
        // No one is logged in. Check SharedPreferences to see if we skip Onboarding.
        final prefs = await SharedPreferences.getInstance();
        final bool hasCompletedOnboarding =
            prefs.getBool('onboardingComplete') ?? false;

        _nextRoute = hasCompletedOnboarding ? '/login' : '/onboarding';
      }
    } catch (e) {
      debugPrint("🚨 SPLASH ERROR: $e");
      ref.read(authProvider.notifier).setLoading(false);
      _nextRoute = '/login';
    }

    _attemptNavigation();
  }

  /// Evaluates if both conditions are met before switching screens
  void _attemptNavigation() {
    if (_animationDone && _nextRoute != null) {
      debugPrint(
          "🚨 SPLASH: Animation complete & route ready. Navigating to $_nextRoute");
      if (mounted) {
        context.go(_nextRoute!);
      }
    }
  }

  @override
  void dispose() {
    _lottieController
        .dispose(); // Always clean up controllers to prevent memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MitraScaffold(
      //backgroundColor: const Color(0xFF181335),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Lottie.asset(
          'assets/animations/splash_animation.json',
          controller: _lottieController,
          fit: BoxFit.cover,
          onLoaded: (composition) {
            // ✨ THE MAGIC FIX: Remove the native splash screen right NOW!
            // The Lottie file is loaded in memory, so there will be zero blank flash.
            FlutterNativeSplash.remove();

            // 1. Set the controller's duration to match the JSON file perfectly
            _lottieController.duration = composition.duration;

            // 2. Play the animation forward exactly once
            _lottieController.forward().then((_) {
              setState(() => _animationDone = true);
              // 3. Trigger navigation now that the final frame has been reached
              _attemptNavigation();
            });
          },
        ),
      ),
    );
  }
}
