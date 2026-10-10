import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';

import 'services/quotes_service.dart';
import 'services/brain_spark_service.dart';
import 'theme/theme_provider.dart';
import 'constants/colors.dart';
import 'router.dart';
import 'services/api_service.dart';
import 'services/quiz_offline_service.dart';
import 'services/telemetry_batch_buffer.dart';
import 'services/telemetry_service.dart';
import 'providers/telemetry_provider.dart';
import 'back_button_dispatcher.dart';
import 'firebase_options.dart';

// ✨ GAMIFICATION & ISAR IMPORTS
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'models/achievement_models.dart';
import 'services/achievement_engine.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('🔔 Background FCM: ${message.messageId}');
}

Future<void> main() async {
  gAppLaunchedAt = DateTime.now();
  runZonedGuarded(() async {
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    // Flutter framework errors → crash telemetry (best-effort).
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      TelemetryService.current?.logCrash(
        errorType: 'flutter',
        message: details.exceptionAsString(),
        stackSummary: details.stack?.toString(),
        fatal: false,
      );
    };

    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('⚠️ .env: $e');
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
      }
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('⚠️ Firebase: $e');
    }

    try {
      ApiService.instance.init();
    } catch (e) {
      debugPrint('⚠️ API: $e');
    }

    final prefs = await SharedPreferences.getInstance();

    try {
      await Hive.initFlutter();
    } catch (e) {
      debugPrint('⚠️ Hive: $e');
    }

    // ✨ INITIALIZE THE ISAR XP DATABASE ✨
    late Isar isar;
    try {
      final dir = await getApplicationDocumentsDirectory();
      isar = await Isar.open(
        [StudentProfileSchema, TopicProgressSchema],
        directory: dir.path,
      );
    } catch (e) {
      debugPrint('⚠️ Isar Gamification DB Error: $e');
    }

    try {
      TelemetryBatchBuffer.instance.startScheduler();
    } catch (e) {
      debugPrint('⚠️ Telemetry: $e');
    }

    await QuotesService.instance.init();
    await BrainSparkService.instance.init();

    runApp(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // ✨ Pass the active DB into the Riverpod UI stream
        isarProvider.overrideWithValue(isar),
      ],
      child: const MitraApp(),
    ));
  }, (error, stack) {
    // Uncaught async / zone errors → crash telemetry (best-effort).
    TelemetryService.current?.logCrash(
      errorType: 'zone',
      message: error.toString(),
      stackSummary: stack.toString(),
      fatal: true,
    );
  });
}

class MitraApp extends ConsumerStatefulWidget {
  const MitraApp({super.key});
  @override
  ConsumerState<MitraApp> createState() => _MitraAppState();
}

class _MitraAppState extends ConsumerState<MitraApp>
    with WidgetsBindingObserver {
  MitraBackButtonHandler? _backHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupFCM();
  }

  @override
  void didHaveMemoryPressure() {
    // OS reported low memory → device-health telemetry (Table A, "RAM").
    TelemetryService.current?.logDeviceHealth(lowMemory: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register handler after router is available via ref
    if (_backHandler == null) {
      final router = ref.read(routerProvider);
      _backHandler = MitraBackButtonHandler(
        router: router,
        ref: ref,
        rootNavKey: rootNavigatorKey,
      );
      _backHandler!.register();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backHandler?.unregister();
    super.dispose();
  }

  void _setupFCM() {
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('🔔 FCM foreground: ${msg.notification?.title}');
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleDeepLink);
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) _handleDeepLink(msg);
    });
  }

  void _handleDeepLink(RemoteMessage msg) {
    final type = msg.data['deep_link_type'] as String?;
    final id = msg.data['deep_link_id'] as String?;
    if (type == null || id == null || id.isEmpty) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    if (type == 'quiz') GoRouter.of(ctx).go('/quiz/$id');
    if (type == 'ar_topic') GoRouter.of(ctx).go('/ar/$id');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final activeTheme = ref.watch(themeProvider);
    ref.watch(quizSyncProvider);

    return MaterialApp.router(
      title: 'MITRA',
      debugShowCheckedModeBanner: false,
      color: MitraColors.saffron,
      theme: ThemeHelper.getThemeData(activeTheme),
      routerConfig: router,

      // ✨ FIX: THIS STOPS EVERY SCREEN FROM HIDING BEHIND THE STATUS BAR ✨
      builder: (context, child) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            bottom: false, // Keeps the bottom nav bar edge-to-edge
            child: child!,
          ),
        );
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('as'),
        Locale('bn'),
        Locale('brx'),
        Locale('doi'),
        Locale('gu'),
        Locale('hi'),
        Locale('kn'),
        Locale('ks'),
        Locale('kok'),
        Locale('mai'),
        Locale('ml'),
        Locale('mni'),
        Locale('mr'),
        Locale('ne'),
        Locale('or'),
        Locale('pa'),
        Locale('sa'),
        Locale('sat'),
        Locale('sd'),
        Locale('ta'),
        Locale('te'),
        Locale('ur'),
        Locale('en'),
      ],
    );
  }
}
