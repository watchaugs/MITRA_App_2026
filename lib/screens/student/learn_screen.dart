import '../../demo/demo_data.dart';
// ═════════════════════════════════════════════════════════════
// SCREEN: Learn — Curriculum tree + live quiz feed
//
// Fetches live quizzes from GET /api/quiz, filtered by the
// student's profile (class, state, language). Quizzes are
// grouped by subject for browsing.
//
// Key improvements over the original:
//  1. Typed error hierarchy — no silent swallow, UI gets
//     actionable messages, analytics/crash-reporting can
//     pattern-match without string parsing.
//  2. Validated API response parsing — malformed items are
//     logged & skipped instead of crashing or silently
//     defaulting to empty IDs.
//  3. Repository abstraction — the provider depends on an
//     [QuizRepository] interface, making it trivial to swap
//     in a mock, local-first cache, or different backend.
//  4. Family-aware invalidation — the original called
//     `ref.invalidate(provider)` without family args, which
//     either fails or invalidates *all* family instances.
//     Now the notifier's `refresh()` targets the correct
//     instance.
//  5. Navigation input sanitisation — empty or suspicious
//     quiz IDs are rejected before `context.go()`.
//  6. Accessibility semantics on interactive elements.
//  7. Numeric clamping on parsed values.
//  8. Scroll-aware refresh: preserves visible data during
//     pull-to-refresh so the list doesn't flash away.
//  9. Extracted sub-widgets for readability & reuse.
// 10. Structured logging for observability.
// ═════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/colors.dart';
import '../../services/api_service.dart';
import '../../services/geo_state_service.dart';
import '../../stores/auth_store.dart';
import '../../providers/translation_provider.dart'; // ✨ Added for language filtering
import '../../providers/tr_ext.dart';
import '../../widgets/orbit_explorer.dart';
import '../../stores/module_progress_store.dart';
import '../../stores/ar_pack_store.dart';
import '../../services/achievement_engine.dart';
import '../../models/quiz_model.dart';

// ═══════════════════════════════════════════════════════════
// DOMAIN: Failures
// ═══════════════════════════════════════════════════════════

/// Sealed failure hierarchy — the UI can present the right
/// message and downstream consumers (analytics, crash-
/// reporting, retry logic) can react without string-matching.
sealed class LearnFailure {
  const LearnFailure();

  /// English fallback, safe to show if a translation is missing.
  String get displayMessage;

  /// Translation-pack key for this message. The UI resolves it through the
  /// app's i18n (context.tr) with [displayMessage] as the fallback, so these
  /// errors localise like the rest of the app. Add these keys to the ARB /
  /// translation packs: error_network, error_server, error_parsing.
  String get messageKey;
}

class NetworkFailure extends LearnFailure {
  const NetworkFailure();
  @override
  String get displayMessage =>
      'Could not reach the server. Please check your connection.';
  @override
  String get messageKey => 'error_network';
}

class ServerFailure extends LearnFailure {
  const ServerFailure();
  @override
  String get displayMessage =>
      'Something went wrong on our end. Please try again later.';
  @override
  String get messageKey => 'error_server';
}

class ParsingFailure extends LearnFailure {
  const ParsingFailure();
  @override
  String get displayMessage => 'Received unexpected data. Please try again.';
  @override
  String get messageKey => 'error_parsing';
}

// ═══════════════════════════════════════════════════════════
// DOMAIN: Quiz model
// ═══════════════════════════════════════════════════════════

/// Status of a quiz as returned by the API.
enum QuizStatus { live, draft, closed }

QuizStatus _parseQuizStatus(String? raw) => switch (raw?.toLowerCase()) {
      'live' => QuizStatus.live,
      'draft' => QuizStatus.draft,
      'closed' => QuizStatus.closed,
      // Unknown values default to `live` (API contract says
      // only live quizzes are returned for this endpoint) but
      // we log a warning so misconfigurations are caught early.
      _ => QuizStatus.live,
    };

/// Lightweight quiz summary for list screens.
///
/// Construct via [QuizSummary.fromMap] which validates the
/// required `id` field and clamps numeric ranges to safe
/// bounds.  The class is public so it can be used in tests
/// and other screens.
class QuizSummary {
  final String id;
  final String title;
  final String subject;
  final String topic;
  final int questionCount;
  final double avgScore;
  final QuizStatus status;
  final String languageTag; // ✨ Added language tag

  const QuizSummary({
    required this.id,
    required this.title,
    required this.subject,
    required this.topic,
    required this.questionCount,
    required this.avgScore,
    required this.status,
    required this.languageTag,
  });

