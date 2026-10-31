// ═══════════════════════════════════════════════════════
// MITRA — Quiz Pack Store (download once, read locally)
// ═══════════════════════════════════════════════════════
//
// Quiz questions/answers/explanations are FIXED for the whole year. So instead
// of fetching questions over the network on every attempt (big egress at lakhs
// of DAU), the app downloads ONE pack per state from the dashboard, writes it to
// a file on the device, and reads every quiz from that local file thereafter.
// Only the RESULTS sync back, through the existing batched QuizOfflineService.
//
// Flow:
//   ensurePack(state)  → if the local file is missing, download /api/quiz/pack/
//                        <state> once and save it. Does nothing if already saved.
//   questionsFor(id)   → read the cached pack from disk and return that quiz's
//                        questions (empty list if the quiz isn't in the pack).
//
// Because the content is yearly-fixed, there is no periodic refresh. The pack is
// re-downloaded only if the file is missing (fresh install / cleared data), or
// when refresh(state) is called explicitly after you publish new content.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/quiz_model.dart';
import '../services/api_service.dart';

class QuizPackStore {
  QuizPackStore._();
  static final QuizPackStore instance = QuizPackStore._();

  Map<String, dynamic>? _memory; // parsed pack held in memory for the session

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/quiz_packs');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return File('${folder.path}/pack.json');
  }

  /// Download the pack once if we don't already have it on the device.
  /// Safe to call on every launch — it only hits the network when the local
  /// file is missing.
  Future<void> ensurePack(String state) async {
    try {
      final f = await _file();
      if (f.existsSync() && f.lengthSync() > 2) {
        _memory ??= _safeDecode(await f.readAsString());
        if (_memory != null) return; // already have a usable pack
      }
      await _download(state);
    } catch (_) {
      // Offline or server error: leave whatever (if anything) is cached. The
      // quiz screen handles an empty pack with a clean empty state.
    }
  }

  /// Force a fresh download (e.g. after the dashboard publishes new content).
  Future<void> refresh(String state) async {
    try {
      await _download(state);
    } catch (_) {}
  }

  Future<void> _download(String state) async {
    final res = await QuizAPI.pack(state);
    if (res.data is Map) {
      final map = Map<String, dynamic>.from(res.data as Map);
      _memory = map;
      final f = await _file();
      await f.writeAsString(jsonEncode(map));
    }
  }

  Map<String, dynamic>? _safeDecode(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    if (_memory != null) return _memory;
    final f = await _file();
    if (!f.existsSync()) return null;
    _memory = _safeDecode(await f.readAsString());
    return _memory;
  }

  /// Questions for one quiz id, read from the local pack. Returns an empty list
  /// when the pack is missing or the quiz isn't in it (→ clean empty state).
  Future<List<QuizQuestion>> questionsFor(String quizId) async {
    final pack = await _load();
    if (pack == null) return const [];
    final quizzes = pack['quizzes'];
    if (quizzes is! List) return const [];
    for (final q in quizzes) {
      if (q is! Map) continue;
      if ((q['id'] ?? '').toString() != quizId) continue;
      final raw = q['questions'];
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((m) {
        final opts = (m['options'] is List)
            ? List<String>.from(
                (m['options'] as List).map((o) => (o ?? '').toString()))
            : <String>[];
        // Pad to 4 options so the UI never indexes out of range.
        while (opts.length < 4) {
          opts.add('');
        }
        // Accept every field name the dashboard/backend may use for the answer
        // index (correct_answer_index is the canonical one; others are legacy).
        // An old app must not silently default every question to "A".
        dynamic rawCi = m['correct_answer_index'] ??
            m['correct_index'] ??
            m['correctIndex'] ??
            m['answer_index'];
        int ci;
        if (rawCi is int) {
          ci = rawCi;
        } else {
          ci = int.tryParse('${rawCi ?? ''}') ?? -1;
          // Also accept a letter answer ('A'..'D').
          if (ci < 0) {
            final letter =
                '${m['answer'] ?? m['correct'] ?? ''}'.trim().toUpperCase();
            final li = ['A', 'B', 'C', 'D'].indexOf(letter);
            ci = li >= 0 ? li : 0;
          }
        }
        return QuizQuestion(
          questionText: (m['question_text'] ?? '').toString(),
          options: opts,
          correctAnswerIndex: (ci >= 0 && ci < opts.length) ? ci : 0,
          explanation: (m['explanation'] ?? '').toString().isEmpty
              ? null
              : m['explanation'].toString(),
        );
      }).toList();
    }
    return const [];
  }
}

final quizPackStoreProvider =
    Provider<QuizPackStore>((ref) => QuizPackStore.instance);
