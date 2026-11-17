// ═══════════════════════════════════════════════════════════════════════════
// Hero cards + this week's counts — saved on the phone (SharedPreferences),
// like the rest of the student's progress. No new server tables.
//
// Hero cards: scanning a lesson's textbook page (page found in the scanner)
// unlocks that lesson's card once. Card title/subject come from the lesson
// catalog when shown, so only { lessonId: day } is stored.
//
// Week counts (for the parent card): lessons finished and quizzes tried this
// week (Monday start). ModuleProgressStore bumps them when it happens.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_provider.dart'; // sharedPreferencesProvider

const _kCards = 'fun_cards'; // JSON { lessonId: yyyymmdd }
const _kCardsSeen = 'fun_cards_seen'; // list of ids already viewed in the album
const _kWeek = 'fun_wk_start'; // yyyymmdd of this week's Monday
const _kWeekLessons = 'fun_wk_lessons';
const _kWeekQuizzes = 'fun_wk_quizzes';

int _ymd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// Monday of the current week, as yyyymmdd.
int weekStartYmd([DateTime? now]) {
  final n = now ?? DateTime.now();
  final d =
      DateTime(n.year, n.month, n.day).subtract(Duration(days: n.weekday - 1));
  return _ymd(d);
}

class CardStore {
  final SharedPreferences _prefs;
  CardStore(this._prefs);

  /// lessonId → day unlocked (yyyymmdd).
  Map<String, int> get unlocked {
    try {
      final m = jsonDecode(_prefs.getString(_kCards) ?? '{}') as Map;
      return m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Set<String> get seen =>
      (_prefs.getStringList(_kCardsSeen) ?? const []).toSet();

  bool has(String id) => unlocked.containsKey(id);

  /// Unlocks the card. Returns true only the first time.
  Future<bool> unlock(String id) async {
    if (id.isEmpty) return false;
    final m = unlocked;
    if (m.containsKey(id)) return false;
    m[id] = _ymd(DateTime.now());
    await _prefs.setString(_kCards, jsonEncode(m));
    return true;
  }

  Future<void> markAllSeen() async {
    await _prefs.setStringList(_kCardsSeen, unlocked.keys.toList());
  }

  int unlockedThisWeek() {
    final w = weekStartYmd();
    return unlocked.values.where((d) => d >= w).length;
  }
}

/// This week's counters (reset automatically each Monday).
class WeekCounts {
  final SharedPreferences _prefs;
  WeekCounts(this._prefs);

  bool get _current => _prefs.getInt(_kWeek) == weekStartYmd();
  int get lessons => _current ? (_prefs.getInt(_kWeekLessons) ?? 0) : 0;
  int get quizzes => _current ? (_prefs.getInt(_kWeekQuizzes) ?? 0) : 0;

  Future<void> _roll() async {
    if (_current) return;
    await _prefs.setInt(_kWeek, weekStartYmd());
    await _prefs.setInt(_kWeekLessons, 0);
    await _prefs.setInt(_kWeekQuizzes, 0);
  }

  Future<void> addLesson() async {
    await _roll();
    await _prefs.setInt(_kWeekLessons, (_prefs.getInt(_kWeekLessons) ?? 0) + 1);
  }

  Future<void> addQuiz() async {
    await _roll();
    await _prefs.setInt(_kWeekQuizzes, (_prefs.getInt(_kWeekQuizzes) ?? 0) + 1);
  }
}

/// Bumped when a card is unlocked or viewed, so the album/HQ rebuild.
final cardTickProvider = StateProvider<int>((ref) => 0);

// ── Hero visibility ──
// A subject's hero stays hidden until the student opens one of its lessons
// or answers one of its quiz questions. The ids opened are kept here.
const _kEngaged = 'fun_engaged';

Set<String> engagedIds(SharedPreferences prefs) =>
    (prefs.getStringList(_kEngaged) ?? const <String>[]).toSet();

/// Marks a lesson or quiz id as opened. Safe to call from initState.
Future<void> markEngaged(WidgetRef ref, String id) async {
  if (id.isEmpty) return;
  final prefs = ref.read(sharedPreferencesProvider);
  final tick = ref.read(cardTickProvider.notifier);
  final ids = engagedIds(prefs);
  if (!ids.add(id)) return;
  await prefs.setStringList(_kEngaged, ids.toList());
  tick.state++;
}

final cardStoreProvider = Provider<CardStore>((ref) {
  ref.watch(cardTickProvider);
  return CardStore(ref.watch(sharedPreferencesProvider));
});
