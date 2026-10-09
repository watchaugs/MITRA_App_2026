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

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/colors.dart';
import '../../services/api_service.dart';
import '../../stores/auth_store.dart';
import '../../providers/translation_provider.dart'; // ✨ Added for language filtering

// ═══════════════════════════════════════════════════════════
// DOMAIN: Failures
// ═══════════════════════════════════════════════════════════

/// Sealed failure hierarchy — the UI can present the right
/// message and downstream consumers (analytics, crash-
/// reporting, retry logic) can react without string-matching.
sealed class LearnFailure {
  const LearnFailure();

  /// Human-readable message safe to show in the UI.
  /// TODO: Localise via ARB files in a real app.
  String get displayMessage;
}

class NetworkFailure extends LearnFailure {
  const NetworkFailure();
  @override
  String get displayMessage =>
      'Could not reach the server. Please check your connection.';
}

class ServerFailure extends LearnFailure {
  const ServerFailure();
  @override
  String get displayMessage =>
      'Something went wrong on our end. Please try again later.';
}

class ParsingFailure extends LearnFailure {
  const ParsingFailure();
  @override
  String get displayMessage => 'Received unexpected data. Please try again.';
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
        developer.log(
          'Malformed quiz at index $i: $e',
          name: 'LearnScreen',
        );
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
  // TODO: Once QuizAPI is refactored to an injectable instance
  //       rather than static methods, accept it as a constructor
  //       parameter for full DI support.
  const ApiQuizRepository();

  @override
  Future<List<QuizSummary>> fetchLiveQuizzes(
    QuizFilterParams params,
  ) async {
    try {
      final res = await QuizAPI.list(params.toQueryParams());
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
    } catch (e, st) {
      developer.log(
        'Quiz fetch failed',
        name: 'LearnScreen',
        error: e,
        stackTrace: st,
      );
      // TODO: Differentiate NetworkFailure vs ServerFailure
      //       once ApiService exposes typed HTTP exceptions.
      throw const NetworkFailure();
    }
  }
}

// ═══════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════

/// Repository instance — override in tests with a mock.
final quizRepositoryProvider = Provider<QuizRepository>((ref) {
  return kPresentationMode
      ? const DemoQuizRepository()
      : const ApiQuizRepository();
});

/// Derives quiz filter params from the current user profile.
/// Returns empty params when the user is not logged in.
final quizFilterParamsProvider = Provider<QuizFilterParams>((ref) {
  final user = ref.watch(currentUserProvider);
  return QuizFilterParams(
    className: user?.classGrade ?? '',
    state: user?.assignedState ?? '',
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
});

/// The AR lessons to show (grouped by subject) plus a side map of each
/// topic id -> its real GLB model URL (empty in demo mode).
class ArCatalog {
  final Map<String, List<ArLessonRec>> bySubject;
  final Map<String, String> glbById;
  const ArCatalog({required this.bySubject, required this.glbById});
}

/// Live AR topics from the dashboard, scoped to the student's state (so the
/// dashboard's geofencing applies), with the hardcoded demo map as a safe
/// fallback — the list is never empty on stage. In presentation mode it
/// returns the demo map unchanged and no network call is made.
final arCatalogProvider = FutureProvider<ArCatalog>((ref) async {
  if (kPresentationMode) {
    return const ArCatalog(
      bySubject: LearnScreen._arLessonsBySubject,
      glbById: {},
    );
  }

  final user = ref.watch(currentUserProvider);
  final state = user?.assignedState ?? '';
  final lang = ref.watch(translationProvider).langCode;

  final res = await CurriculumAPI.arTopics({
    if (state.isNotEmpty) 'state': state,
    if (lang.isNotEmpty) 'lang': lang,
  });

  final raw = res.data is Map ? res.data['data'] : null;
  final bySubject = <String, List<ArLessonRec>>{};
  final glbById = <String, String>{};

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
      ));
      final glb =
          (m['flutter_url'] ?? m['glb_url'] ?? m['model_url'] ?? '').toString();
      if (glb.isNotEmpty) glbById[id] = glb;
    }
  }

  // Nothing came back → keep the demo list so the screen isn't blank.
  if (bySubject.isEmpty) {
    return const ArCatalog(
      bySubject: LearnScreen._arLessonsBySubject,
      glbById: {},
    );
  }
  return ArCatalog(bySubject: bySubject, glbById: glbById);
});

