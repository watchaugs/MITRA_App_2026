// ═══════════════════════════════════════════════════════
// MITRA — Module Progress Store (device-local gating state)
// ═══════════════════════════════════════════════════════
//
// WHAT THIS IS
//   The Learn tab gates modules: the NEXT module unlocks only after the
//   CURRENT module's quiz hits 100% (best attempt kept). It also hides a
//   module's quiz until the student has launched + watched its AR lesson once,
//   and shows a score badge (100% once mastered, otherwise the best % so far).
//
//   This file holds that per-module state ON THE DEVICE (SharedPreferences —
//   fast, offline, zero backend cost). It is the single source of truth the
//   Learn screen reads for locks and badges.
//
// CLOUD SYNC (no new network calls here)
//   The raw quiz attempts already ride to the backend through
//   quiz_offline_service.dart, which batches them on an interval. The backend
//   remaps those into student analytics. So this store does NOT make its own
//   network calls — it mirrors what the batched attempts already carry. If the
//   app is reinstalled, the device-local gates reset, but the cloud still has
//   the attempt history (and can be used to rehydrate later if you choose).
//
// KEYS (per module/quiz id)
//   mp_best_<id>   : int   best percentage score 0..100
//   mp_arseen_<id> : bool  AR lesson for this module launched + watched once
//
//   A module is "mastered" when mp_best_<id> == 100.
// ═══════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_provider.dart'; // sharedPreferencesProvider

String _bestKey(String id) => 'mp_best_$id';
String _arSeenKey(String id) => 'mp_arseen_$id';
String _ansKey(String id) => 'mp_answers_$id'; // CSV of student answers
String _correctKey(String id) => 'mp_correct_$id'; // CSV of correct indices
String _qtextKey(String id) => 'mp_qtext_$id'; // \u0001-joined question texts
String _optsKey(String id) => 'mp_opts_$id'; // \u0001 rows, \u0002 options
String _explKey(String id) => 'mp_expl_$id'; // \u0001-joined explanations
String _arPctKey(String id) => 'mp_arpct_$id'; // highest AR audio % reached
const _lastModuleKey = 'mp_last_module';

/// Immutable snapshot of one module's progress.
class ModuleProgress {
  final String id;
  final int bestPct; // 0..100
  final bool arWatched;

  const ModuleProgress({
    required this.id,
    this.bestPct = 0,
    this.arWatched = false,
  });

  bool get mastered => bestPct >= 100;
  bool get attempted => bestPct > 0;
}

class ModuleProgressStore {
  final SharedPreferences _prefs;
  ModuleProgressStore(this._prefs);

  // ── Reads ──────────────────────────────────────────────
  int bestPct(String id) {
    if (id.isEmpty) return 0;
    final v = _prefs.getInt(_bestKey(id)) ?? 0;
    return v.clamp(0, 100);
  }

  bool isMastered(String id) => bestPct(id) >= 100;

  bool arWatched(String id) {
    if (id.isEmpty) return false;
    return _prefs.getBool(_arSeenKey(id)) ?? false;
  }

  ModuleProgress read(String id) => ModuleProgress(
        id: id,
        bestPct: bestPct(id),
        arWatched: arWatched(id),
      );

  // ── Writes ─────────────────────────────────────────────
  /// Record a quiz result. Keeps the BEST attempt — a lower later attempt
  /// never downgrades a module that was already mastered.
  Future<void> recordQuiz(String id, int score, int total) async {
    if (id.isEmpty || total <= 0) return;
    final pct = ((score / total) * 100).round().clamp(0, 100);
    final prev = bestPct(id);
    if (pct > prev) {
      await _prefs.setInt(_bestKey(id), pct);
    }
  }

  /// Mark that the student has launched + watched this module's AR lesson once.
  /// This is what makes the quiz appear as its own list item.
  // Highest AR-narration % reached (0..100). Once ≥80, the module counts as
  // "watched" and its quiz unlocks. Monotonic — never decreases.
  int arWatchedPct(String id) {
    if (id.isEmpty) return 0;
    return (_prefs.getInt(_arPctKey(id)) ?? 0).clamp(0, 100);
  }