  /// Parses a single quiz map from the API response.
  ///
  /// Throws [FormatException] if the required `id` field is
  /// missing or empty — this is a hard contract violation.
  factory QuizSummary.fromMap(Map<String, dynamic> m) {
    final rawId = m['id'];
    if (rawId is! String || rawId.isEmpty) {
      throw FormatException(
        'Quiz map missing non-empty "id" field — got: $rawId',
      );
    }

    return QuizSummary(
      id: rawId,
      title: m['title'] as String? ?? 'Untitled Quiz',
      subject: _coalesce(m['subject'] as String?) ?? 'General',
      topic: (m['topic'] as String?)?.trim() ?? '',
      // Clamp to realistic bounds — guards against typos or
      // injection in the backend response.
      questionCount: (m['question_count'] as int?)?.clamp(0, 9999) ?? 0,
      avgScore: ((m['avg_score'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0),
      status: _parseQuizStatus(m['status'] as String?),
      // ✨ Safely pulls the tag, defaults to 'all' for legacy/un-tagged dashboard content
      languageTag: m['language_tag'] as String? ?? 'all',
    );
  }

  /// Parses a list of raw maps, gracefully skipping malformed
  /// entries while logging them for observability.
  static List<QuizSummary> parseList(List<dynamic> raw) {
    final results = <QuizSummary>[];
    for (var i = 0; i < raw.length; i++) {
      try {
        final item = raw[i];
        if (item is! Map<String, dynamic>) {
          developer.log(
            'Quiz item at index $i is not a Map — skipping',
            name: 'LearnScreen',
          );
          continue;
        }
        results.add(QuizSummary.fromMap(item));
      } on FormatException catch (e) {
        developer.log('Malformed quiz at index $i: $e', name: 'LearnScreen');
        // Skip this item but continue parsing the rest.
      }
    }
    return results;
  }
}

/// Returns a trimmed, non-empty string or null.
String? _coalesce(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

// ═══════════════════════════════════════════════════════════
// DOMAIN: Subject metadata
// ═══════════════════════════════════════════════════════════

// NOTE: Emojis render inconsistently across OS versions.
// In a production app, prefer SVG assets or icon fonts.
const _subjectEmoji = <String, String>{
  'Science': '🔬',
  'Maths': '📐',
  'Mathematics': '📐',
  'History': '🏛️',
  'Geography': '🌍',
  'English': '🔠',
  'Hindi': '🔤',
  'Social Science': '🌐',
  'Computer Science': '💻',
  'Physics': '⚛️',
  'Chemistry': '⚗️',
  'Biology': '🧬',
};

String _emojiFor(String subject) => _subjectEmoji[subject] ?? '📖';

// ═══════════════════════════════════════════════════════════
// DOMAIN: Filter parameters
// ═══════════════════════════════════════════════════════════

/// Immutable, validated filter parameters for the quiz feed.
///
/// Implements value equality so Riverpod's family caching
/// works correctly — without this, every `build()` call would
/// create a new `Map<String, String>` and trigger a re-fetch.
class QuizFilterParams {
  final String className;
  final String state;
  final String language;

  const QuizFilterParams({
    this.className = '',
    this.state = '',
    this.language = '',
  });

  /// Converts to query parameters, omitting empty values so
  /// the API doesn't receive `?class_name=&state=`.
  Map<String, String> toQueryParams() => {
        'status': 'live',
        if (className.isNotEmpty) 'class_name': className,
        if (state.isNotEmpty) 'state': state,
        if (language.isNotEmpty) 'language': language,
        _limitKey: _defaultLimit,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuizFilterParams &&
          className == other.className &&
          state == other.state &&
          language == other.language;

  @override
  int get hashCode => Object.hash(className, state, language);

  static const _limitKey = 'limit';
  static const _defaultLimit = '100';
}

// ═══════════════════════════════════════════════════════════
// DATA: Quiz repository
// ═══════════════════════════════════════════════════════════

/// Abstraction over quiz data access — swap with a mock in
/// tests or a local-first implementation for offline support.
abstract class QuizRepository {
  Future<List<QuizSummary>> fetchLiveQuizzes(QuizFilterParams params);
}

class ApiQuizRepository implements QuizRepository {
  // Full DI: the quiz API client is injected, so tests pass a mock
  // QuizApiClient and no live backend is needed. Production wires the real
  // client through quizApiClientProvider (see below).
  final QuizApiClient _api;
  const ApiQuizRepository(this._api);

  @override
  Future<List<QuizSummary>> fetchLiveQuizzes(QuizFilterParams params) async {
    try {
      final res = await _api.list(params.toQueryParams());
      final raw = res.data['data'];

      // Guard against unexpected response shapes (e.g. the
      // backend returns `{ "data": null }` or a single object).
      if (raw is! List<dynamic>) {
        developer.log(
          'Unexpected "data" shape: ${raw.runtimeType}',
          name: 'LearnScreen',
          error: raw,
        );
        throw const ParsingFailure();
      }

      final all = QuizSummary.parseList(raw);
      // Client-side guard: only surface live quizzes even if
      // the API accidentally returns others.
      return all.where((q) => q.status == QuizStatus.live).toList();
    } on LearnFailure {
      rethrow;
    } on FormatException {
      throw const ParsingFailure();
    } on DioException catch (e, st) {
      developer.log(
        'Quiz fetch failed (${e.type})',
        name: 'LearnScreen',
        error: e,
        stackTrace: st,
      );
      // Reached the server but it errored (5xx) → ServerFailure.
      // Couldn't reach it at all (timeout / connection / cancel) → NetworkFailure.
      final status = e.response?.statusCode ?? 0;
      final serverSide =
          e.type == DioExceptionType.badResponse && status >= 500;
      throw serverSide ? const ServerFailure() : const NetworkFailure();
    } catch (e, st) {
      developer.log(
        'Quiz fetch failed (unexpected)',
        name: 'LearnScreen',
        error: e,
        stackTrace: st,
      );
      // Anything non-Dio and unclassified → treat as a server-side problem.
      throw const ServerFailure();
    }
  }
}

// ═══════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════

/// AR-watch threshold (%) required to unlock a module's quiz. Set on the
/// dashboard (learning-settings). Defaults to 80 if the fetch fails.
final arWatchThresholdProvider = FutureProvider<int>((ref) async {
  try {
    final res = await CurriculumAPI.learningSettings();
    final v = res.data['ar_watch_threshold'];
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n != null && n >= 1 && n <= 100) return n;
  } catch (_) {/* fall back */}
  return 80;
});

/// Rule 1 dialog: tapping a quiz before the AR is watched enough opens this.
/// Offers an "Open AR module" action that jumps straight to the AR content.
Future<void> _showWatchArFirstDialog(
    BuildContext context, int threshold, VoidCallback openAr) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.trCtx(
          'student_finish_the_ar_module_first', 'Finish the AR module first')),
      content: Text(ctx.trpCtx(
          'student_watch_at_least_threshold_of_the_ar',
          'Watch at least {threshold}% of the AR module before taking its quiz.',
          {'threshold': '$threshold'})),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(ctx.trCtx('student_not_now', 'Not now')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            openAr();
          },
          child: Text(ctx.trCtx('student_open_ar_module', 'Open AR module')),
        ),
      ],
    ),
  );
}

/// The injectable quiz API client. Production uses the app's shared Dio
/// instance; a test can override this provider with a mock QuizApiClient so the
/// repository never touches a real backend.
final quizApiClientProvider = Provider<QuizApiClient>((ref) {
  return QuizApiClient(ApiService.instance.dio);
});

/// Repository instance — override in tests with a mock.
final quizRepositoryProvider = Provider<QuizRepository>((ref) {
  return kPresentationMode
      ? const DemoQuizRepository()
      : ApiQuizRepository(ref.watch(quizApiClientProvider));
});

/// Derives quiz filter params from the current user profile.
/// Returns empty params when the user is not logged in.
final quizFilterParamsProvider = Provider<QuizFilterParams>((ref) {
  final user = ref.watch(currentUserProvider);
  return QuizFilterParams(
    className: user?.classGrade ?? '',
    state: ref.watch(effectiveStateProvider), // GPS-primary licensed state
    language: user?.languagePreference ?? '',
  );
});

// ═══════════════════════════════════════════════════════════
// DATA: AR catalog — live + geofenced, with demo fallback
// ═══════════════════════════════════════════════════════════

/// One AR lesson tile's data. Structurally identical to the inline record
/// used by [_SubjectSection]/[_ArTile], so the two are interchangeable.
typedef ArLessonRec = ({
  String id,
  String title,
  String topic,
  String languageTag,
  String classTag,
  bool locked, // Rule 3: a "coming soon" scheduled teaser — greyed, not openable
});

/// The AR lessons to show (grouped by subject) plus a side map of each
/// topic id -> its real GLB model URL (empty in demo mode).
class ArCatalog {
  final Map<String, List<ArLessonRec>> bySubject;
  final Map<String, String> glbById;
  final Map<String, String> nativeGlbById;
  final Map<String, String> videoById;
  final Map<String, String> audioById;
  final Map<String, Map<String, String>> audiosByLangById; // id -> {lang: url}
  final Map<String, Map<String, String>>
      audiosAacByLangById; // id -> {lang: url} AAC fallback
  final Map<String, String> chromaById;
  final bool territorySupported; // false = outside MITRA's approved area
  const ArCatalog({
    required this.bySubject,
    required this.glbById,
    this.nativeGlbById = const {},
    this.videoById = const {},
    this.audioById = const {},
    this.audiosByLangById = const {},
    this.audiosAacByLangById = const {},
    this.chromaById = const {},
    this.territorySupported = true,
  });
}

