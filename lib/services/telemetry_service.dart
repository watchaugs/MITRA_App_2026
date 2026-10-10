import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'device_probe.dart';
import 'student_context.dart';
import 'telemetry_dead_letter_queue.dart';
import 'telemetry_batch_buffer.dart';
import 'telemetry_enums.dart';

/// Result of [TelemetryService.initialise], so callers can react to
/// partial failures instead of the original silently proceeding with a
/// half-populated static context.
enum TelemetryInitResult {
  success,
  notLoggedIn,
  profileLoadFailed,
  devicePropeFailed,
}

class TelemetryInitOutcome {
  final TelemetryInitResult result;
  final TelemetryService? service;
  final Object? error;

  const TelemetryInitOutcome(this.result, {this.service, this.error});

  bool get isUsable => service != null;
}

/// MITRA Telemetry Service — Government-Grade Analytics
///
/// Collects dimensions across REF Sheet, device/connectivity, DPDPA
/// compliance, and behavioral signals, attached to every event for
/// rollup to RAW_* sheets.
///
/// Key differences from the original static-singleton implementation:
///  - Instance-based: built via [TelemetryService.create], not a global
///    mutable singleton. Each session/test gets its own isolated context.
///  - Consent is enforced, not just recorded: see
///    [StudentContext.hasValidConsent] / [StudentContext.demographicsIfConsented].
///    DPDPA-sensitive fields are omitted from outgoing events entirely
///    (not sent as null) when consent isn't affirmatively granted.
///  - All previously-stringly-typed fields are enums (telemetry_enums.dart),
///    so a typo can't silently corrupt analytics data.
///  - Failed writes go to a local dead-letter queue instead of being
///    logged to stdout and discarded.
class TelemetryService {
  final FirebaseFirestore _db;
  final TelemetryDeadLetterQueue _deadLetterQueue;
  StudentContext _context;

  /// The most-recently created service, so top-level code outside the widget
  /// tree (e.g. the crash handler in main.dart) can emit telemetry. Set in
  /// [create]; may be null before the first successful init.
  static TelemetryService? current;

  TelemetryService._({
    required StudentContext context,
    required FirebaseFirestore db,
    required TelemetryDeadLetterQueue deadLetterQueue,
  })  : _context = context,
        _db = db,
        _deadLetterQueue = deadLetterQueue;

  /// Current context, exposed read-only. Use [updateConnectivity] /
  /// [updateConsent] to change it rather than reaching in and mutating.
  StudentContext get context => _context;

  /// Build a TelemetryService for the currently logged-in user. Loads the
  /// student profile from Firestore and probes the device. Returns a
  /// [TelemetryInitOutcome] describing what happened rather than silently
  /// degrading — callers decide whether e.g. `profileLoadFailed` should
  /// block telemetry entirely or proceed with reduced context.
  static Future<TelemetryInitOutcome> create({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    DeviceProbe? deviceProbe,
    TelemetryDeadLetterQueue? deadLetterQueue,
  }) async {
    final firestore = db ?? FirebaseFirestore.instance;
    final uid = (auth ?? FirebaseAuth.instance).currentUser?.uid;

    if (uid == null) {
      return const TelemetryInitOutcome(TelemetryInitResult.notLoggedIn);
    }

    final probe = await (deviceProbe ?? DeviceProbe()).probe();

    Map<String, dynamic>? profileDoc;
    Object? profileError;
    try {
      final doc = await firestore.collection('students').doc(uid).get();
      profileDoc = doc.data();
    } catch (e) {
      profileError = e;
    }

    if (profileDoc == null) {
      // Either the read threw, or the doc genuinely doesn't exist yet.
      // Either way we don't have enough to safely emit DPDPA-relevant
      // events, so surface this distinctly rather than guessing.
      return TelemetryInitOutcome(
        TelemetryInitResult.profileLoadFailed,
        error: profileError,
      );
    }

    final context = StudentContext.fromFirestore(
      studentId: uid,
      doc: profileDoc,
      deviceModel: probe.deviceModel,
      osVersion: probe.osVersion,
      isArCapable: probe.isArCapable,
    );

    final service = TelemetryService._(
      context: context,
      db: firestore,
      deadLetterQueue: deadLetterQueue ?? TelemetryDeadLetterQueue(),
    );
    current = service;

    return TelemetryInitOutcome(TelemetryInitResult.success, service: service);
  }

