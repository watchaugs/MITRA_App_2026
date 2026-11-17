// ═══════════════════════════════════════════════════════════════════════════
// Fun-kit progress: today's goal (up to 3 missions) and each subject hero's
// costume level. Reads what the app already stores — no new tables, no new
// server calls:
//   • lessons + quiz links: arCatalogProvider (the Learn screen's catalog)
//   • quizzes: quizFeedProvider (the Learn screen's quiz list)
//   • watched % / best quiz %: ModuleProgressStore (device prefs)
//   • XP per lesson / quiz: the achievement engine's TopicProgress (Isar)
//
// TODAY'S GOAL
//   At the first look of the day we pick up to 3 missions from what is open to
//   the student right now, following the Learn screen's own unlock chain:
//   "watch" an unlocked lesson not yet watched past the threshold, or "quiz"
//   an unlocked quiz not yet answered. The list is saved for the day, so it
//   doesn't shrink as the student finishes things. Nothing open → one
//   "revise" mission (replay a lesson or retry a quiz), so the streak can still
//   grow on a day with no new content.
//
// HERO COSTUME (per subject)
//   A subject's hero is hidden until the student opens one of its lessons or
//   answers one of its quiz questions (fun_cards.dart markEngaged).
//   subject XP = AR XP of its lessons + quiz XP of their linked quizzes.
//   Share of the subject's possible XP → costume level:
//   <20% → 0 (20% dressed), <40% → 1, <60% → 2, <80% → 3, else 4 (100%).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/achievement_models.dart';
import '../providers/translation_provider.dart';
import '../screens/student/learn_screen.dart';
import '../services/achievement_engine.dart';
import '../stores/module_progress_store.dart';
import '../theme/theme_provider.dart'; // sharedPreferencesProvider
import 'fun_cards.dart'; // engagedIds, CardStore, cardTickProvider

const int kGoalCap = 3;
const int kArXp = 20, kQuizXp = 50; // per lesson / quiz (achievement engine)