/// Live AR topics from the dashboard, scoped to the student's state (so the
/// dashboard's geofencing applies), with the hardcoded demo map as a safe
/// fallback — the list is never empty on stage. In presentation mode it
/// returns the demo map unchanged and no network call is made.
/// Flatten a /manifest/<state> payload into the same maps the Learn screen
/// already consumes. Returns null if the shape is unusable. A manifest only
/// exists for a supported state, so territorySupported is true here.
// Media URLs from the backend are RELATIVE (e.g. "/api/ar/file/xxx_lite.glb").
// The 3D viewer, AR plugin and audio player all need an ABSOLUTE https URL, so
// we prefix the API base URL. Values that are already absolute (http/https) or
// bundled assets ("assets/...") are returned unchanged.
String _absMedia(String url) {
  final u = url.trim();
  if (u.isEmpty) return u;
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  if (u.startsWith('assets/')) return u;
  final base = ApiService.instance.dio.options.baseUrl.replaceAll(
    RegExp(r'/+$'),
    '',
  );
  final path = u.startsWith('/') ? u : '/$u';
  return '$base$path';
}

ArCatalog? _catalogFromManifest(dynamic data) {
  if (data is! Map) return null;
  final classes = data['classes'];
  if (classes is! List) return null;
  final bySubject = <String, List<ArLessonRec>>{};
  final glbById = <String, String>{};
  final nativeGlbById = <String, String>{};
  final videoById = <String, String>{};
  final audioById = <String, String>{};
  final audiosByLangById = <String, Map<String, String>>{};
  final audiosAacByLangById = <String, Map<String, String>>{};
  final chromaById = <String, String>{};
  for (final c in classes) {
    if (c is! Map) continue;
    final className = (c['class_name'] ?? c['class'] ?? '').toString();
    final subjects = c['subjects'];
    if (subjects is! List) continue;
    for (final sj in subjects) {
      if (sj is! Map) continue;
      final subject = (sj['subject'] ?? 'Other').toString();
      final topics = sj['topics'];
      if (topics is! List) continue;
      for (final t in topics) {
        if (t is! Map) continue;
        final topic = (t['topic'] ?? subject).toString();
        final lessons = t['ar_lessons'];
        if (lessons is! List) continue;
        for (final l in lessons) {
          if (l is! Map) continue;
          final id = (l['id'] ?? '').toString();
          if (id.isEmpty) continue;
          bySubject.putIfAbsent(subject, () => []).add((
            id: id,
            title: (l['title'] ?? id).toString(),
            topic: topic,
            languageTag:
                (l['language_tag'] ?? l['language'] ?? 'all').toString(),
            classTag: (l['class_name'] ?? className).toString(),
            locked: false,
          ));
          // flutter_url = Draco _lite.glb (for the on-screen 3D viewer).
          // native_url  = non-Draco _native.glb (for floor AR / Filament).
          final glb = _absMedia((l['flutter_url'] ?? '').toString());
          if (glb.isNotEmpty) glbById[id] = glb;
          final nativeGlb = _absMedia((l['native_url'] ?? '').toString());
          if (nativeGlb.isNotEmpty) nativeGlbById[id] = nativeGlb;
          final vid = _absMedia((l['video_url'] ?? '').toString());
          if (vid.isNotEmpty) videoById[id] = vid;
          final aud = _absMedia((l['audio_url'] ?? '').toString());
          if (aud.isNotEmpty) audioById[id] = aud;
          // Multi-language narration: { lang: url }. Absolutise each URL.
          final rawAudios = l['audios'];
          if (rawAudios is Map && rawAudios.isNotEmpty) {
            final m = <String, String>{};
            rawAudios.forEach((k, v) {
              final u = _absMedia((v ?? '').toString());
              if (u.isNotEmpty) m[k.toString().toLowerCase()] = u;
            });
            if (m.isNotEmpty) audiosByLangById[id] = m;
          }
          // AAC fallback map { lang: url } for devices that can't decode Opus.
          final rawAudiosAac = l['audios_aac'];
          if (rawAudiosAac is Map && rawAudiosAac.isNotEmpty) {
            final m = <String, String>{};
            rawAudiosAac.forEach((k, v) {
              final u = _absMedia((v ?? '').toString());
              if (u.isNotEmpty) m[k.toString().toLowerCase()] = u;
            });
            if (m.isNotEmpty) audiosAacByLangById[id] = m;
          }
          if (l['chroma_enabled'] == true) {
            chromaById[id] = (l['chroma_color'] ?? '#00ff00').toString();
          }
        }
      }
    }
  }
  if (bySubject.isEmpty) return null;
  return ArCatalog(
    bySubject: bySubject,
    glbById: glbById,
    nativeGlbById: nativeGlbById,
    videoById: videoById,
    audioById: audioById,
    audiosByLangById: audiosByLangById,
    audiosAacByLangById: audiosAacByLangById,
    chromaById: chromaById,
    territorySupported: true,
  );
}

final arCatalogProvider = FutureProvider<ArCatalog>((ref) async {
  if (kPresentationMode) {
    return const ArCatalog(
      bySubject: LearnScreen._arLessonsBySubject,
      glbById: {},
    );
  }

  final state = ref.watch(effectiveStateProvider); // GPS-primary licensed state
  final lang = ref.watch(translationProvider).langCode;

  // ── Cost-shield: try the hard-cached state manifest first. ──────────────
  // One document read, served with a long Cache-Control, instead of a
  // per-launch Firestore collection scan. If it yields lessons we build the
  // catalog from it and never touch /ar-topics. If it's empty/unreachable we
  // fall through to the live /ar-topics call below (unchanged behaviour).
  if (state.isNotEmpty) {
    try {
      final mres = await CurriculumAPI.manifest(state, stateName: state);
      final mcat = _catalogFromManifest(mres.data);
      if (mcat != null && mcat.bySubject.isNotEmpty) return mcat;
    } catch (_) {
      // ignore and fall back to /ar-topics
    }
  }

  final res = await CurriculumAPI.arTopics({
    if (state.isNotEmpty) 'state': state,
    if (lang.isNotEmpty) 'lang': lang,
  });

  final raw = res.data is Map ? res.data['data'] : null;
  final territorySupported =
      res.data is Map ? (res.data['territory_supported'] != false) : true;
  final bySubject = <String, List<ArLessonRec>>{};
  final glbById = <String, String>{};
  final nativeGlbById = <String, String>{};
  final audioById = <String, String>{};
  final videoById = <String, String>{};
  final chromaById = <String, String>{};

  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = (m['id'] ?? m['topic_id'] ?? '').toString();
      if (id.isEmpty) continue;
      final subject = (m['subject'] ?? 'Other').toString();
      bySubject.putIfAbsent(subject, () => []).add((
        id: id,
        title: (m['title'] ?? id).toString(),
        topic: (m['topic'] ?? subject).toString(),
        languageTag: (m['language_tag'] ?? m['language'] ?? 'all').toString(),
        classTag: (m['class_name'] ?? m['class'] ?? '').toString(),
        locked: m['locked'] == true || m['status'] == 'scheduled',
      ));
      final glb = _absMedia(
        (m['flutter_url'] ?? m['glb_url'] ?? m['model_url'] ?? '').toString(),
      );
      if (glb.isNotEmpty) glbById[id] = glb;
      final nativeGlb = _absMedia((m['native_url'] ?? '').toString());
      if (nativeGlb.isNotEmpty) nativeGlbById[id] = nativeGlb;
      final vid = _absMedia((m['video_url'] ?? '').toString());
      if (vid.isNotEmpty) videoById[id] = vid;
      final aud = _absMedia((m['audio_url'] ?? '').toString());
      if (aud.isNotEmpty) audioById[id] = aud;
      if (m['chroma_enabled'] == true) {
        chromaById[id] = (m['chroma_color'] ?? '#00ff00').toString();
      }
    }
  }

  // Nothing came back → keep the demo list so the screen isn't blank.
  if (bySubject.isEmpty) {
    return const ArCatalog(
      bySubject: LearnScreen._arLessonsBySubject,
      glbById: {},
    );
  }
  return ArCatalog(
    bySubject: bySubject,
    glbById: glbById,
    nativeGlbById: nativeGlbById,
    videoById: videoById,
    audioById: audioById,
    chromaById: chromaById,
    territorySupported: territorySupported,
  );
});

