import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'widgets/in_app_notification_card.dart';
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
      // FirebaseMessaging.onBackgroundMessage(
      //     _firebaseMessagingBackgroundHandler);
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

    try {
      await QuotesService.instance.init();
    } catch (e) {
      debugPrint('⚠️ QuotesService: $e');
    }
    try {
      await BrainSparkService.instance.init();
    } catch (e) {
      debugPrint('⚠️ BrainSpark: $e');
    }

    debugPrint('🚦 MAIN: reached runApp');
    runApp(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // ✨ Pass the active DB into the Riverpod UI stream
        isarProvider.overrideWithValue(isar),
      ],
      child: const MitraApp(),
    ));
    // Belt-and-suspenders: lift the native splash shortly after runApp, no
    // matter what the splash screen does. Prevents a stuck static splash.
    Future.delayed(const Duration(milliseconds: 600), () {
      FlutterNativeSplash.remove();
    });
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

  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotif.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        // Tapping a shown notification deep-links the same way FCM does.
        final data = resp.payload;
        if (data != null && data.contains('|')) {
          final parts = data.split('|');
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && parts.length == 2 && parts[1].isNotEmpty) {
            if (parts[0] == 'quiz') GoRouter.of(ctx).go('/quiz/${parts[1]}');
            if (parts[0] == 'ar_topic') {
              GoRouter.of(ctx).go('/student/ar/${parts[1]}');
            }
          }
        }
      },
    );
    // The channel the dashboard targets (channelId: 'mitra_content'). The
    // accent colour per-message is applied in _showLocalNotification.
    const channel = AndroidNotificationChannel(
      'mitra_content',
      'MITRA Announcements',
      description: 'Lessons, quizzes and announcements from MITRA',
      importance: Importance.high,
    );
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _setupFCM() {
    // Fully non-blocking + guarded: notification init must never affect launch
    // or the UI, especially on devices where Google Play Services / FCM is
    // unavailable (SERVICE_NOT_AVAILABLE).
    Future(() async {
      try {
        await _initLocalNotifications();
      } catch (e) {
        debugPrint('⚠️ local notif init: $e');
      }
    });
    try {
      FirebaseMessaging.onMessage.listen((msg) {
        // Foreground: show BOTH the in-app card (rich, styled) and a tray
        // notification, so the student sees it whether or not they're looking.
        _showInAppCard(msg);
        _showLocalNotification(msg);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleDeepLink);
      FirebaseMessaging.instance.getInitialMessage().then((msg) {
        if (msg != null) _handleDeepLink(msg);
      });
    } catch (e) {
      debugPrint('⚠️ FCM setup: $e');
    }
  }

  // Tray notification with the dashboard's accent colour + banner image.
  Future<void> _showLocalNotification(RemoteMessage msg) async {
    final n = msg.notification;
    if (n == null) return;
    final data = msg.data;
    final colorHex = (data['color'] ?? '').toString();
    final imageUrl = (data['image_url'] ?? '').toString();
    Color? accent;
    if (colorHex.startsWith('#') && colorHex.length == 7) {
      accent = Color(int.parse('FF${colorHex.substring(1)}', radix: 16));
    }
    final payload =
        '${data['deep_link_type'] ?? ''}|${data['deep_link_id'] ?? ''}';

    StyleInformation? style;
    if (imageUrl.isNotEmpty) {
      try {
        // BigPicture needs a local/asset path; for a URL we fall back to
        // BigText so the notification still expands nicely. (Downloading the
        // image for BigPicture can be added later via a file provider.)
        style = BigTextStyleInformation(n.body ?? '');
      } catch (_) {}
    }

    final android = AndroidNotificationDetails(
      'mitra_content',
      'MITRA Announcements',
      channelDescription: 'Lessons, quizzes and announcements from MITRA',
      importance: Importance.high,
      priority: Priority.high,
      color: accent,
      colorized: accent != null,
      styleInformation: style,
    );
    await _localNotif.show(
      msg.hashCode,
      n.title,
      n.body,
      NotificationDetails(
          android: android, iOS: const DarwinNotificationDetails()),
      payload: payload,
    );
  }

  // Rich in-app card (full design control) when the app is open.
  void _showInAppCard(RemoteMessage msg) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    showInAppNotificationCard(ctx, msg);
  }

  void _handleDeepLink(RemoteMessage msg) {
    final type = msg.data['deep_link_type'] as String?;
    final id = msg.data['deep_link_id'] as String?;
    if (type == null || id == null || id.isEmpty) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    if (type == 'quiz') GoRouter.of(ctx).go('/quiz/$id');
    if (type == 'ar_topic') GoRouter.of(ctx).go('/student/ar/$id');
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
