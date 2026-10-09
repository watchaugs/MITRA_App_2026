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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ── Configuration ──────────────────────────────────────
// How often buffered events get flushed to Firestore as one batch.
const telemetryFlushInterval = Duration(hours: 6);

// Safety valve: flush immediately if a single event type piles up this
// much locally, even if the interval above hasn't elapsed yet.
const telemetryMaxBufferedPerType = 50;

const _kBoxName = 'telemetry_buffer';
const _kCheckInterval = Duration(minutes: 15);

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
  DateTime? _lastFlushAt;
  FirebaseFirestore? _db;

  Future<void> _ensureBox() async {
    _box ??= await Hive.openBox<String>(_kBoxName);
  }

  /// Starts the periodic flush check. Call once, early in app startup.
  void startScheduler({FirebaseFirestore? db}) {
    _db = db ?? FirebaseFirestore.instance;
    _checkTimer ??= Timer.periodic(_kCheckInterval, (_) => _maybeFlush());
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) _maybeFlush();
    });
  }

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
    final due = _lastFlushAt == null ||
        DateTime.now().difference(_lastFlushAt!) >= telemetryFlushInterval;
    final overCap = _box!.length >= telemetryMaxBufferedPerType;
    if (!due && !overCap) return;
    await flushNow();
  }

  /// Public so it can be triggered manually too.
  Future<void> flushNow() async {
    await _ensureBox();
    if (_isFlushing || _box!.isEmpty || _db == null) return;
    _isFlushing = true;

    try {
      final entries = _box!.toMap().entries.toList();
      final events = entries
          .map((e) =>
              MapEntry(e.key, _BufferedEvent.fromJson(jsonDecode(e.value))))
          .toList();

      // Group by (collection, studentId) — each group becomes ONE
      // Firestore document holding an array of events, instead of one
      // document per event.
      final groups = <String, List<MapEntry<dynamic, _BufferedEvent>>>{};
      for (final entry in events) {
        final k = '${entry.value.collection}::${entry.value.studentId}';
        groups.putIfAbsent(k, () => []).add(entry);
      }

      final flushedKeys = <dynamic>[];
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
        } catch (e) {
          dev.log('⚠️ Batch flush failed for $collection, will retry: $e',
              name: 'TelemetryBatch');
        }
      }

      if (flushedKeys.isNotEmpty) await _box!.deleteAll(flushedKeys);
      _lastFlushAt = DateTime.now();
    } finally {
      _isFlushing = false;
    }
  }
}
