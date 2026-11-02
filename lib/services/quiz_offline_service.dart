// ═══════════════════════════════════════════════════════
// QuizOfflineService — records quiz results locally (SQLite)
// instead of sending them to the server immediately. A
// background scheduler batches everything unsynced into ONE
// network request on a schedule, instead of one request per
// quiz submission.
// ═══════════════════════════════════════════════════════

import 'dart:async';
import 'dart:developer' as dev;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';

// ── Configuration ──────────────────────────────────────
// Routine batched sync cadence. Per the data-collection design, usage/analytics
// are consolidated every 10 days, PLUS a compulsory sync on the last day of the
// month (see _isMonthEndDue) for month-end submission.
const quizSyncInterval = Duration(days: 10);

// Safety valve: sync immediately if this many attempts pile up locally,
// even if the interval above hasn't elapsed yet.
const quizSyncMaxQueuedAttempts = 30;

const _kLastSyncPrefsKey = 'quiz_last_sync_at';
const _kCheckInterval = Duration(hours: 1); // how often we check the clock

// ── Local SQLite storage ───────────────────────────────
class QuizOfflineDb {
  QuizOfflineDb._();
  static final QuizOfflineDb instance = QuizOfflineDb._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'mitra_quiz_attempts.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE quiz_attempts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quiz_id TEXT NOT NULL,
          student_id TEXT NOT NULL,
          state TEXT,
          district TEXT,
          class_grade TEXT,
          score INTEGER NOT NULL,
          max_score INTEGER NOT NULL,
          questions_attempted INTEGER NOT NULL,
          correct_answers INTEGER NOT NULL,
          time_taken_secs INTEGER NOT NULL,
          app_language TEXT,
          completed_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
    return _db!;
  }

  /// Called right when a quiz is submitted — purely local, no network.
  Future<void> recordAttempt({
    required String quizId,
    required String studentId,
    required String state,
    required String district,
    required String classGrade,
    required int score,
    required int maxScore,
    required int questionsAttempted,
    required int correctAnswers,
    required int timeTakenSecs,
    required String appLanguage,
  }) async {
    final db = await _database;
    await db.insert('quiz_attempts', {
      'quiz_id': quizId,
      'student_id': studentId,
      'state': state,
      'district': district,
      'class_grade': classGrade,
      'score': score,
      'max_score': maxScore,
      'questions_attempted': questionsAttempted,
      'correct_answers': correctAnswers,
      'time_taken_secs': timeTakenSecs,
      'app_language': appLanguage,
      'completed_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsynced() async {
    final db = await _database;
    return db.query('quiz_attempts', where: 'synced = 0');
  }

  Future<int> unsyncedCount() async {
    final db = await _database;
    final result = await db
        .rawQuery('SELECT COUNT(*) AS c FROM quiz_attempts WHERE synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Deletes rows once the server has confirmed receiving them.
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete('quiz_attempts',
        where: 'id IN ($placeholders)', whereArgs: ids);
  }
}

// ── Sync state ──────────────────────────────────────────
enum QuizSyncStatus { idle, syncing, error }

class QuizSyncState {
  final QuizSyncStatus status;
  final DateTime? lastSyncAt;
  final int unsyncedCount;
  const QuizSyncState({
    this.status = QuizSyncStatus.idle,
    this.lastSyncAt,
    this.unsyncedCount = 0,
  });

  QuizSyncState copyWith({
    QuizSyncStatus? status,
    DateTime? lastSyncAt,
    int? unsyncedCount,
  }) =>
      QuizSyncState(
        status: status ?? this.status,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        unsyncedCount: unsyncedCount ?? this.unsyncedCount,
      );
}

// ── Sync notifier — self-initializing, checks the clock hourly,
//    and actually syncs once a day (or sooner if the queue is full) ──
class QuizSyncNotifier extends StateNotifier<QuizSyncState> {
  Timer? _checkTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  QuizSyncNotifier() : super(const QuizSyncState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString(_kLastSyncPrefsKey);
    final lastSync =
        lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;
    state = state.copyWith(lastSyncAt: lastSync);

    _checkTimer = Timer.periodic(_kCheckInterval, (_) => _maybeSync());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) _maybeSync();
    });

    unawaited(_maybeSync());
  }

  Future<void> _maybeSync() async {
    if (_isSyncing) return;

    final unsynced = await QuizOfflineDb.instance.unsyncedCount();
    state = state.copyWith(unsyncedCount: unsynced);
    if (unsynced == 0) return;

    final dueByCap = unsynced >= quizSyncMaxQueuedAttempts;
    final dueByTime = state.lastSyncAt == null ||
        DateTime.now().difference(state.lastSyncAt!) >= quizSyncInterval;

    // Compulsory month-end consolidation: on the LAST day of the month, force a
    // sync so the state's monthly submission is complete, even if the 10-day
    // timer hasn't elapsed. Guarded so it fires at most once per month-end day.
    final dueByMonthEnd = _isMonthEndDue();

    if (!dueByCap && !dueByTime && !dueByMonthEnd) return;

    await _syncNow();
  }

  // True only on the last calendar day of the month, and only if we haven't
  // already done the month-end sync for this month (tracked in prefs so it
  // doesn't re-fire every hourly check on the 31st).
  bool _isMonthEndDue() {
    final now = DateTime.now();
    // The last day of THIS month: day 0 of next month rolls back to it.
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    if (now.day != lastDay) return false;
    final tag = '${now.year}-${now.month}'; // e.g. "2026-11"
    if (_lastMonthEndSyncTag == tag)
      return false; // already synced this month-end
    _lastMonthEndSyncTag = tag;
    return true;
  }

  // Remembers the month we last did the compulsory month-end sync for.
  String? _lastMonthEndSyncTag;

  Future<void> _syncNow() async {
    _isSyncing = true;
    state = state.copyWith(status: QuizSyncStatus.syncing);
    try {
      final rows = await QuizOfflineDb.instance.getUnsynced();
      if (rows.isEmpty) {
        state = state.copyWith(status: QuizSyncStatus.idle);
        return;
      }

      final payload = rows
          .map((r) => {
                'quiz_id': r['quiz_id'],
                'student_id': r['student_id'],
                'state': r['state'],
                'district': r['district'],
                'class_grade': r['class_grade'],
                'score': r['score'],
                'max_score': r['max_score'],
                'questions_attempted': r['questions_attempted'],
                'correct_answers': r['correct_answers'],
                'time_taken_secs': r['time_taken_secs'],
                'app_language': r['app_language'],
                'completed_at': r['completed_at'],
              })
          .toList();

      await QuizAPI.submitBatch(payload);

      final ids = rows.map((r) => r['id'] as int).toList();
      await QuizOfflineDb.instance.deleteByIds(ids);

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastSyncPrefsKey, now.toIso8601String());

      state = state.copyWith(
        status: QuizSyncStatus.idle,
        lastSyncAt: now,
        unsyncedCount: 0,
      );
      dev.log('✅ Synced ${rows.length} quiz attempts', name: 'QuizSync');
    } catch (e) {
      // Left unsynced on disk — the next scheduled check (or the next
      // time connectivity comes back) retries automatically.
      state = state.copyWith(status: QuizSyncStatus.error);
      dev.log('⚠️ Quiz batch sync failed, will retry: $e', name: 'QuizSync');
    } finally {
      _isSyncing = false;
    }
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}

final quizSyncProvider = StateNotifierProvider<QuizSyncNotifier, QuizSyncState>(
    (ref) => QuizSyncNotifier());