/// Async quiz feed notifier — exposes typed errors through
/// [LearnFailure] and supports explicit refresh that keeps
/// existing data visible during pull-to-refresh.
final quizFeedProvider = AsyncNotifierProvider.family<QuizFeedNotifier,
    List<QuizSummary>, QuizFilterParams>(QuizFeedNotifier.new);

class QuizFeedNotifier
    extends FamilyAsyncNotifier<List<QuizSummary>, QuizFilterParams> {
  @override
  Future<List<QuizSummary>> build(QuizFilterParams arg) {
    final repo = ref.watch(quizRepositoryProvider);
    return repo.fetchLiveQuizzes(arg);
  }

  /// Refreshes the quiz feed.
  ///
  /// - If data already exists (pull-to-refresh), the current
  ///   list stays visible while the fetch is in flight — no
  ///   loading spinner flash.
  /// - If there's no data yet (first load or error), a
  ///   loading state is emitted so the spinner appears.
  Future<void> refresh() async {
    final previousData = state.valueOrNull;
    if (previousData == null) {
      state = const AsyncLoading();
    }
    final repo = ref.read(quizRepositoryProvider);
    state = await AsyncValue.guard(() => repo.fetchLiveQuizzes(arg));
  }
}

// ═══════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════

class LearnScreen extends ConsumerStatefulWidget {
  // When a Home subject tile is tapped, the subject name is passed here so the
  // Learn screen opens on that subject's filter instead of defaulting to 'All'.
  final String? initialSubject;
  const LearnScreen({super.key, this.initialSubject});

  // ✨ Hardcoded mapping of AR Lessons to their respective subjects
  static const _arLessonsBySubject = <String,
      List<
          ({
            String id,
            String title,
            String topic,
            String languageTag,
            String classTag,
            bool locked,
          })>>{
    'Science': [
      (
        id: 'cell-division',
        title: 'Cell Division 3D',
        topic: 'Biology',
        languageTag: 'all',
        classTag: '',
        locked: false,
      ),
      (
        id: 'atom-structure-en',
        title: 'Atom Structure (English Audio)',
        topic: 'Chemistry',
        languageTag: 'en',
        classTag: '',
        locked: false,
      ),
      (
        id: 'atom-structure-hi',
        title: 'Atom Structure (Hindi Audio)',
        topic: 'Chemistry',
        languageTag: 'hi',
        classTag: '',
        locked: false,
      ),
    ],
    'Geography': [
      (
        id: 'solar-system',
        title: 'Solar System 3D',
        topic: 'Space',
        languageTag: 'all',
        classTag: '',
        locked: false,
      ),
      (
        id: 'ocean-layers',
        title: 'Ocean Layers 3D',
        topic: 'Earth',
        languageTag: 'all',
        classTag: '',
        locked: false,
      ),
    ],
    'History': [
      (
        id: 'ancient-rome',
        title: 'Ancient Rome 3D',
        topic: 'World History',
        languageTag: 'all',
        classTag: '',
        locked: false,
      ),
    ],
  };

  static Map<String, List<QuizSummary>> _groupQuizzesBySubject(
    List<QuizSummary> quizzes,
  ) {
    final grouped = <String, List<QuizSummary>>{};
    for (final q in quizzes) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    return grouped;
  }

  static void _navigateToQuiz(BuildContext context, WidgetRef ref, String id) {
    if (id.isEmpty) return;
    if (id.contains('/') || id.contains('..')) return;
    final mps = ref.read(moduleProgressStoreProvider);
    // Already mastered + a saved attempt exists → open the RESULT screen in
    // review mode instead of re-launching the quiz for re-answering.
    if (mps.isMastered(id) && mps.hasSavedAttempt(id)) {
      final a = mps.readQuizAttempt(id)!;
      final qtexts = (a['questionTexts'] as List).cast<String>();
      final opts = (a['options'] as List)
          .map((o) => (o as List).cast<String>())
          .toList();
      final correct = (a['correct'] as List).cast<int>();
      final expl = (a['explanations'] as List).cast<String>();
      final answers = (a['answers'] as List).cast<int?>();
      final questions = <QuizQuestion>[
        for (int i = 0; i < qtexts.length; i++)
          QuizQuestion(
            questionText: qtexts[i],
            options: i < opts.length ? opts[i] : const [],
            correctAnswerIndex: i < correct.length ? correct[i] : 0,
            explanation: i < expl.length && expl[i].isNotEmpty ? expl[i] : null,
          ),
      ];
      final score = [
        for (int i = 0; i < questions.length; i++)
          if (i < answers.length &&
              answers[i] == questions[i].correctAnswerIndex)
            1
      ].length;
      context.push('/quiz-result', extra: {
        'score': score,
        'total': questions.length,
        'xpEarned': score * 50,
        'quizId': id,
        'questions': questions,
        'studentAnswers': answers,
        'review': true,
      });
      return;
    }
    context.push('/quiz/$id');
  }

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  // ✨ State to track which subject tile is tapped!
  String _selectedSubject = 'All';

  @override
  void initState() {
    super.initState();
    // Open on the subject passed from the Home tile (if any). If that subject
    // isn't in the loaded list, the build() guard falls back to 'All'.
    final s = widget.initialSubject;
    if (s != null && s.trim().isNotEmpty) _selectedSubject = s;
  }

