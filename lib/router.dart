// ═══════════════════════════════════════════════════════
// MITRA App Router — GoRouter
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mitra_student/screens/student/achievements_screen.dart';

import '../screens/auth/splash_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/setup_screen.dart';
import '../screens/student/student_shell.dart';
import '../screens/student/home_screen.dart';
import '../screens/student/learn_screen.dart';
import '../screens/student/student_profile_screen.dart';
import '../screens/teacher/teacher_shell.dart';
import '../screens/teacher/teacher_home_screen.dart';
import '../screens/teacher/students_screen.dart';
import '../screens/teacher/analytics_screen.dart';
import '../screens/teacher/assign_screen.dart';
import '../screens/teacher/teacher_profile_screen.dart';
import '../screens/quiz/quiz_screen.dart';
import '../screens/quiz/quiz_result_screen.dart';
import '../models/quiz_model.dart';
import '../screens/ar/ar_viewer_screen.dart';
import '../stores/auth_store.dart';
import '../screens/auth/consent_screen.dart';
import '../screens/auth/location_screen.dart';
import '../screens/auth/greeting_screen.dart';
import 'screens/student/edit_profile_screen.dart';
import 'screens/legal/policy_screen.dart';
import 'config/legal_config.dart';
import 'screens/legal/grievance_screen.dart';

// ── Shell navigator keys ───────────────────────────────
// ✅ Exposed as public so main.dart can use rootNavigatorKey.currentContext
// for showing dialogs from the WidgetsBindingObserver hook
final rootNavigatorKey = GlobalKey<NavigatorState>();
final _studentKey = GlobalKey<NavigatorState>();
final _teacherKey = GlobalKey<NavigatorState>();

// ── Router provider ────────────────────────────────────
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final loggedIn = authState.isLoggedIn;
      final user = authState.user;
      final path = state.uri.path;

      if (path == '/') return null;

      if (!loggedIn &&
          path != '/onboarding' &&
          path != '/login' &&
          path != '/consent') {
        return '/onboarding';
      }

      if (loggedIn &&
          user?.isStudent == true &&
          user?.classGrade == null &&
          path != '/setup' &&
          path != '/consent') {
        return '/setup';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/legal/grievance',
        builder: (c, s) => const GrievanceScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),

      GoRoute(
        path: '/consent',
        builder: (context, state) {
          final next = state.uri.queryParameters['next'] ?? '/student/home';
          return ConsentScreen(nextRoute: next);
        },
      ),
      GoRoute(
        path: '/location',
        builder: (context, state) => const LocationScreen(),
      ),
      GoRoute(
        path: '/setup/class',
        builder: (context, state) => const SetupScreen(classOnly: true),
      ),

      GoRoute(
        path: '/greeting',
        builder: (context, state) {
          final next = state.uri.queryParameters['next'] ?? '/student/home';
          return GreetingScreen(nextRoute: next);
        },
      ),

      // ── Student Shell ────────────────────────────────
      // Back button handled centrally in main.dart via didPopRoute
      ShellRoute(
        navigatorKey: _studentKey,
        builder: (context, state, child) => StudentShell(child: child),
        routes: [
          GoRoute(path: '/student/home', builder: (c, s) => const HomeScreen()),
          GoRoute(
              path: '/student/learn', builder: (c, s) => const LearnScreen()),
          // ✨ Deleted the dead AR tab route
          GoRoute(
              path: '/student/achievements',
              builder: (c, s) => const AchievementsScreen()),
          GoRoute(
              path: '/student/profile',
              builder: (c, s) => const StudentProfileScreen()),
          GoRoute(
              path: '/student/edit-profile',
              builder: (c, s) => const EditProfileScreen()),
        ],
      ),

      // ── Teacher Shell ────────────────────────────────
      ShellRoute(
        navigatorKey: _teacherKey,
        builder: (context, state, child) => TeacherShell(child: child),
        routes: [
          GoRoute(
              path: '/teacher/home',
              builder: (c, s) => const TeacherHomeScreen()),
          GoRoute(
              path: '/teacher/students',
              builder: (c, s) => const StudentsScreen()),
          GoRoute(
              path: '/teacher/analytics',
              builder: (c, s) => const AnalyticsScreen()),
          GoRoute(
              path: '/teacher/assign', builder: (c, s) => const AssignScreen()),
          GoRoute(
              path: '/teacher/profile',
              builder: (c, s) => const TeacherProfileScreen()),
        ],
      ),

      // ── Quiz (full screen modal) ─────────────────────
      GoRoute(
        path:
            '/quiz-result', // ✨ FIX: Changed path to completely avoid :quizId collision
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return QuizResultScreen(
            score: extra['score'] as int? ?? 0,
            total: extra['total'] as int? ?? 0,
            xpEarned: extra['xpEarned'] as int? ?? 0,
            quizId: extra['quizId'] as String? ?? '',
            questions: extra['questions'] as List<QuizQuestion>? ?? [],
            studentAnswers: extra['studentAnswers'] as List<int?>? ?? [],
          );
        },
      ),
      GoRoute(
        path:
            '/quiz/:quizId', // ✨ FIX: Dynamic route placed beneath the static result route
        builder: (context, state) => QuizScreen(
          quizId: state.pathParameters['quizId'] ?? '',
        ),
      ),

      GoRoute(
        path: '/legal/privacy',
        builder: (c, s) => const PolicyScreen(
          title: 'Privacy Policy',
          body: LegalConfig.privacyPolicyText,
          externalUrl: LegalConfig.privacyPolicyUrl,
        ),
      ),
      GoRoute(
        path: '/legal/terms',
        builder: (c, s) => const PolicyScreen(
          title: 'Terms of Use',
          body: LegalConfig.termsText,
          externalUrl: LegalConfig.termsUrl,
        ),
      ),

      // ── AR Viewer (full screen modal) ────────────────
      GoRoute(
        // ✨ Updated the path to match exactly what the Learn Screen is asking for!
        path: '/student/ar/:topicId',
        builder: (context, state) => ArViewerScreen(
          topicId: state.pathParameters['topicId'] ?? '',
          // Optional real model URL, e.g. /student/ar/cell-division?glb=<url>.
          // Absent for current callers, so the viewer uses its sample model.
          modelUrl: state.uri.queryParameters['glb'],
        ),
      ),
    ],
  );
});