  // ─── CONTEXT UPDATES (replace direct field mutation) ──────────────────

  void updateConnectivity(ConnectivityType type) {
    _context = _context.copyWith(connectivityType: type);
  }

  /// Record a consent decision. This updates the in-memory context AND
  /// logs the compliance event itself — callers should call this instead
  /// of mutating consent fields directly, so the two can never drift.
  Future<void> updateConsent({
    required String consentType, // "parental" / "data_retention" / "analytics"
    required ConsentStatus status,
    required String consentFormVersion,
    String? denialReason,
  }) async {
    final now = DateTime.now();
    _context = _context.copyWith(
      parentalConsentStatus:
          consentType == 'parental' ? status : _context.parentalConsentStatus,
      dataRetentionConsent: consentType == 'data_retention'
          ? status
          : _context.dataRetentionConsent,
      consentTimestamp: now,
      consentVersion: consentFormVersion,
    );

    await _write('compliance_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'consent_${status.wireValue.toLowerCase()}',
      'consent_type': consentType,
      'action': status.wireValue,
      'consent_form_version': consentFormVersion,
      'denial_reason': denialReason,
    });
  }

  /// Update the in-memory demographic context (gender / mobile ownership)
  /// captured at profile setup, so the *current* session's events carry it
  /// immediately rather than only after the next TelemetryService.create()
  /// reload. Mirrors [updateConnectivity] / [updateConsent].
  void updateDemographics({String? gender, MobileOwnership? mobileOwnership}) {
    _context = _context.copyWith(
      gender: gender,
      mobileOwnership: mobileOwnership,
    );
  }

  /// Records that the student completed (or updated) the profile-setup
  /// form, including the demographic fields collected there. Respects the
  /// same consent gate as every other event — [StudentContext.toBaseEventJson]
  /// only includes gender/mobile_ownership/etc. when consent is affirmative,
  /// so this call is always safe to make regardless of consent state.
  Future<void> logProfileSetup({
    required bool genderProvided,
    required bool mobileOwnershipProvided,
  }) async {
    await _write('profile_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'profile_setup_complete',
      'gender_provided': genderProvided,
      'mobile_ownership_provided': mobileOwnershipProvided,
    });
  }

  // ─── SESSION EVENTS ─────────────────────────────────────────────────────

  Future<void> logSessionStart(
      {required ConnectivityType connectivityType}) async {
    updateConnectivity(connectivityType);
    await _write('sessions', {
      ..._context.toBaseEventJson(),
      'event_type': 'session_start',
    });
  }

  Future<void> logSessionEnd({
    required int durationSeconds,
    required bool wasOffline,
    required ConnectivityType connectivityType,
  }) async {
    updateConnectivity(connectivityType);
    await _write('sessions', {
      ..._context.toBaseEventJson(),
      'event_type': 'session_end',
      'duration_seconds': durationSeconds,
      'was_offline': wasOffline,
    });
  }

  // ─── AR MODULE EVENTS ───────────────────────────────────────────────────

  Future<void> logArStart({
    required String arId,
    required String topicId,
    required String moduleTitle,
    required double preModuleScore,
  }) async {
    await _write('ar_views', {
      ..._context.toBaseEventJson(),
      'event_type': 'ar_start',
      'ar_id': arId,
      'topic_id': topicId,
      'module_title': moduleTitle,
      'pre_module_score': preModuleScore,
      'ar_init_success': true,
    });
  }

  Future<void> logArEnd({
    required String arId,
    required String topicId,
    required String moduleTitle,
    required int durationSeconds,
    required bool completed,
    required bool isReplay,
    required double preModuleScore,
    required double postModuleScore,
    int? tapCount,
    int? rotateCount,
    int? zoomCount,
    double? batteryDrainPercent,
  }) async {
    await _write('ar_views', {
      ..._context.toBaseEventJson(),
      'event_type': 'ar_end',
      'ar_id': arId,
      'topic_id': topicId,
      'module_title': moduleTitle,
      'duration_seconds': durationSeconds,
      'completed': completed,
      'is_replay': isReplay,
      'pre_module_score': preModuleScore,
      'post_module_score': postModuleScore,
      'score_uplift': postModuleScore - preModuleScore,
      'tap_count': tapCount,
      'rotate_count': rotateCount,
      'zoom_count': zoomCount,
      'battery_drain_pct': batteryDrainPercent,
    });
  }

  Future<void> logArInitFailure(
      {required String arId, required String reason}) async {
    await _write('ar_views', {
      ..._context.toBaseEventJson(),
      'event_type': 'ar_init_failure',
      'ar_id': arId,
      'failure_reason': reason,
    });
  }

  // ─── QUIZ EVENTS ────────────────────────────────────────────────────────

  Future<void> logQuizSubmit({
    required String quizId,
    required String quizTitle,
    required int correctAnswers,
    required int totalQuestions,
    required int durationSeconds,
    required bool completed,
    List<Map<String, dynamic>>? mcqResponses,
  }) async {
    final scorePct = totalQuestions > 0 ? correctAnswers / totalQuestions : 0.0;
    await _write('quiz_attempts', {
      ..._context.toBaseEventJson(),
      'event_type': 'quiz_submit',
      'quiz_id': quizId,
      'quiz_title': quizTitle,
      'correct_answers': correctAnswers,
      'total_questions': totalQuestions,
      'score_pct': scorePct,
      'passed': scorePct >= 0.6,
      'duration_seconds': durationSeconds,
      'completed': completed,
      // Per-question breakdown → BigQuery mcq_responses column
      if (mcqResponses != null && mcqResponses.isNotEmpty)
        'mcq_responses': mcqResponses,
    });

    // Also write a session record for BigQuery pipeline
    await _write('sessions', {
      ..._context.toBaseEventJson(),
      'event_type': 'quiz_session',
      'quiz_id': quizId,
      'subject': _context.subject,
      'session_minutes': (durationSeconds / 60).ceil(),
      'time_spent_seconds': durationSeconds,
      'completion_percent': completed
          ? 100
          : totalQuestions > 0
              ? (correctAnswers / totalQuestions * 100).round()
              : 0,
      'interactions_count': totalQuestions,
      'has_ar_content': false,
      'offline_session': false,
      'sync_version': 'v1',
      if (mcqResponses != null && mcqResponses.isNotEmpty)
        'mcq_responses': mcqResponses,
    });
  }

  // ─── SCREEN NAVIGATION EVENTS ───────────────────────────────────────────

  Future<void> logScreenView({
    required String screenName,
    required int durationSeconds,
    bool exitedWithRageTap = false,
  }) async {
    await _write('screen_views', {
      ..._context.toBaseEventJson(),
      'event_type': 'screen_view',
      'screen_name': screenName,
      'duration_seconds': durationSeconds,
      'exited_rage_tap': exitedWithRageTap,
    });
  }

  // ─── NOTIFICATION EVENTS ────────────────────────────────────────────────

  Future<void> logNotificationEvent({
    required String notificationType,
    required String action,
    String? deepLinkTarget,
  }) async {
    await _write('notification_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'notification_$action',
      'notification_type': notificationType,
      'action': action,
      'deep_link_target': deepLinkTarget,
    });
  }

  // ─── OFFLINE SYNC EVENTS ────────────────────────────────────────────────

  Future<void> logOfflineSync({
    required int cachedEventCount,
    required bool syncSuccess,
    int? syncDurationSeconds,
  }) async {
    await _write('sync_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'offline_sync',
      'cached_event_count': cachedEventCount,
      'sync_success': syncSuccess,
      'sync_duration_seconds': syncDurationSeconds,
    });
  }

  // ─── ACCESSIBILITY & LANGUAGE EVENTS ────────────────────────────────────

  Future<void> logAccessibilityToggle({
    required String feature,
    required bool enabled,
  }) async {
    await _write('accessibility_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'accessibility_toggle',
      'feature': feature,
      'enabled': enabled,
    });
  }

  Future<void> logLanguageSwitch({
    required String fromLanguage,
    required String toLanguage,
  }) async {
    await _write('language_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'language_switch',
      'from_language': fromLanguage,
      'to_language': toLanguage,
    });
  }

  Future<void> logAccessibilityRequest({
    required String
        accommodationType, // "TTS" / "HighContrast" / "LargerFont" / "2D_Fallback"
    required bool approved,
    String? denialReason,
  }) async {
    await _write('accessibility_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'accessibility_request',
      'accommodation_type': accommodationType,
      'approved': approved,
      'denial_reason': denialReason,
    });
  }

  // ─── DEVICE HEALTH / CRASH / COLD-START (Table A) ───────────────────────

  Future<void> logColdStart({required int coldStartMs}) async {
    await _write('device_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'cold_start',
      'cold_start_ms': coldStartMs,
    });
  }

  Future<void> logCrash({
    required String errorType, // 'flutter' | 'zone'
    required String message,
    String? stackSummary,
    bool fatal = false,
  }) async {
    await _write('device_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'crash',
      'error_type': errorType,
      'crash_message':
          message.length > 500 ? message.substring(0, 500) : message,
      if (stackSummary != null)
        'crash_stack': stackSummary.length > 2000
            ? stackSummary.substring(0, 2000)
            : stackSummary,
      'is_fatal': fatal,
    });
  }

  Future<void> logDeviceHealth({
    int? ramTotalMb,
    int? ramFreeMb,
    bool lowMemory = false,
  }) async {
    await _write('device_events', {
      ..._context.toBaseEventJson(),
      'event_type': 'device_health',
      if (ramTotalMb != null) 'ram_total_mb': ramTotalMb,
      if (ramFreeMb != null) 'ram_free_mb': ramFreeMb,
      'low_memory': lowMemory,
    });
  }

  // ─── DEAD-LETTER QUEUE MAINTENANCE ──────────────────────────────────────

  /// Attempt to resend any previously-failed writes. Call this
  /// periodically (app foreground, connectivity-restored callback, etc).
  /// Entries that fail again are left queued with their attempt count
  /// bumped; callers may want to give up on entries past some attempt
  /// threshold (left to caller policy rather than hardcoded here).
  Future<void> retryDeadLetterQueue({int maxAttemptsBeforeDrop = 10}) async {
    final pending = await _deadLetterQueue.pending();
    for (final entry in pending.entries) {
      final key = entry.key;
      final dl = entry.value;
      try {
        await _db
            .collection('telemetry_sync')
            .doc(_context.studentId)
            .collection(dl.collection)
            .add(dl.data);
        await _deadLetterQueue.remove(key);
      } catch (e) {
        if (dl.attempts + 1 >= maxAttemptsBeforeDrop) {
          await _deadLetterQueue.remove(key); // give up; avoid unbounded retry
        } else {
          await _deadLetterQueue.recordAttempt(key, dl);
        }
      }
    }
  }

  Future<int> deadLetterQueueLength() => _deadLetterQueue.length();

  // ─── INTERNAL ────────────────────────────────────────────────────────────

  Future<void> _write(String collection, Map<String, dynamic> data) async {
    // Buffered locally and flushed in batches (telemetry_batch_buffer.dart)
    // instead of writing to Firestore immediately on every single event.
    await TelemetryBatchBuffer.instance.buffer(
      collection: collection,
      studentId: _context.studentId,
      data: data,
    );
  }
}