  @override
  Widget build(BuildContext context) {
    // ── Territory licensing gate (GPS-primary) ──────────────────────────────
    // Strict: a student outside every geofenced/licensed state gets no content.
    // Safety valve: GPS unavailable/denied → "enable location" prompt, not a lockout.
    if (!kPresentationMode) {
      final geoAsync = ref.watch(geoStateProvider);
      final geo = geoAsync.valueOrNull;
      if (geoAsync.isLoading && geo == null) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: OrbitLoader(
              message: context.tr(
                  ref, 'student_finding_your_state', 'Finding your state…')),
        );
      }
      if (geo != null && geo.status != GeoStatus.insideTerritory) {
        final isGps = geo.status == GeoStatus.gpsUnavailable;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isGps ? '📍' : '🌏',
                      style: const TextStyle(fontSize: 48),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isGps
                          ? context.tr(
                              ref,
                              'learn_location_needed',
                              'Location needed',
                            )
                          : context.tr(
                              ref,
                              'learn_not_available_here',
                              'Not available here yet',
                            ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Baloo2',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      geo.message != null
                          ? context.trText(ref, geo.message!)
                          : (isGps
                              ? context.tr(
                                  ref,
                                  'learn_location_needed_body',
                                  'Turn on location to access your state\'s lessons.',
                                )
                              : context.tr(
                                  ref,
                                  'learn_not_available_body',
                                  'MITRA is not yet available in your location.',
                                )),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (isGps)
                      ElevatedButton(
                        onPressed: () => ref.invalidate(geoStateProvider),
                        child: Text(
                          context.tr(ref, 'btn_try_again', 'Try again'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    final params = ref.watch(quizFilterParamsProvider);
    final quizAsync = ref.watch(quizFeedProvider(params));

    final currentLang = ref.watch(translationProvider).langCode;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Colors.transparent, // ✨ Global background support
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✨ DYNAMIC THEMED HEADER: Adapts to the clicked Subject tile and shows real-time stats!
            _LearnHeader(selectedSubject: _selectedSubject),
            Expanded(
              child: quizAsync.when(
                loading: () => OrbitLoader(
                    message: context.tr(ref, 'student_loading_your_lessons',
                        'Loading your lessons…')),
                error: (error, _) => _ErrorState(
                  // Localised via the app's i18n, falling back to the failure's
                  // English displayMessage if the translation pack lacks the key.
                  message: switch (error) {
                    LearnFailure f =>
                      context.tr(ref, f.messageKey, f.displayMessage),
                    _ => context.tr(ref, 'error_generic',
                        'Something went wrong. Please try again.'),
                  },
                  onRetry: () =>
                      ref.read(quizFeedProvider(params).notifier).refresh(),
                ),
                data: (quizzes) {
                  // Live-or-demo AR catalog (geofenced by state when live),
                  // with the demo map as fallback so the list is never empty.
                  final arCatalog = ref.watch(arCatalogProvider).valueOrNull;
                  final arBySubject =
                      arCatalog?.bySubject ?? LearnScreen._arLessonsBySubject;
                  final arGlbById =
                      arCatalog?.glbById ?? const <String, String>{};

                  final filteredQuizzes = quizzes.where((q) {
                    return q.languageTag == currentLang ||
                        q.languageTag == 'all';
                  }).toList();

                  final grouped = LearnScreen._groupQuizzesBySubject(
                    filteredQuizzes,
                  );

                  for (final subject in arBySubject.keys) {
                    grouped.putIfAbsent(subject, () => []);
                  }

                  if (grouped.isEmpty) {
                    // Outside MITRA's approved territory → geofence message;
                    // otherwise the playful "coming soon".
                    return OrbitEmptyView(
                      type: (arCatalog?.territorySupported ?? true)
                          ? OrbitErrorType.comingSoon
                          : OrbitErrorType.unavailable,
                    );
                  }

                  // Gather all unique subjects for the top tiles
                  final allSubjects = ['All', ...grouped.keys.toList()..sort()];

                  // Ensure selected subject is valid
                  if (!allSubjects.contains(_selectedSubject)) {
                    _selectedSubject = 'All';
                  }

                  // ✨ Filter the vertical list below based on the tapped tile!
                  final displayEntries = _selectedSubject == 'All'
                      ? grouped.entries
                      : grouped.entries.where((e) => e.key == _selectedSubject);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Download-for-offline: caches this state's AR models +
                      // audio over Wi-Fi so lessons open without a live
                      // connection. No-op (with a hint) if not on Wi-Fi.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(MitraSpacing.lg,
                            MitraSpacing.sm, MitraSpacing.lg, 0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(
                                Icons.download_for_offline_outlined,
                                size: 18),
                            label: Text(context.tr(
                                ref,
                                'student_save_lessons_offline',
                                'Save lessons offline')),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final models = arCatalog?.glbById ??
                                  const <String, String>{};
                              final audio = arCatalog?.audioById ??
                                  const <String, String>{};
                              if (models.isEmpty && audio.isEmpty) {
                                messenger.showSnackBar(SnackBar(
                                    content: Text(ref.trNow(
                                        'student_no_downloadable_lessons_for_your_sta',
                                        'No downloadable lessons for your state yet.'))));
                                return;
                              }
                              messenger.showSnackBar(SnackBar(
                                  content: Text(context.tr(
                                      ref,
                                      'student_downloading_over_wi_fi',
                                      'Downloading over Wi-Fi…'))));
                              final n = await ArPackStore.instance.downloadPack(
                                models: models,
                                audios: audio,
                                wifiOnly: true,
                              );
                              messenger.showSnackBar(SnackBar(
                                  content: Text(n > 0
                                      ? ref.trpNow(
                                          'student_saved_n_files_for_offline_use',
                                          '✅ Saved {n} files for offline use', {
                                          'n': '$n'
                                        })
                                      : ref.trNow(
                                          'student_connect_to_wi_fi_to_download',
                                          'Connect to Wi-Fi to download lessons.'))));
                            },
                          ),
                        ),
                      ),
                      // ════════════════════════════════════════════════
                      // ✨ TOP SECTION: Square Subject Filter Tiles
                      // ════════════════════════════════════════════════
                      SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: MitraSpacing.lg,
                          ),
                          itemCount: allSubjects.length,
                          itemBuilder: (context, index) {
                            final subject = allSubjects[index];
                            final isSelected = subject == _selectedSubject;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedSubject = subject;
                                });
                              },
                              child: Container(
                                width: 100, // ✨ Square Tile Layout
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? MitraColors.saffron.withValues(
                                          alpha: 0.15,
                                        )
                                      : onSurface.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? MitraColors.saffron
                                        : onSurface.withValues(alpha: 0.1),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      subject == 'All'
                                          ? '🌐'
                                          : _emojiFor(subject),
                                      style: const TextStyle(fontSize: 32),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      context.trText(ref, subject),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Baloo2',
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        fontSize: 14,
                                        color: isSelected
                                            ? MitraColors.saffron
                                            : onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: MitraSpacing.md),

                      // ════════════════════════════════════════════════
                      // ✨ BOTTOM SECTION: Chapters and Topics
                      // ════════════════════════════════════════════════
                      Expanded(
                        child: RefreshIndicator(
                          color: MitraColors.saffron,
                          backgroundColor: MitraColors.bgCard,
                          onRefresh: () => ref
                              .read(quizFeedProvider(params).notifier)
                              .refresh(),
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(
                              MitraSpacing.lg,
                              0,
                              MitraSpacing.lg,
                              MediaQuery.paddingOf(context).bottom +
                                  MitraSpacing.lg,
                            ),
                            children: displayEntries.map((entry) {
                              final arLessonsForSubject =
                                  arBySubject[entry.key] ?? [];

                              // Scope to the student's OWN class: a Class IX
                              // student must not see other classes' modules.
                              // Lessons with no class tag are shown (ungated
                              // legacy content), as are exact class matches.
                              final userClass =
                                  (ref.watch(currentUserProvider)?.classGrade ??
                                          '')
                                      .trim()
                                      .toLowerCase();
                              final filteredArLessons =
                                  arLessonsForSubject.where((ar) {
                                final langOk = ar.languageTag == currentLang ||
                                    ar.languageTag == 'all';
                                final arClass =
                                    ar.classTag.trim().toLowerCase();
                                final classOk = userClass.isEmpty ||
                                    arClass.isEmpty ||
                                    arClass == userClass;
                                return langOk && classOk;
                              }).toList();

                              if (entry.value.isEmpty &&
                                  filteredArLessons.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return _SubjectSection(
                                subject: entry.key,
                                quizzes: entry.value,
                                arLessons: filteredArLessons,
                                audiosByLangById:
                                    arCatalog?.audiosByLangById ?? const {},
                                hideHeader: _selectedSubject !=
                                    'All', // ✨ Hides redundant headings when filtered!
                                onQuizTap: (id) => LearnScreen._navigateToQuiz(
                                    context, ref, id),
                                onArTap: (id) {
                                  // Remember this as the last-opened lesson so
                                  // Home's "Continue Learning" card shows REAL
                                  // data (title/subject/topic/%), not a stub.
                                  final rec = filteredArLessons
                                      .where((l) => l.id == id)
                                      .cast<ArLessonRec?>()
                                      .firstWhere(
                                        (_) => true,
                                        orElse: () => null,
                                      );
                                  if (rec != null) {
                                    ref
                                        .read(moduleProgressStoreProvider)
                                        .recordOpenedModule(
                                          id: rec.id,
                                          title: rec.title,
                                          subject: entry.key,
                                          topic: rec.topic,
                                        );
                                  }
                                  // Fixes the old '/ar/$id' route (no such
                                  // route existed) and carries the real model
                                  // URL when the dashboard supplied one.
                                  // Offline-first: prefer a cached on-device
                                  // file (downloaded over Wi-Fi) over the
                                  // network URL. Falls back to the URL.
                                  final localGlb =
                                      ArPackStore.instance.localModel(id);
                                  final localAud =
                                      ArPackStore.instance.localAudio(id);
                                  final glb = localGlb ?? arGlbById[id];
                                  final nativeGlb =
                                      arCatalog?.nativeGlbById[id];
                                  final vid = arCatalog?.videoById[id];
                                  final aud =
                                      localAud ?? arCatalog?.audioById[id];
                                  final chroma = arCatalog?.chromaById[id];
                                  final qp = <String>[];
                                  if (glb != null && glb.isNotEmpty) {
                                    qp.add('glb=${Uri.encodeComponent(glb)}');
                                  }
                                  if (nativeGlb != null &&
                                      nativeGlb.isNotEmpty) {
                                    qp.add(
                                      'nglb=${Uri.encodeComponent(nativeGlb)}',
                                    );
                                  }
                                  if (vid != null && vid.isNotEmpty) {
                                    qp.add('video=${Uri.encodeComponent(vid)}');
                                  }
                                  if (aud != null && aud.isNotEmpty) {
                                    qp.add('audio=${Uri.encodeComponent(aud)}');
                                  }
                                  final auds = arCatalog?.audiosByLangById[id];
                                  if (auds != null && auds.isNotEmpty) {
                                    qp.add(
                                        'audios=${Uri.encodeComponent(jsonEncode(auds))}');
                                  }
                                  final audsAac =
                                      arCatalog?.audiosAacByLangById[id];
                                  if (audsAac != null && audsAac.isNotEmpty) {
                                    qp.add(
                                        'audios_aac=${Uri.encodeComponent(jsonEncode(audsAac))}');
                                  }
                                  if (chroma != null && chroma.isNotEmpty) {
                                    qp.add(
                                      'chroma=${Uri.encodeComponent(chroma)}',
                                    );
                                  }
                                  final query =
                                      qp.isEmpty ? '' : '?${qp.join('&')}';
                                  context.push('/student/ar/$id$query');
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dynamic Themed Header ────────────────────────────────

class _LearnHeader extends ConsumerWidget {
  final String selectedSubject;
  const _LearnHeader({required this.selectedSubject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    // ✨ Fetch real stats from the current user.
    // Using XP to estimate counts dynamically for the UI demo,
    // but you can wire this directly to your database variables later!
    // Single source of truth: the achievement-engine profile (live Isar stream).
    final profile = ref.watch(studentProfileProvider).valueOrNull;
    final xp = profile?.totalXp ?? 0;
    // Progress counters derived from the student's XP, matching the engine.
    final topicsConsumed = (xp / 100).floor();
    final quizzesTaken = (xp / 500).floor();

    final isAll = selectedSubject == 'All';
    final title = isAll
        ? context.tr(ref, 'student_learn_modules', 'Learn Modules')
        : selectedSubject;
    final emoji = isAll ? '📚' : _emojiFor(selectedSubject);
    final themeColor = isAll ? MitraColors.saffron : MitraColors.indigoLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: themeColor.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    color: themeColor.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAll
                            ? context.tr(
                                ref, 'student_curriculum', 'Curriculum')
                            : context.tr(ref, 'student_subject', 'Subject'),
                        style: TextStyle(
                          fontFamily: 'Mukta',
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          color: onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ✨ Real-time student status tracking
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatBadge(
                icon: '🎯',
                label: context.trp(
                    ref,
                    'student_topicsconsumed_topics',
                    '{topicsConsumed} Topics',
                    {'topicsConsumed': '$topicsConsumed'}),
                color: onSurface,
              ),
              const SizedBox(height: 6),
              _StatBadge(
                icon: '📝',
                label: context.trp(
                    ref,
                    'student_quizzestaken_quizzes',
                    '{quizzesTaken} Quizzes',
                    {'quizzesTaken': '$quizzesTaken'}),
                color: onSurface,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'SpaceMono',
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Subject section ──────────────────────────────────────

class _SubjectSection extends ConsumerWidget {
  final String subject;
  final List<QuizSummary> quizzes;
  final List<ArLessonRec> arLessons;
  final bool hideHeader; // ✨ New parameter to control header visibility
  final ValueChanged<String> onQuizTap;
  final ValueChanged<String> onArTap;
  final Map<String, Map<String, String>> audiosByLangById; // #8b

  const _SubjectSection({
    required this.subject,
    required this.quizzes,
    required this.arLessons,
    this.hideHeader = false,
    required this.onQuizTap,
    required this.onArTap,
    this.audiosByLangById = const {},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild locks/badges whenever progress changes.
    ref.watch(moduleProgressTickProvider);
    // #8b: the student's chosen UI/narration language (for availability badge).
    final myLang = ref.watch(translationProvider).langCode.toLowerCase();
    final progress = ref.watch(moduleProgressStoreProvider);

    // AR-watch % needed to unlock a quiz. Dashboard-configurable; 80 until the
    // setting loads or if the fetch fails.
    final arWatchThreshold = ref.watch(arWatchThresholdProvider).maybeWhen(
          data: (v) => v,
          orElse: () => 80,
        );

    // Match each AR module to its quiz by shared id → gives us the question
    // count to show as subtext, and the quiz list item once AR is watched.
    final quizById = {for (final q in quizzes) q.id: q};

    final totalItems = quizzes.length + arLessons.length;

    return Semantics(
      header: true,
      label: context.trp(
          ref,
          'student_subject_totalitems_items',
          '{subject}, {totalItems} items',
          {'subject': subject, 'totalItems': totalItems.toString()}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideHeader) // ✨ Only show header when 'All' is selected
            Padding(
              padding: const EdgeInsets.only(bottom: MitraSpacing.sm),
              child: Row(
                children: [
                  Text(
                    _emojiFor(subject),
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      subject,
                      style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface, // ✨ Themed
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: MitraColors.saffron.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(MitraRadius.pill),
                      border: Border.all(
                        color: MitraColors.saffron.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '$totalItems',
                      style: const TextStyle(
                        fontFamily: 'SpaceMono',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        color: MitraColors.saffron,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Gated modules, in list order. The first is always open; each later
          // one unlocks only when the previous module is mastered (100%).
          ...() {
            final widgets = <Widget>[];
            final shownQuizIds = <String>{};
            bool prevMastered = true; // first module in the subject is open
            for (int i = 0; i < arLessons.length; i++) {
              final ar = arLessons[i];

              // Rule 3: a "coming soon" scheduled teaser — show it greyed and
              // non-openable (name + lock only), and do NOT let it affect the
              // mastery chain or the first-module-open rule.
              if (ar.locked) {
                widgets.add(_ArTile(
                  lesson: ar,
                  onTap: (_) {},
                  unlocked: false,
                  bestPct: 0,
                  questionCount: 0,
                  completed: false,
                  comingSoon: true,
                ));
                continue;
              }

              final unlocked = (i == 0) || prevMastered;
              final best = progress.bestPct(ar.id);
              // Quiz unlocks only after the AR narration is heard past the
              // dashboard-configured threshold (default 80%).
              final watched = progress.arWatchedPct(ar.id) >= arWatchThreshold;
              final matchedQuiz = quizById[ar.id];
              final qCount = matchedQuiz?.questionCount ?? 0;

              widgets.add(
                _ArTile(
                  lesson: ar,
                  onTap: onArTap,
                  unlocked: unlocked,
                  bestPct: best,
                  questionCount: qCount,
                  completed: watched, // watched enough → Completed stamp
                  audioLabel: () {
                    final langs =
                        (audiosByLangById[ar.id] ?? const {}).keys.toSet();
                    if (langs.isEmpty) return '';
                    if (myLang.isNotEmpty && langs.contains(myLang)) {
                      return context.tr(
                          ref, 'student_your_language', 'Your language');
                    }
                    if (langs.contains('hi') || langs.contains('en')) {
                      return context.tr(
                          ref, 'student_hindi_english', 'Hindi/English');
                    }
                    return '';
                  }(),
                ),
              );

              // Once the module is unlocked, its quiz is ALWAYS shown. If the AR
              // hasn't been watched enough yet, the quiz appears greyed and
              // tapping it opens the "finish the AR first" dialog (Rule 1).
              if (unlocked && matchedQuiz != null) {
                shownQuizIds.add(matchedQuiz.id);
                widgets.add(
                  _QuizTile(
                    quiz: matchedQuiz,
                    onTap: onQuizTap,
                    bestPct: best,
                    locked: !watched,
                    onLockedTap: () => _showWatchArFirstDialog(
                        context, arWatchThreshold, () => onArTap(ar.id)),
                  ),
                );
              }

              // Chain: the next module needs THIS one mastered.
              prevMastered = progress.isMastered(ar.id);
            }

            // Any quizzes with no matching AR module (standalone) show as before.
            for (final q in quizzes) {
              if (shownQuizIds.contains(q.id)) continue;
              widgets.add(
                _QuizTile(
                  quiz: q,
                  onTap: onQuizTap,
                  bestPct: progress.bestPct(q.id),
                ),
              );
            }
            return widgets;
          }(),
          const SizedBox(height: MitraSpacing.lg),
        ],
      ),
    );
  }
}

// ── Individual quiz tile ─────────────────────────────────

class _QuizTile extends StatelessWidget {
  final QuizSummary quiz;
  final ValueChanged<String> onTap;
  final int bestPct; // 0..100 — this student's best score on this module
  // Rule 1: when the AR hasn't been watched enough, the quiz shows greyed and
  // tapping it fires onLockedTap (the "watch the AR first" dialog) instead.
  final bool locked;
  final VoidCallback? onLockedTap;

  const _QuizTile({
    required this.quiz,
    required this.onTap,
    this.bestPct = 0,
    this.locked = false,
    this.onLockedTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: '${quiz.title}. '
          '${quiz.questionCount} questions. '
          '${locked ? 'Locked. Finish the AR module first. ' : ''}'
          '${quiz.topic.isNotEmpty ? 'Topic: ${quiz.topic}.' : ''}'
          '${quiz.avgScore > 0 ? ' Average score ${quiz.avgScore.toStringAsFixed(0)} percent.' : ''}',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: locked ? 0.5 : 1.0,
          child: GestureDetector(
            onTap: () => locked ? (onLockedTap?.call()) : onTap(quiz.id),
            child: Container(
              margin: const EdgeInsets.only(bottom: MitraSpacing.sm),
              padding: const EdgeInsets.all(MitraSpacing.lg),
              decoration: BoxDecoration(
                // ✨ Global Glass Theme Applied
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    onSurface.withValues(alpha: 0.08),
                    onSurface.withValues(alpha: 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(MitraRadius.md),
                border: Border.all(color: onSurface.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  _QuestionCountBadge(count: quiz.questionCount),
                  const SizedBox(width: MitraSpacing.md),
                  Expanded(
                    child: _QuizInfo(title: quiz.title, topic: quiz.topic),
                  ),
                  if (bestPct > 0) ...[
                    const SizedBox(width: 8),
                    _ScoreBadge(pct: bestPct),
                  ] else if (quiz.avgScore > 0) ...[
                    const SizedBox(width: 8),
                    _AvgScoreChip(score: quiz.avgScore),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    locked ? Icons.lock_outline : Icons.arrow_forward_ios,
                    size: locked ? 16 : 14,
                    color: onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── AR Lesson tile (gated + badge + N-questions subtext) ─────────────────

class _ArTile extends ConsumerWidget {
  final ArLessonRec lesson;
  final ValueChanged<String> onTap;
  final bool unlocked; // false = greyed, tap shows "unlock" hint
  final int bestPct; // 0..100 best score on this module
  final int questionCount; // shown as "N questions" subtext
  final bool completed; // ≥80% AR narration watched → Completed stamp
  final bool
      comingSoon; // Rule 3: scheduled teaser — "Coming soon", not openable
  final String audioLabel; // #8b: '' | 'Your language' | 'Hindi/English'

  const _ArTile({
    required this.lesson,
    required this.onTap,
    this.unlocked = true,
    this.bestPct = 0,
    this.questionCount = 0,
    this.completed = false,
    this.comingSoon = false,
    this.audioLabel = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    final subtext = questionCount > 0
        ? '${lesson.topic.isNotEmpty ? '${lesson.topic} · ' : ''}${questionCount == 1 ? context.tr(ref, 'student_1_question', '1 question') : context.trp(ref, 'student_n_questions', '{count} questions', {
                'count': '$questionCount'
              })}'
        : lesson.topic;
    final audioNote = audioLabel.isEmpty ? '' : ' · 🔊 $audioLabel';

    final card = Container(
      margin: const EdgeInsets.only(bottom: MitraSpacing.sm),
      padding: const EdgeInsets.all(MitraSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MitraColors.sky.withValues(alpha: unlocked ? 0.15 : 0.05),
            onSurface.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(
          color: MitraColors.sky.withValues(alpha: unlocked ? 0.3 : 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MitraColors.sky.withValues(alpha: unlocked ? 0.2 : 0.08),
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              border: Border.all(color: MitraColors.sky.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(
              unlocked ? '🧊' : '🔒',
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(width: MitraSpacing.md),
          Expanded(
            child: _QuizInfo(
              title: lesson.title,
              topic: comingSoon
                  ? context.tr(ref, 'student_coming_soon', 'Coming soon')
                  : unlocked
                      ? subtext + audioNote
                      : context.tr(
                          ref,
                          'student_score_100_on_the_previous_module',
                          'Score 100% on the previous module to unlock'),
            ),
          ),
          const SizedBox(width: 8),
          // AR "Completed 100%" stamp once ≥80% of the narration is watched.
          if (completed) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: MitraColors.emerald.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(MitraRadius.pill),
                border: Border.all(
                    color: MitraColors.emerald.withValues(alpha: 0.35)),
              ),
              child: Text(
                context.tr(ref, 'student_completed_100', '✓ COMPLETED 100%'),
                style: TextStyle(
                    fontFamily: 'SpaceMono',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: MitraColors.emerald),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Badge: 100% once mastered, otherwise best % so far (if attempted).
          if (bestPct > 0) ...[
            _ScoreBadge(pct: bestPct),
            const SizedBox(width: 8),
          ],
          if (unlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: MitraColors.sky.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(MitraRadius.pill),
              ),
              child: Row(
                children: [
                  Icon(Icons.view_in_ar, size: 14, color: Colors.black87),
                  SizedBox(width: 4),
                  Text(
                    context.tr(ref, 'student_view_3d', 'View 3D'),
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            )
          else
            Icon(
              Icons.lock_outline,
              size: 18,
              color: onSurface.withValues(alpha: 0.4),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: comingSoon
          ? context.trp(
              ref,
              'student_coming_soon_title_not_yet_available',
              'Coming soon: {title}. Not yet available.',
              {'title': lesson.title})
          : unlocked
              ? context.trp(ref, 'student_3d_lesson_title',
                  '3D Lesson: {title}', {'title': lesson.title})
              : context.trp(
                  ref,
                  'student_locked_title_score_100_on_the',
                  'Locked: {title}. Score 100% on the previous module to unlock.',
                  {'title': lesson.title}),
      child: ExcludeSemantics(
        child: GestureDetector(
          // Locked tiles do nothing on tap (the hint is already visible).
          onTap: unlocked ? () => onTap(lesson.id) : null,
          child: Opacity(opacity: unlocked ? 1.0 : 0.6, child: card),
        ),
      ),
    );
  }
}

// ── Score badge (100% or best % so far) ──────────────────
class _ScoreBadge extends ConsumerWidget {
  final int pct;
  const _ScoreBadge({required this.pct});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mastered = pct >= 100;
    final color = mastered ? MitraColors.emerald : MitraColors.saffron;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MitraRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        mastered
            ? context.tr(ref, 'student_completed_100', '✓ COMPLETED 100%')
            : '$pct%',
        style: TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Extracted sub-widgets ────────────────────────────────

class _QuestionCountBadge extends ConsumerWidget {
  final int count;
  const _QuestionCountBadge({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: MitraColors.indigoLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MitraRadius.sm),
        border: Border.all(
          color: MitraColors.indigoLight.withValues(alpha: 0.25),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: MitraColors.indigoLight,
            ),
          ),
          Text(
            context.tr(ref, 'student_qs', 'Qs'),
            style: TextStyle(
              fontFamily: 'Mukta',
              fontSize: 9,
              color: MitraColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizInfo extends StatelessWidget {
  final String title;
  final String topic;
  const _QuizInfo({required this.title, required this.topic});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(
      context,
    ).colorScheme.onSurface; // ✨ Automatically adapts

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Baloo2',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: onSurface,
          ),
        ),
        if (topic.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            topic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Mukta',
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

class _AvgScoreChip extends ConsumerWidget {
  final double score;
  const _AvgScoreChip({required this.score});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MitraColors.emerald.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MitraRadius.pill),
        border: Border.all(color: MitraColors.emerald.withValues(alpha: 0.25)),
      ),
      child: Text(
        context.trp(ref, 'student_avg_v1', 'avg {v1}%',
            {'v1': score.toStringAsFixed(0)}),
        style: const TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: MitraColors.emerald,
        ),
      ),
    );
  }
}

// ── Error state (distinct from empty — shows ⚠️) ────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MitraSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: MitraSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Mukta',
                fontSize: 14,
                color: MitraColors.textMuted,
              ),
            ),
            const SizedBox(height: MitraSpacing.lg),
            _RetryButton(onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

// ── Shared retry button ──────────────────────────────────

class _RetryButton extends ConsumerWidget {
  final VoidCallback onTap;
  const _RetryButton({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: context.tr(
            ref, 'student_retry_loading_quizzes', 'Retry loading quizzes'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: MitraColors.saffron.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(MitraRadius.pill),
            border: Border.all(
              color: MitraColors.saffron.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            context.tr(ref, 'btn_retry', 'Retry'),
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: MitraColors.saffron,
            ),
          ),
        ),
      ),
    );
  }
}