  Future<void> recordArProgress(String id, int pct) async {
    if (id.isEmpty) return;
    final p = pct.clamp(0, 100);
    if (p > arWatchedPct(id)) await _prefs.setInt(_arPctKey(id), p);
    if (p >= 80) await markArWatched(id);
  }

  // Persist a finished quiz attempt so a passed quiz can be re-opened in
  // read-only review without re-answering (survives relogin).
  Future<void> saveQuizAttempt({
    required String id,
    required List<int?> answers,
    required List<int> correct,
    required List<String> questionTexts,
    required List<List<String>> options,
    required List<String?> explanations,
  }) async {
    if (id.isEmpty) return;
    await _prefs.setString(
        _ansKey(id), answers.map((e) => e == null ? '' : '$e').join(','));
    await _prefs.setString(_correctKey(id), correct.join(','));
    await _prefs.setString(_qtextKey(id), questionTexts.join('\u0001'));
    await _prefs.setString(
        _optsKey(id), options.map((o) => o.join('\u0002')).join('\u0001'));
    await _prefs.setString(
        _explKey(id), explanations.map((e) => e ?? '').join('\u0001'));
  }

  bool hasSavedAttempt(String id) =>
      id.isNotEmpty && (_prefs.getString(_ansKey(id)) ?? '').isNotEmpty;

  // Returns the saved attempt for the result screen, or null if none.
  Map<String, dynamic>? readQuizAttempt(String id) {
    if (!hasSavedAttempt(id)) return null;
    final ans = (_prefs.getString(_ansKey(id)) ?? '')
        .split(',')
        .map((s) => s.isEmpty ? null : int.tryParse(s))
        .toList();
    final correct = (_prefs.getString(_correctKey(id)) ?? '')
        .split(',')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final qtexts = (_prefs.getString(_qtextKey(id)) ?? '').split('\u0001');
    final opts = (_prefs.getString(_optsKey(id)) ?? '')
        .split('\u0001')
        .map((row) => row.split('\u0002'))
        .toList();
    final expl = (_prefs.getString(_explKey(id)) ?? '').split('\u0001');
    return {
      'answers': ans,
      'correct': correct,
      'questionTexts': qtexts,
      'options': opts,
      'explanations': expl,
    };
  }

  Future<void> markArWatched(String id) async {
    if (id.isEmpty) return;
    if (_prefs.getBool(_arSeenKey(id)) == true) return;
    await _prefs.setBool(_arSeenKey(id), true);
  }

  // ── Cloud-sync export / merge ──────────────────────────────────────────────
  // Serialize ALL per-module progress into a plain map for the cloud snapshot.
  // Enumerates the mp_* keys so no module catalog is needed. Quiz ATTEMPT review
  // data (answers/options/etc.) is per-module and bundled so review survives a
  // reinstall too.
  Map<String, dynamic> exportProgress() {
    final out = <String, dynamic>{};
    for (final key in _prefs.getKeys()) {
      // Extract topicId from each known prefix.
      String? id;
      if (key.startsWith('mp_best_')) {
        id = key.substring('mp_best_'.length);
      } else if (key.startsWith('mp_arpct_')) {
        id = key.substring('mp_arpct_'.length);
      } else if (key.startsWith('mp_arseen_')) {
        id = key.substring('mp_arseen_'.length);
      }
      if (id == null || id.isEmpty) continue;
      out.putIfAbsent(id, () {
        final m = <String, dynamic>{
          'best': bestPct(id!),
          'arPct': arWatchedPct(id),
          'arSeen': arWatched(id),
        };
        // Bundle the saved quiz attempt if one exists (for review-after-restore).
        final attempt = readQuizAttempt(id);
        if (attempt != null) m['attempt'] = attempt;
        return m;
      });
    }
    return out;
  }

