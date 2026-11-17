// ═══════════════════════════════════════════════════════
// MITRA App Router — GoRouter
// ═══════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
// Hero HQ replaces the old Achievements page (same routes).
import 'fun/hero_hq_screen.dart';
import 'fun/card_album_screen.dart';

import '../screens/auth/splash_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/setup_screen.dart';
import '../screens/student/student_shell.dart';
import '../screens/student/home_screen.dart';
import '../screens/student/learn_screen.dart';
import '../screens/student/student_profile_screen.dart';
import '../screens/student/notifications_screen.dart';
import '../screens/teacher/teacher_shell.dart';
import '../screens/teacher/teacher_home_screen.dart';
import '../screens/teacher/students_screen.dart';
import '../screens/teacher/analytics_screen.dart';
import '../screens/teacher/assign_screen.dart';
import '../screens/teacher/teacher_profile_screen.dart';
import '../screens/quiz/quiz_screen.dart';
import '../screens/quiz/quiz_result_screen.dart';
import '../models/quiz_model.dart';
//import '../screens/ar/ar_room_screen.dart';
import '../screens/ar/ar_entry_screen.dart';
import '../stores/auth_store.dart';
import '../screens/auth/consent_screen.dart';
import '../screens/auth/location_screen.dart';
import '../screens/auth/language_screen.dart';
import '../screens/auth/greeting_screen.dart';
import 'screens/student/edit_profile_screen.dart';
import 'screens/legal/policy_screen.dart';
import 'config/legal_config.dart';
import 'screens/legal/grievance_screen.dart';
import 'models/user.dart';
import 'services/geo_state_service.dart'; // geoStateProvider
import 'services/territory_service.dart'; // TerritoryGate (home-state rule)
import 'stores/ar_pack_store.dart';
import 'screens/student/territory_lock_screen.dart';
import 'demo/demo_data.dart' show kPresentationMode;
import 'package:mitra_student/services/telemetry_service.dart';

/// Fires a screen_view telemetry event on every route push/replace, so the
/// dashboard's screen_views analytics populate. Uses the TelemetryService
/// singleton (same one main.dart uses); no-ops safely until it's ready.
class _ScreenViewObserver extends NavigatorObserver {
  final Map<Route<dynamic>, DateTime> _enteredAt = {};

  void _track(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    _enteredAt[route!] = DateTime.now();
  }

  void _flush(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name;
    final started = _enteredAt.remove(route);
    if (name == null || name.isEmpty) return;
    final secs =
        started == null ? 0 : DateTime.now().difference(started).inSeconds;
    TelemetryService.current?.logScreenView(
      screenName: name,
      durationSeconds: secs,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _flush(route);
    _track(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _flush(oldRoute);
    _track(newRoute);
  }
}

// ── Shell navigator keys ───────────────────────────────
// ✅ Exposed as public so main.dart can use rootNavigatorKey.currentContext
// for showing dialogs from the WidgetsBindingObserver hook
final rootNavigatorKey = GlobalKey<NavigatorState>();
final _studentKey = GlobalKey<NavigatorState>();
final _teacherKey = GlobalKey<NavigatorState>();

// ── Router provider ────────────────────────────────────
// Re-runs GoRouter's redirect whenever the auth state changes (login resolves,
// session restores, logout) so a genuinely logged-in student is never left on
// the wrong screen after the async auth check settles.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
    // Home-state rule: re-route when the location check result changes.
    ref.listen(geoStateProvider, (_, __) => notifyListeners());
  }
}

// Routes a locked student may still open: data rights / legal pages, the lock
// screen, and first-time setup (home state not chosen yet).
// The language → consent steps after sign-in stay reachable, so consent is
// never skipped while the location check is still running.
bool _openWhenLocked(String path, MitraUser? user) {
  if (path == '/student/locked' || path.startsWith('/legal/')) return true;
  if (path == '/consent' || path == '/language') return true;
  // First-time setup only: an existing home state can't be changed here
  // (moving state = re-register).
  final noHomeYet = (user?.assignedState ?? '').trim().isEmpty;
  return noHomeYet &&
      (path == '/setup' || path == '/setup/class' || path == '/location');
}

