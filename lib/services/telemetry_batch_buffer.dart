// ═══════════════════════════════════════════════════════
// TelemetryBatchBuffer — buffers telemetry events locally
// (Hive) and periodically flushes them to Firestore as ONE
// batched document per event-type, instead of writing a new
// Firestore document for every single event immediately.
//
// TelemetryService._write() routes through this, so it
// protects every current AND future telemetry call site.
// ═══════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Configuration ──────────────────────────────────────
// TWO TIERS, matching the consolidation policy:
//   • CRITICAL events (legal/consent + session boundaries) sync fast, so
//     the dashboard's compliance + usage view is never >1 day stale.
//   • BULK behavioural events (AR views, screen views, notifications) ride
//     the 10-day + compulsory month-end cadence, same as quizzes, to cut
//     write cost at scale.
const telemetryCriticalInterval = Duration(hours: 12);
const telemetryBulkInterval = Duration(days: 10);

// Collections treated as CRITICAL (everything else is BULK).
const _kCriticalCollections = <String>{
  'compliance_events',
  'profile_events',
  'sessions',
};

// Safety valve: flush a type immediately if it piles up this much locally,
// regardless of tier or interval (prevents unbounded on-device growth / loss).
const telemetryMaxBufferedPerType = 50;

// Month-end consolidation: each device picks a stable random offset inside
// the last 48h of the month, so the compulsory sync spreads out across ~2
// days instead of every device hitting Firestore at 23:59 on the last day.
const _kMonthEndWindowHours = 48;

const _kBoxName = 'telemetry_buffer';
const _kCheckInterval = Duration(minutes: 15);

// Persisted keys (SharedPreferences) so cadence survives app restarts.
const _kLastBulkFlushKey = 'telemetry_last_bulk_flush_at';
const _kLastMonthEndTagKey = 'telemetry_last_monthend_tag';
const _kMonthEndJitterKey = 'telemetry_monthend_jitter_min';

class _BufferedEvent {
  final String collection;
  final String studentId;
  final Map<String, dynamic> data;

  _BufferedEvent(
      {required this.collection, required this.studentId, required this.data});

  Map<String, dynamic> toJson() =>
      {'collection': collection, 'studentId': studentId, 'data': data};

  factory _BufferedEvent.fromJson(Map<String, dynamic> json) => _BufferedEvent(
        collection: json['collection'] as String,
        studentId: json['studentId'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map),
      );
}

class TelemetryBatchBuffer {
  TelemetryBatchBuffer._();
  static final TelemetryBatchBuffer instance = TelemetryBatchBuffer._();

  Box<String>? _box;
  Timer? _checkTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isFlushing = false;
  DateTime? _lastBulkFlushAt; // last time the BULK tier was flushed
  FirebaseFirestore? _db;

  Future<void> _ensureBox() async {
    _box ??= await Hive.openBox<String>(_kBoxName);
  }

  // True if a collection is in the fast "critical" tier.
  bool _isCritical(String collection) =>
      _kCriticalCollections.contains(collection);