int todayYmd() {
  final n = DateTime.now();
  return n.year * 10000 + n.month * 100 + n.day;
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

enum MissionKind { watch, quiz, revise }

class Mission {
  final MissionKind kind;
  final String id; // lesson id (watch) or quiz id (quiz); '' for revise
  final String title;
  final String subject;
  const Mission(this.kind, this.id, this.title, this.subject);

  Map<String, dynamic> toJson() =>
      {'k': kind.name, 'id': id, 't': title, 's': subject};
  static Mission fromJson(Map m) => Mission(
        MissionKind.values.firstWhere((k) => k.name == m['k'],
            orElse: () => MissionKind.revise),
        (m['id'] ?? '').toString(),
        (m['t'] ?? '').toString(),
        (m['s'] ?? '').toString(),
      );
}

/// Everything open to the student right now, in Learn-screen order.
List<Mission> openMissions({
  required ArCatalog catalog,
  required List<QuizSummary> quizzes,
  required ModuleProgressStore progress,
  required int threshold,
}) {
  final out = <Mission>[];
  for (final e in catalog.bySubject.entries) {
    final subject = e.key;
    final lessons = e.value.where((l) => !l.locked).toList();
    final subjQuizzes = quizzes.where((q) => q.subject == subject).toList();
    final byId = {for (final q in subjQuizzes) q.id: q};
    final byTopic = <String, QuizSummary>{};
    for (final q in subjQuizzes) {
      final k = _norm(q.topic);
      if (k.isNotEmpty) byTopic.putIfAbsent(k, () => q);
    }
    // Same matching as the Learn screen: tree link, then id, then topic.
    QuizSummary? quizFor(ArLessonRec ar) {
      for (final qid in catalog.quizIdsByArId[ar.id] ?? const <String>[]) {
        final q = byId[qid];
        if (q != null) return q;
      }
      return byId[ar.id] ?? byTopic[_norm(ar.topic)];
    }

    bool prevMastered = true;
    for (int i = 0; i < lessons.length; i++) {
      final ar = lessons[i];
      final unlocked = i == 0 || prevMastered;
      final quiz = quizFor(ar);
      final watched = progress.arWatchedPct(ar.id) >= threshold;
      if (unlocked) {
        if (!watched) {
          out.add(Mission(MissionKind.watch, ar.id, ar.title, subject));
        } else if (quiz != null &&
            progress.bestPct(quiz.id) == 0 &&
            !progress.hasSavedAttempt(quiz.id)) {
          out.add(Mission(MissionKind.quiz, quiz.id, ar.title, subject));
        }
      }
      prevMastered = quiz != null ? progress.isMastered(quiz.id) : watched;
    }
  }
  return out;
}

class DailyGoal {
  final int ymd;
  final List<Mission> missions;
  final List<bool> done;
  const DailyGoal(this.ymd, this.missions, this.done);

  int get total => missions.length;
  int get doneCount => done.where((d) => d).length;
  bool get complete => total > 0 && doneCount >= total;
}

const _kGoalDay = 'fun_goal_day';
const _kGoalItems = 'fun_goal_items';
const _kGoalCelebrated = 'fun_goal_celebrated';
const kLastActiveKey = 'mp_last_active_ymd'; // written by ModuleProgressStore

/// Today's goal. Null until the lesson catalog has loaded.
final dailyGoalProvider = Provider<DailyGoal?>((ref) {
  ref.watch(moduleProgressTickProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final progress = ref.watch(moduleProgressStoreProvider);
  final catalog = ref.watch(arCatalogProvider).valueOrNull;
  if (catalog == null) return null;
  final threshold = ref
      .watch(arWatchThresholdProvider)
      .maybeWhen(data: (v) => v, orElse: () => 85);
  final lang = ref.watch(translationProvider).langCode;
  final quizzes = (ref
              .watch(quizFeedProvider(ref.watch(quizFilterParamsProvider)))
              .valueOrNull ??
          const <QuizSummary>[])
      .where((q) => q.languageTag == lang || q.languageTag == 'all')
      .toList();

  final today = todayYmd();
  List<Mission> missions;
  if (prefs.getInt(_kGoalDay) == today) {
    try {
      final raw = jsonDecode(prefs.getString(_kGoalItems) ?? '[]') as List;
      missions = raw.whereType<Map>().map(Mission.fromJson).toList();
    } catch (_) {
      missions = const [];
    }
  } else {
    final open = openMissions(
        catalog: catalog,
        quizzes: quizzes,
        progress: progress,
        threshold: threshold);
    missions = open.isEmpty
        ? const [Mission(MissionKind.revise, '', '', '')]
        : open.take(kGoalCap).toList();
    prefs.setInt(_kGoalDay, today);
    prefs.setString(
        _kGoalItems, jsonEncode(missions.map((m) => m.toJson()).toList()));
  }

  final activeToday = prefs.getInt(kLastActiveKey) == today;
  final done = missions.map((m) {
    switch (m.kind) {
      case MissionKind.watch:
        return progress.arWatchedPct(m.id) >= threshold;
      case MissionKind.quiz:
        return progress.bestPct(m.id) > 0 || progress.hasSavedAttempt(m.id);
      case MissionKind.revise:
        return activeToday;
    }
  }).toList();
  return DailyGoal(today, missions, done);
});

/// True once per day, the first time today's goal is seen complete.
bool takeGoalCelebration(SharedPreferences prefs, DailyGoal g) {
  if (!g.complete) return false;
  if (prefs.getInt(_kGoalCelebrated) == g.ymd) return false;
  prefs.setInt(_kGoalCelebrated, g.ymd);
  return true;
}

// ── Hero costume per subject ────────────────────────────────────────────────
class SubjectHeroProgress {
  final String subject;
  final int xp, maxXp;

  /// false until the student opens a lesson or answers a quiz question in
  /// this subject. A hidden hero is not shown anywhere.
  final bool engaged;
  const SubjectHeroProgress(this.subject, this.xp, this.maxXp,
      {this.engaged = false});

  double get share => maxXp <= 0 ? 0 : (xp / maxXp).clamp(0.0, 1.0);
  int get level => share < .2
      ? 0
      : share < .4
          ? 1
          : share < .6
              ? 2
              : share < .8
                  ? 3
                  : 4;
}

/// subject → hero progress, for every subject in the lesson catalog.
final subjectHeroProgressProvider =
    FutureProvider<Map<String, SubjectHeroProgress>>((ref) async {
  ref.watch(studentProfileProvider); // recompute whenever XP changes
  final catalog = ref.watch(arCatalogProvider).valueOrNull;
  if (catalog == null) return const {};
  ref.watch(cardTickProvider); // a lesson opened / page scanned
  ref.watch(moduleProgressTickProvider); // a quiz finished
  final prefs = ref.watch(sharedPreferencesProvider);
  final mps = ref.watch(moduleProgressStoreProvider);
  final opened = engagedIds(prefs);
  final scanned = CardStore(prefs).unlocked;
  final isar = ref.watch(isarProvider);
  final rows = await isar.collection<TopicProgress>().where().findAll();
  final byTopic = {for (final r in rows) r.topicId: r};
  // Older activity counts too, so students who used the app before this
  // update see their heroes straight away.
  bool lessonTouched(String id) =>
      opened.contains(id) ||
      scanned.containsKey(id) ||
      mps.arWatched(id) ||
      mps.arWatchedPct(id) > 0 ||
      (byTopic[id]?.arXpEarned ?? 0) > 0;
  bool quizTouched(String id) =>
      opened.contains(id) ||
      mps.hasSavedAttempt(id) ||
      mps.bestPct(id) > 0 ||
      (byTopic[id]?.quizXpEarned ?? 0) > 0;
  final out = <String, SubjectHeroProgress>{};
  for (final e in catalog.bySubject.entries) {
    int xp = 0, max = 0;
    bool engaged = false;
    for (final l in e.value) {
      final qids = catalog.quizIdsByArId[l.id] ?? const <String>[];
      if (!engaged) engaged = lessonTouched(l.id) || qids.any(quizTouched);
      if (l.locked) continue;
      max += kArXp;
      xp += math.min(byTopic[l.id]?.arXpEarned ?? 0, kArXp);
      for (final qid in qids) {
        max += kQuizXp;
        xp += math.min(byTopic[qid]?.quizXpEarned ?? 0, kQuizXp);
      }
    }
    out[e.key] = SubjectHeroProgress(e.key, xp, max, engaged: engaged);
  }
  return out;
});

/// Subjects whose hero the student has met (opened a lesson or answered a
/// quiz question there), in catalog order. Other heroes stay hidden.
final metSubjectsProvider = Provider<List<String>>((ref) {
  final prog = ref.watch(subjectHeroProgressProvider).valueOrNull ?? const {};
  final subjects = ref.watch(arCatalogProvider).valueOrNull?.bySubject.keys ??
      const <String>[];
  return subjects.where((s) => prog[s]?.engaged ?? false).toList();
});

/// Streak milestones for the power meter: 7, 30, 100, then every 100.
int nextStreakMilestone(int streak) {
  if (streak < 7) return 7;
  if (streak < 30) return 30;
  if (streak < 100) return 100;
  return ((streak ~/ 100) + 1) * 100;
}

int prevStreakMilestone(int streak) {
  if (streak < 7) return 0;
  if (streak < 30) return 7;
  if (streak < 100) return 30;
  return (streak ~/ 100) * 100;
}