Map<String, String>? _parseAudios(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return (jsonDecode(raw) as Map)
        .map((k, v) => MapEntry('$k'.toLowerCase(), '$v'));
  } catch (_) {
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    observers: [_ScreenViewObserver()],
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final loggedIn = authState.isLoggedIn;
      final user = authState.user;
      final path = state.uri.path;

      if (path == '/') return null;

      // Auth still resolving (restoring the cached session / fetching the
      // profile) — do NOT bounce to login yet. The splash holds until it's done,
      // and refreshListenable re-runs this once isLoading flips to false.
      if (authState.isLoading) return null;

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

      // ── Home-state rule (territory_service.dart) ──────────────────────────
      // Outside the registered state, or not confirmed with no grace left →
      // only the lock screen (data rights + sign-out). In grace → only
      // lessons saved on this phone open.
      if (!kPresentationMode &&
          loggedIn &&
          user?.isStudent == true &&
          TerritoryGate.enforced) {
        if (!TerritoryGate.contentAllowed) {
          return _openWhenLocked(path, user) ? null : '/student/locked';
        }
        if (path == '/student/locked' &&
            state.uri.queryParameters['reason'] != 'unsaved') {
          return '/student/home';
        }
        if (TerritoryGate.status == TerritoryStatus.grace &&
            path.startsWith('/student/ar/')) {
          final id = path.substring('/student/ar/'.length);
          if (!ArPackStore.instance.hasLesson(id)) {
            return '/student/locked?reason=unsaved';
          }
        }
      }

      // ── Teacher flow hidden for launch ────────────────────────────────────
      // The teacher screens (Students/Analytics/Assign) are not wired to live
      // data yet, so we don't expose them. Anyone landing on /teacher/* is sent
      // to the student home. Remove this block to re-enable the teacher flow.
      if (path.startsWith('/teacher')) {
        return '/student/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/student/locked',
        builder: (context, state) => TerritoryLockScreen(
            reason: state.uri.queryParameters['reason'] ?? ''),
      ),
      GoRoute(
        path: '/legal/grievance',
        builder: (c, s) => const GrievanceScreen(),
      ),
      // Root-level Achievements DETAIL route (distinct from the shell TAB at
      // /student/achievements). Opened via push from Home/Settings so the back
      // button returns there instead of jumping to the Home tab.
      GoRoute(
        path: '/achievements',
        builder: (c, s) => const HeroHqScreen(standalone: true),
      ),
      // "My heroes" (Home card button) opens Hero HQ too.
      GoRoute(
        path: '/student/heroes',
        builder: (c, s) => const HeroHqScreen(standalone: true),
      ),
      GoRoute(
        path: '/student/cards',
        builder: (c, s) => const CardAlbumScreen(),
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
        path: '/language',
        builder: (context, state) => LanguageScreen(
          nextRoute: state.uri.queryParameters['next'] ?? '/consent',
          state: state.uri.queryParameters['state'],
        ),
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
              path: '/student/learn',
              builder: (c, s) => LearnScreen(
                  initialSubject: s.uri.queryParameters['subject'])),
          // ✨ Deleted the dead AR tab route
          GoRoute(
              path: '/student/achievements',
              builder: (c, s) => const HeroHqScreen()),
          GoRoute(
              path: '/student/profile',
              builder: (c, s) => const StudentProfileScreen()),
        ],
      ),

      // ── Teacher Shell ────────────────────────────────
      // edit-profile & notifications are detail screens, never tabs. As
      // TOP-LEVEL routes (outside the shell) they push onto the root navigator
      // automatically, so the back button pops to wherever they were opened
      // from, not to the Home tab. No parentNavigatorKey needed here.
      GoRoute(
        path: '/student/edit-profile',
        builder: (c, s) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/student/notifications',
        builder: (c, s) => const NotificationsScreen(),
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
        builder: (context, state) => ArEntryScreen(
          topicId: state.pathParameters['topicId'] ?? '',
          // Routes to native ARCore (ArRoomScreen) on capable phones, else the
          // on-screen 3D viewer (ArViewerScreen). /student/ar/<id>?glb=&audio=
          modelUrl: state.uri.queryParameters['glb'],
          // Non-Draco GLB for native Filament AR (Draco glb can't render there).
          nativeModelUrl: state.uri.queryParameters['nglb'],
          audioUrl: state.uri.queryParameters['audio'],
          audios: _parseAudios(state.uri.queryParameters['audios']),
          audiosAac: _parseAudios(state.uri.queryParameters['audios_aac']),
          targetsUrl: state.uri.queryParameters['mind'],
          // Page image for native ARCore image tracking (Scan page).
          targetImageUrl: state.uri.queryParameters['img'],
          videoUrl: state.uri.queryParameters['video'],
          // Page video: box on the page (JSON), sound mode, first view.
          videoRegion: state.uri.queryParameters['vregion'],
          videoSound: state.uri.queryParameters['vsound'],
          videoView: state.uri.queryParameters['vview'],
          chromaColor: state.uri.queryParameters['chroma'],
        ),
      ),
    ],
  );
});