  /// Starts the periodic flush check. Call once, early in app startup.
  Future<void> startScheduler({FirebaseFirestore? db}) async {
    _db = db ?? FirebaseFirestore.instance;

    // Restore the last BULK flush time so a 10-day cadence survives restarts.
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_kLastBulkFlushKey);
      if (s != null) _lastBulkFlushAt = DateTime.tryParse(s);
    } catch (_) {/* best-effort */}

    _checkTimer ??= Timer.periodic(_kCheckInterval, (_) => _maybeFlush());
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) _maybeFlush();
    });
  }

  /// Flush just the critical tier now — call this on app background/close so
  /// legal + session data is never left sitting locally for long.
  Future<void> flushCriticalNow() => flushNow(tier: Tier.critical);

  /// Called by TelemetryService._write() instead of hitting Firestore
  /// directly — purely local, no network.
  Future<void> buffer({
    required String collection,
    required String studentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureBox();
    final event = _BufferedEvent(
        collection: collection, studentId: studentId, data: data);
    final key = '${DateTime.now().microsecondsSinceEpoch}_${_box!.length}';
    await _box!.put(key, jsonEncode(event.toJson()));

    final countForType = _box!.values
        .where((v) => jsonDecode(v)['collection'] == collection)
        .length;
    if (countForType >= telemetryMaxBufferedPerType) {
      unawaited(_maybeFlush());
    }
  }

  Future<void> _maybeFlush() async {
    await _ensureBox();
    if (_isFlushing || _box!.isEmpty) return;

    final now = DateTime.now();

    // ── CRITICAL tier: flush every 12h (fast), or sooner if anything piled up.
    final hasCritical = _box!.values.any((v) {
      try {
        return _isCritical(jsonDecode(v)['collection'] as String);
      } catch (_) {
        return false;
      }
    });
    if (hasCritical) {
      final criticalDue = _lastBulkFlushAt == null // reuse-safe clock reference
          ? true
          : true; // critical has no persisted clock; cadence is driven below
      // Critical is flushed on every scheduler tick that finds critical data,
      // but throttled to the 12h interval via its own in-memory stamp.
      if (criticalDue && _criticalDue(now)) {
        await flushNow(tier: Tier.critical);
      }
    }

    // ── BULK tier: 10-day cadence OR compulsory (jittered) month-end.
    final bulkDueByTime = _lastBulkFlushAt == null ||
        now.difference(_lastBulkFlushAt!) >= telemetryBulkInterval;
    final bulkDueByMonthEnd = await _isMonthEndDue(now);
    final overCap = _box!.length >= telemetryMaxBufferedPerType;

    if (bulkDueByTime || bulkDueByMonthEnd || overCap) {
      await flushNow(tier: Tier.bulk);
      if (bulkDueByMonthEnd) await _markMonthEndDone(now);
    }
  }

  // In-memory 12h throttle for the critical tier.
  DateTime? _lastCriticalFlushAt;
  bool _criticalDue(DateTime now) {
    if (_lastCriticalFlushAt == null) return true;
    return now.difference(_lastCriticalFlushAt!) >= telemetryCriticalInterval;
  }

  // ── Jittered month-end logic ───────────────────────────────────────────────
  // Each device gets a STABLE random offset (0..48h) stored once. The month-end
  // sync fires when we're inside [lastDay 00:00 - jitter ... month end], so the
  // fleet spreads its compulsory sync across the final ~2 days of the month.
  Future<int> _monthEndJitterMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getInt(_kMonthEndJitterKey);
      if (existing != null) return existing;
      final jitter =
          Random().nextInt(_kMonthEndWindowHours * 60); // 0..2879 min
      await prefs.setInt(_kMonthEndJitterKey, jitter);
      return jitter;
    } catch (_) {
      return 0; // best-effort → behaves like strict last-day
    }
  }

  Future<bool> _isMonthEndDue(DateTime now) async {
    // Last day of the current month at 23:59.
    final firstNextMonth = (now.month == 12)
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    final monthEnd = firstNextMonth.subtract(const Duration(minutes: 1));

    final jitterMin = await _monthEndJitterMinutes();
    // Window opens jitter-minutes before the end of the last day.
    final windowOpen = monthEnd.subtract(Duration(minutes: jitterMin));
    if (now.isBefore(windowOpen)) return false;

    // Only once per month.
    final tag = '${now.year}-${now.month}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kLastMonthEndTagKey) == tag) return false;
    } catch (_) {/* if prefs fails, allow it — better to sync than skip */}
    return true;
  }

  Future<void> _markMonthEndDone(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastMonthEndTagKey, '${now.year}-${now.month}');
    } catch (_) {/* best-effort */}
  }

  /// Public so it can be triggered manually too.
  /// [tier] selects which events to send. `_Tier.all` sends everything (used by
  /// manual/force flushes); the scheduler passes `critical` or `bulk`.
  Future<void> flushNow({Tier tier = Tier.all}) async {
    await _ensureBox();
    if (_isFlushing || _box!.isEmpty || _db == null) return;
    _isFlushing = true;

    try {
      final entries = _box!.toMap().entries.toList();
      final events = entries
          .map((e) =>
              MapEntry(e.key, _BufferedEvent.fromJson(jsonDecode(e.value))))
          .where((e) => _tierMatches(tier, e.value.collection))
          .toList();

      if (events.isEmpty) return;

      // Group by (collection, studentId) — each group becomes ONE
      // Firestore document holding an array of events, instead of one
      // document per event.
      final groups = <String, List<MapEntry<dynamic, _BufferedEvent>>>{};
      for (final entry in events) {
        final k = '${entry.value.collection}::${entry.value.studentId}';
        groups.putIfAbsent(k, () => []).add(entry);
      }

      final flushedKeys = <dynamic>[];
      var anyCriticalFlushed = false;
      var anyBulkFlushed = false;
      for (final group in groups.values) {
        final collection = group.first.value.collection;
        final studentId = group.first.value.studentId;
        try {
          await _db!
              .collection('telemetry_sync')
              .doc(studentId)
              .collection(collection)
              .add({
            'batched_events': group.map((e) => e.value.data).toList(),
            'event_count': group.length,
            'batch_flushed_at': DateTime.now().toIso8601String(),
            'processed': false,
          });
          flushedKeys.addAll(group.map((e) => e.key));
          if (_isCritical(collection)) {
            anyCriticalFlushed = true;
          } else {
            anyBulkFlushed = true;
          }
        } catch (e) {
          dev.log('⚠️ Batch flush failed for $collection, will retry: $e',
              name: 'TelemetryBatch');
        }
      }

      if (flushedKeys.isNotEmpty) await _box!.deleteAll(flushedKeys);

      final now = DateTime.now();
      if (anyCriticalFlushed) _lastCriticalFlushAt = now;
      if (anyBulkFlushed) {
        _lastBulkFlushAt = now;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kLastBulkFlushKey, now.toIso8601String());
        } catch (_) {/* best-effort */}
      }
    } finally {
      _isFlushing = false;
    }
  }

  // Does this collection belong in the tier currently being flushed?
  bool _tierMatches(Tier tier, String collection) {
    switch (tier) {
      case Tier.all:
        return true;
      case Tier.critical:
        return _isCritical(collection);
      case Tier.bulk:
        return !_isCritical(collection);
    }
  }
}

// Which slice of buffered events a flush should send.
enum Tier { all, critical, bulk }
