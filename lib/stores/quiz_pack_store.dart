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
//
// Picture rounds: after a download, every quiz picture is saved next to the
// pack (quiz_packs/img/) so picture rounds work offline. A pack saved by an
// older app version (no picture / sequence rounds) is replaced once, online.
//
// The pack remembers which state it was downloaded for. When a different
// state's student signs in on the same phone (or a student's state changes),
// that state's pack is downloaded instead of reusing the other one.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/quiz_model.dart';
import '../services/api_service.dart';

class QuizPackStore {
  QuizPackStore._();
  static final QuizPackStore instance = QuizPackStore._();

  Map<String, dynamic>? _memory; // parsed pack held in memory for the session

  /// Pack format this app writes. 2 = includes picture / sequence rounds.
  static const int _kFmt = 2;
  String? _imgDir; // quiz_packs/img, known after the first _file() call
  bool _imagesChecked = false; // once per session

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/quiz_packs');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    _imgDir ??= '${folder.path}/img';
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
        // Already have a usable pack from this app version, for this state.
        if (_memory != null &&
            (_memory!['fmt'] ?? 0) == _kFmt &&
            '${_memory!['for_state'] ?? ''}' == state) {
          if (!_imagesChecked) {
            _imagesChecked = true;
            unawaited(
                _cacheImages(_memory!)); // fetch any picture missed offline
          }
          return;
        }
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
      map['fmt'] = _kFmt;
      map['for_state'] = state;
      _memory = map;
      final f = await _file();
      await f.writeAsString(jsonEncode(map));
      _imagesChecked = true;
      unawaited(_cacheImages(map));
    }
  }

  // ── Quiz pictures (picture rounds) ──────────────────────────────────────────
  static String _abs(String url) {
    final u = url.trim();
    if (u.isEmpty || u.startsWith('http://') || u.startsWith('https://')) {
      return u;
    }
    final base =
        ApiService.instance.dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base${u.startsWith('/') ? u : '/$u'}';
  }

  // Stable file name for a picture URL (FNV-1a hash + length).
  static String _imgName(String url) {
    int h = 0x811c9dc5;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    final ext = RegExp(r'\.(jpg|jpeg|png|webp)(\?|$)', caseSensitive: false)
            .firstMatch(url)
            ?.group(1)
            ?.toLowerCase() ??
        'img';
    return 'q_${h.toRadixString(16)}_${url.length}.$ext';
  }

  /// The saved copy of a quiz picture, or null if it isn't on the device yet.
  File? cachedImage(String url) {
    final dir = _imgDir;
    if (dir == null || url.isEmpty) return null;
    final f = File('$dir/${_imgName(_abs(url))}');
    return f.existsSync() ? f : null;
  }

  /// Full URL for a quiz picture (relative dashboard paths get the API host).
  String imageUrl(String url) => _abs(url);

  Future<void> _cacheImages(Map<String, dynamic> pack) async {
    try {
      await _file(); // sets _imgDir
      final dir = Directory(_imgDir!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final urls = <String>{};
      for (final q in (pack['quizzes'] as List? ?? const [])) {
        if (q is! Map) continue;
        for (final m in (q['questions'] as List? ?? const [])) {
          if (m is! Map) continue;
          final qi = '${m['question_image'] ?? ''}';
          if (qi.isNotEmpty) urls.add(_abs(qi));
          for (final u in (m['option_images'] as List? ?? const [])) {
            if ('$u'.isNotEmpty) urls.add(_abs('$u'));
          }
        }
      }
      if (urls.isEmpty) return;
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30)));
      for (final u in urls) {
        final f = File('${dir.path}/${_imgName(u)}');
        if (f.existsSync() && f.lengthSync() > 0) continue;
        final tmp = '${f.path}.part';
        try {
          await dio.download(u, tmp);
          await File(tmp).rename(f.path);
        } catch (_) {
          try {
            File(tmp).deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {/* offline — tried again next launch */}
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
        final type = '${m['type'] ?? ''}';
        if (type == 'sequence' && opts.length >= 2) {
          return QuizQuestion(
            questionText: (m['question_text'] ?? '').toString(),
            options: opts.take(6).toList(),
            correctAnswerIndex: 0, // 0 = the right order
            explanation: (m['explanation'] ?? '').toString().isEmpty
                ? null
                : m['explanation'].toString(),
            kind: QuizKind.sequence,
          );
        }
        final imgs = (m['option_images'] is List)
            ? (m['option_images'] as List).map((o) => '${o ?? ''}').toList()
            : <String>[];
        if (type == 'picture' && imgs.length >= 2) {
          final n = imgs.length > 4 ? 4 : imgs.length;
          while (opts.length < n) {
            opts.add('');
          }
          final ci = int.tryParse(
                  '${m['correct_answer_index'] ?? m['correct_index'] ?? 0}') ??
              0;
          final qi = '${m['question_image'] ?? ''}';
          return QuizQuestion(
            questionText: (m['question_text'] ?? '').toString(),
            options: opts.take(n).toList(),
            correctAnswerIndex: (ci >= 0 && ci < n) ? ci : 0,
            explanation: (m['explanation'] ?? '').toString().isEmpty
                ? null
                : m['explanation'].toString(),
            kind: QuizKind.picture,
            questionImage: qi.isEmpty ? null : qi,
            optionImages: imgs.take(n).toList(),
          );
        }
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
