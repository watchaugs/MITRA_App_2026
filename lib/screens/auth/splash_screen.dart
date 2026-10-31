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
    debugPrint('🟢 SPLASH initState RAN');
    // Initialize the controller that will manage the Lottie playback speeds
    _lottieController = AnimationController(vsync: this);

    // Remove the native splash NOW — never leave it gated on the Lottie loading.
    // If the heavy animation stalls, the native splash would otherwise cover the
    // app forever (the freeze you saw).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });

    // SAFETY NET: never hang on the splash. The Lottie is heavy (~4 MB) and
    // takes a few seconds to play through, so we only force-advance if it has
    // genuinely stalled well past its normal runtime.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && !_animationDone) {
        setState(() => _animationDone = true);
        _attemptNavigation();
      }
    });

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

        // 2. Try to fetch the latest profile. A network hiccup or a missing
        //    doc must NOT force re-login/re-setup — we fall back to the cached
        //    profile that auth_store restored on launch.
        Map<String, dynamic>? data;
        try {
          final doc = await FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: '(default)',
          ).collection('app_users').doc(firebaseUser.uid).get();
          if (doc.exists) data = doc.data();
        } catch (e) {
          debugPrint('⚠️  SPLASH profile fetch failed (using cache): $e');
        }

        // Prefer the fresh doc; otherwise use the cached/restored auth user.
        final cached = ref.read(authProvider).user;
        final String role =
            (data?['role'] as String?) ?? cached?.role ?? 'student';
        final String? classGrade =
            (data?['class_grade'] as String?) ?? cached?.classGrade;

        if (data != null) {
          final consumerUser = MitraUser(
            id: firebaseUser.uid,
            fullName:
                (data['name'] ?? data['full_name'] ?? 'Student').toString(),
            phone: (data['phone'] ?? '').toString(),
            role: role,
          ).copyWith(
            classGrade: data['class_grade'],
            assignedState: data['assigned_state'],
            assignedDistrict: data['assigned_district'],
            avatarEmoji: data['avatar_emoji'] ?? '🎒',
            languagePreference: data['language_preference'] ?? 'en',
          );
          ref.read(authProvider.notifier).setUser(consumerUser);
        }

        // Decide where to go. A student with a known class is fully set up.
        if (classGrade == null || classGrade.isEmpty) {
          // No profile anywhere (brand-new account) → finish setup.
          _nextRoute = '/setup';
        } else {
          final prefs = await SharedPreferences.getInstance();
          final bool consentGiven = prefs.getBool('consentGiven') ?? false;
          final String homeRoute =
              role == 'teacher' ? '/teacher/home' : '/student/home';
          _nextRoute = consentGiven ? '/greeting?next=$homeRoute' : '/location';
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
    debugPrint('🟢 SPLASH build RAN');
    return MitraScaffold(
      //backgroundColor: const Color(0xFF181335),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Lottie.asset(
          'assets/animations/splash_animation.json',
          controller: _lottieController,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) {
            // Animation failed to load → don't block. Advance after a beat.
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && !_animationDone) {
                setState(() => _animationDone = true);
                _attemptNavigation();
              }
            });
            return const SizedBox.shrink();
          },
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