  // Merge a cloud snapshot into local, MAX-WINS: higher quiz %, higher AR %,
  // OR'd arSeen, and keep a quiz attempt from whichever side has one (local
  // preferred — it's the review data the student already saw).
  Future<void> mergeProgress(Map<String, dynamic> cloud) async {
    for (final entry in cloud.entries) {
      final id = entry.key;
      final m = entry.value;
      if (id.isEmpty || m is! Map) continue;

      final cBest = (m['best'] as num?)?.toInt() ?? 0;
      if (cBest > bestPct(id)) await _prefs.setInt(_bestKey(id), cBest);

      final cArPct = (m['arPct'] as num?)?.toInt() ?? 0;
      if (cArPct > arWatchedPct(id)) {
        await _prefs.setInt(_arPctKey(id), cArPct.clamp(0, 100));
      }

      if (m['arSeen'] == true) await markArWatched(id);

      // Restore a quiz attempt only if local has none (don't clobber local).
      if (!hasSavedAttempt(id) && m['attempt'] is Map) {
        final a = (m['attempt'] as Map).cast<String, dynamic>();
        try {
          final answers = (a['answers'] as List)
              .map((e) => e == null ? null : (e as num).toInt())
              .toList()
              .cast<int?>();
          final correct =
              (a['correct'] as List).map((e) => (e as num).toInt()).toList();
          final qtexts = (a['questionTexts'] as List).cast<String>();
          final opts = (a['options'] as List)
              .map((o) => (o as List).cast<String>())
              .toList();
          final expl = (a['explanations'] as List)
              .map((e) => e == null ? '' : e.toString())
              .toList();
          await saveQuizAttempt(
            id: id,
            answers: answers,
            correct: correct,
            questionTexts: qtexts,
            options: opts,
            explanations: expl.map((e) => e.isEmpty ? null : e).toList(),
          );
        } catch (_) {/* malformed cloud attempt — skip, never crash login */}
      }
    }
  }

  /// Remember the last AR lesson the student opened, so Home's "Continue
  /// Learning" card can show it with real progress. Called when a lesson opens.
  Future<void> recordOpenedModule({
    required String id,
    required String title,
    required String subject,
    required String topic,
  }) async {
    if (id.isEmpty) return;
    try {
      await _prefs.setString(
          _lastModuleKey,
          jsonEncode({
            'id': id,
            'title': title,
            'subject': subject,
            'topic': topic,
          }));
    } catch (_) {/* best-effort */}
  }

  /// The last opened module (with its live best-% merged in), or null if none.
  LastModule? readLastModule() {
    try {
      final raw = _prefs.getString(_lastModuleKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) return null;
      return LastModule(
        id: id,
        title: (m['title'] ?? '').toString(),
        subject: (m['subject'] ?? '').toString(),
        topic: (m['topic'] ?? '').toString(),
        bestPct: bestPct(id),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The most recently opened AR lesson — powers the "Continue Learning" card on
/// Home with REAL data instead of a hardcoded placeholder.
class LastModule {
  final String id;
  final String title;
  final String subject;
  final String topic;
  final int bestPct;
  const LastModule({
    required this.id,
    required this.title,
    required this.subject,
    required this.topic,
    this.bestPct = 0,
  });
}

/// Provider for the store itself (reads SharedPreferences synchronously).
final moduleProgressStoreProvider = Provider<ModuleProgressStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ModuleProgressStore(prefs);
});

/// A tiny tick that bumps whenever progress changes, so widgets watching it
/// rebuild (locks/badges refresh) without us wiring a full StateNotifier map.
final moduleProgressTickProvider = StateProvider<int>((ref) => 0);

/// The last-opened module for Home's Continue Learning card. Rebuilds when the
/// progress tick bumps (e.g. after a quiz) so the % stays fresh.
final lastModuleProvider = Provider<LastModule?>((ref) {
  ref.watch(moduleProgressTickProvider);
  return ref.watch(moduleProgressStoreProvider).readLastModule();
});