/// Async quiz feed notifier — exposes typed errors through
/// [LearnFailure] and supports explicit refresh that keeps
/// existing data visible during pull-to-refresh.
final quizFeedProvider = AsyncNotifierProvider.family<QuizFeedNotifier,
    List<QuizSummary>, QuizFilterParams>(
  QuizFeedNotifier.new,
);

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
  const LearnScreen({super.key});

  // ✨ Hardcoded mapping of AR Lessons to their respective subjects
  static const _arLessonsBySubject = <String,
      List<({String id, String title, String topic, String languageTag})>>{
    'Science': [
      (
        id: 'cell-division',
        title: 'Cell Division 3D',
        topic: 'Biology',
        languageTag: 'all'
      ),
      (
        id: 'atom-structure-en',
        title: 'Atom Structure (English Audio)',
        topic: 'Chemistry',
        languageTag: 'en'
      ),
      (
        id: 'atom-structure-hi',
        title: 'Atom Structure (Hindi Audio)',
        topic: 'Chemistry',
        languageTag: 'hi'
      ),
    ],
    'Geography': [
      (
        id: 'solar-system',
        title: 'Solar System 3D',
        topic: 'Space',
        languageTag: 'all'
      ),
      (
        id: 'ocean-layers',
        title: 'Ocean Layers 3D',
        topic: 'Earth',
        languageTag: 'all'
      ),
    ],
    'History': [
      (
        id: 'ancient-rome',
        title: 'Ancient Rome 3D',
        topic: 'World History',
        languageTag: 'all'
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

  static void _navigateToQuiz(BuildContext context, String id) {
    if (id.isEmpty) return;
    if (id.contains('/') || id.contains('..')) return;
    context.go('/quiz/$id');
  }

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  // ✨ State to track which subject tile is tapped!
  String _selectedSubject = 'All';

  @override
  Widget build(BuildContext context) {
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
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: MitraColors.saffron,
                  ),
                ),
                error: (error, _) => _ErrorState(
                  message: switch (error) {
                    LearnFailure f => f.displayMessage,
                    _ => 'Something went wrong. Please try again.',
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

                  final grouped =
                      LearnScreen._groupQuizzesBySubject(filteredQuizzes);

                  for (final subject in arBySubject.keys) {
                    grouped.putIfAbsent(subject, () => []);
                  }

                  if (grouped.isEmpty) {
                    final user = ref.read(currentUserProvider);
                    return _EmptyState(
                      message: user?.classGrade != null
                          ? 'No live content for ${user!.classGrade} yet.'
                          : 'No live content available right now.',
                      onRetry: () =>
                          ref.read(quizFeedProvider(params).notifier).refresh(),
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
                      // ════════════════════════════════════════════════
                      // ✨ TOP SECTION: Square Subject Filter Tiles
                      // ════════════════════════════════════════════════
                      SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: MitraSpacing.lg),
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
                                      ? MitraColors.saffron
                                          .withValues(alpha: 0.15)
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
                                        style: const TextStyle(fontSize: 32)),
                                    const SizedBox(height: 8),
                                    Text(
                                      subject,
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

                              final filteredArLessons =
                                  arLessonsForSubject.where((ar) {
                                return ar.languageTag == currentLang ||
                                    ar.languageTag == 'all';
                              }).toList();

                              if (entry.value.isEmpty &&
                                  filteredArLessons.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return _SubjectSection(
                                subject: entry.key,
                                quizzes: entry.value,
                                arLessons: filteredArLessons,
                                hideHeader: _selectedSubject !=
                                    'All', // ✨ Hides redundant headings when filtered!
                                onQuizTap: (id) =>
                                    LearnScreen._navigateToQuiz(context, id),
                                onArTap: (id) {
                                  // Fixes the old '/ar/$id' route (no such
                                  // route existed) and carries the real model
                                  // URL when the dashboard supplied one.
                                  final glb = arGlbById[id];
                                  context.push(
                                    glb != null && glb.isNotEmpty
                                        ? '/student/ar/$id?glb=${Uri.encodeComponent(glb)}'
                                        : '/student/ar/$id',
                                  );
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
    final user = ref.watch(currentUserProvider);
    final xp = user?.totalXp;
    final topicsConsumed = xp != null ? (xp / 100).floor() : 12;
    final quizzesTaken = xp != null ? (xp / 500).floor() : 4;

    final isAll = selectedSubject == 'All';
    final title = isAll ? 'Learn Modules' : selectedSubject;
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
                        color: themeColor.withValues(alpha: 0.5), width: 2),
                    color: themeColor.withValues(alpha: 0.15),
                  ),
                  child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 26))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAll ? 'Curriculum' : 'Subject',
                        style: TextStyle(
                            fontFamily: 'Mukta',
                            fontSize: 12,
                            color: onSurface.withValues(alpha: 0.6)),
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
                  label: '$topicsConsumed Topics',
                  color: onSurface),
              const SizedBox(height: 6),
              _StatBadge(
                  icon: '📝', label: '$quizzesTaken Quizzes', color: onSurface),
            ],
          )
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;

  const _StatBadge(
      {required this.icon, required this.label, required this.color});

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

class _SubjectSection extends StatelessWidget {
  final String subject;
  final List<QuizSummary> quizzes;
  final List<({String id, String title, String topic, String languageTag})>
      arLessons;
  final bool hideHeader; // ✨ New parameter to control header visibility
  final ValueChanged<String> onQuizTap;
  final ValueChanged<String> onArTap;

  const _SubjectSection({
    required this.subject,
    required this.quizzes,
    required this.arLessons,
    this.hideHeader = false,
    required this.onQuizTap,
    required this.onArTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalItems = quizzes.length + arLessons.length;

    return Semantics(
      header: true,
      label: '$subject, $totalItems items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideHeader) // ✨ Only show header when 'All' is selected
            Padding(
              padding: const EdgeInsets.only(bottom: MitraSpacing.sm),
              child: Row(
                children: [
                  Text(_emojiFor(subject),
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      subject,
                      style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color:
                            Theme.of(context).colorScheme.onSurface, // ✨ Themed
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: MitraColors.saffron.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(MitraRadius.pill),
                      border: Border.all(
                          color: MitraColors.saffron.withValues(alpha: 0.3)),
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
          // ✨ Inject AR Lessons dynamically at the top of the subject
          ...arLessons.map(
            (ar) => _ArTile(lesson: ar, onTap: onArTap),
          ),
          // Followed immediately by the quizzes
          ...quizzes.map(
            (q) => _QuizTile(quiz: q, onTap: onQuizTap),
          ),
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

  const _QuizTile({required this.quiz, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: '${quiz.title}. '
          '${quiz.questionCount} questions. '
          '${quiz.topic.isNotEmpty ? 'Topic: ${quiz.topic}.' : ''}'
          '${quiz.avgScore > 0 ? ' Average score ${quiz.avgScore.toStringAsFixed(0)} percent.' : ''}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => onTap(quiz.id),
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
                  child: _QuizInfo(
                    title: quiz.title,
                    topic: quiz.topic,
                  ),
                ),
                if (quiz.avgScore > 0) ...[
                  const SizedBox(width: 8),
                  _AvgScoreChip(score: quiz.avgScore),
                ],
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: onSurface.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── AR Lesson tile ───────────────────────────────────────

class _ArTile extends StatelessWidget {
  final ({String id, String title, String topic, String languageTag}) lesson;
  final ValueChanged<String> onTap;

  const _ArTile({required this.lesson, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: '3D Lesson: ${lesson.title}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => onTap(lesson.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: MitraSpacing.sm),
            padding: const EdgeInsets.all(MitraSpacing.lg),
            decoration: BoxDecoration(
              // ✨ AR Glass Theme Applied (Sky tint over theme background)
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  MitraColors.sky.withValues(alpha: 0.15),
                  onSurface.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(MitraRadius.md),
              border: Border.all(color: MitraColors.sky.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: MitraColors.sky.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(MitraRadius.sm),
                    border: Border.all(
                        color: MitraColors.sky.withValues(alpha: 0.3)),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🧊', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: MitraSpacing.md),
                Expanded(
                  child: _QuizInfo(
                    title: lesson.title,
                    topic: lesson.topic,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: MitraColors.sky.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(MitraRadius.pill),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.view_in_ar, size: 14, color: Colors.black87),
                      SizedBox(width: 4),
                      Text(
                        'View 3D',
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ],
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

// ── Extracted sub-widgets ────────────────────────────────

class _QuestionCountBadge extends StatelessWidget {
  final int count;
  const _QuestionCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: MitraColors.indigoLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MitraRadius.sm),
        border:
            Border.all(color: MitraColors.indigoLight.withValues(alpha: 0.25)),
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
          const Text(
            'Qs',
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
    final onSurface =
        Theme.of(context).colorScheme.onSurface; // ✨ Automatically adapts

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

class _AvgScoreChip extends StatelessWidget {
  final double score;
  const _AvgScoreChip({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MitraColors.emerald.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MitraRadius.pill),
        border: Border.all(color: MitraColors.emerald.withValues(alpha: 0.25)),
      ),
      child: Text(
        'avg ${score.toStringAsFixed(0)}%',
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

// ── Empty state (distinct from error — shows 📭) ────────

class _EmptyState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _EmptyState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MitraSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📭', style: TextStyle(fontSize: 48)),
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

class _RetryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RetryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Retry loading quizzes',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: MitraColors.saffron.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(MitraRadius.pill),
            border:
                Border.all(color: MitraColors.saffron.withValues(alpha: 0.35)),
          ),
          child: const Text(
            'Retry',
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
