// ═══════════════════════════════════════════════════════════════════════════
// Topic cache — lessons kept on the phone so they play without streaming.
//
// RULE (per subject of the student's class, in Curriculum Map order):
//   • the NEXT 3 released topics the student has not finished, and
//   • the LAST 3 topics the student finished (fast revisit / replay)
// are downloaded and kept on the phone.
//   "Finished" = the AR lesson was watched AND its linked quiz was passed
//   (a lesson with no linked quiz is finished once watched).
//
// REMOVAL: when a finished topic falls out of the "last 3", it is removed
// (oldest finished first). A topic that is not finished is NEVER removed while
// it is still in the student's lesson list. A topic the dashboard withdrew
// (no longer in the list) is removed.
//
// WHAT IS KEPT per topic: the 3D model (the one this phone uses), the page
// video, the page target (.mind) and page image, and the narration in the
// student's languages (state language, app language, English). Quizzes are
// already kept offline by the quiz pack.
//
// Downloads run on any network, one file at a time, in the background, and
// only in the home state (TerritoryGate.syncAllowed). Each AR screen asks
// pathFor(url) first and plays the saved copy; if there is none it streams as
// before, so nothing breaks when a file is missing.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'territory_service.dart'; // TerritoryGate (home-state rule)

/// One lesson of a subject, with every file the phone needs to play it.
class CacheTopic {
  final String id;
  final List<String> urls;
  const CacheTopic(this.id, this.urls);
}

class TopicCache {
  TopicCache._();
  static final TopicCache instance = TopicCache._();

  /// Unfinished topics kept ahead, per subject.
  static const int ahead = 3;

  /// Finished topics kept for revisit, per subject.
  static const int behind = 3;

  Directory? _dir;
  Future<void>? _loading;
  final Map<String, String> _files = {}; // remote URL → file name
  final Map<String, List<String>> _topics = {}; // kept topic id → its URLs
  final Map<String, int> _doneAt = {}; // topic id → when it was finished

  Map<String, List<CacheTopic>>? _plan; // subject → lessons in map order
  bool Function(String id)? _isDone;
  bool _running = false;
  bool _again = false;
  Timer? _poke;

  // ── Index on disk ─────────────────────────────────────────────────────────
  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/topic_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      final idx = File('${dir.path}/index.json');
      if (!idx.existsSync()) return;
      final m = jsonDecode(await idx.readAsString());
      if (m is! Map) return;
      final f = m['files'], t = m['topics'], d = m['done'];
      if (f is Map) {
        f.forEach((k, v) {
          if (File('${dir.path}/$v').existsSync()) _files['$k'] = '$v';
        });
      }
      if (t is Map) {
        t.forEach((k, v) {
          if (v is List) _topics['$k'] = v.map((e) => '$e').toList();
        });
      }
      if (d is Map) {
        d.forEach((k, v) {
          if (v is int) _doneAt['$k'] = v;
        });
      }
    } catch (e) {
      debugPrint('📦 TopicCache load: $e');
    }
  }

  Future<void> _save() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final tmp = File('${dir.path}/index.json.tmp');
      await tmp.writeAsString(jsonEncode({
        'files': _files,
        'topics': _topics,
        'done': _doneAt,
      }));
      await tmp.rename('${dir.path}/index.json');
    } catch (e) {
      debugPrint('📦 TopicCache save: $e');
    }
  }

  static String _nameFor(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 && path.length - dot <= 6 ? path.substring(dot) : '';
    return '${md5.convert(utf8.encode(url))}$ext';
  }

  // ── Lookups used by the AR screens ────────────────────────────────────────
  /// The saved copy of [url] on this phone, or null (then stream as before).
  Future<String?> pathFor(String? url) async {
    if (url == null || !url.startsWith('http')) return null;
    await _ensureLoaded();
    final dir = _dir, name = _files[url];
    if (dir == null || name == null) return null;
    final f = File('${dir.path}/$name');
    if (f.existsSync() && f.lengthSync() > 0) return f.path;
    _files.remove(url);
    return null;
  }

  // ── Planning ──────────────────────────────────────────────────────────────
  /// The student's lessons per subject (Curriculum Map order, released and
  /// for their class) and how to tell a finished topic. Starts the background
  /// download / clean-up.
  void plan(Map<String, List<CacheTopic>> bySubject,
      bool Function(String id) isDone) {
    _plan = bySubject;
    _isDone = isDone;
    unawaited(_run());
  }

  /// Progress changed (lesson watched / quiz passed) → move the window on.
  void poke() {
    if (_plan == null) return;
    _poke?.cancel();
    _poke = Timer(const Duration(seconds: 3), () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again);
    } catch (e) {
      debugPrint('📦 TopicCache: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _syncOnce() async {
    final plan = _plan, isDone = _isDone;
    if (plan == null || isDone == null) return;
    await _ensureLoaded();
    final dir = _dir;
    if (dir == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    var stamp = 0;
    final all = <String, CacheTopic>{};
    final nextBySubject = <List<CacheTopic>>[];
    final wanted = <String, CacheTopic>{}; // download order

    final doneBySubject = <List<CacheTopic>>[];
    for (final lessons in plan.values) {
      final next = <CacheTopic>[];
      final done = <CacheTopic>[];
      for (final t in lessons) {
        if (all.containsKey(t.id)) continue;
        all[t.id] = t;
        if (isDone(t.id)) {
          // First seen finished now; earlier in the map = finished earlier.
          _doneAt.putIfAbsent(t.id, () => now + stamp++);
          done.add(t);
        } else {
          _doneAt.remove(t.id);
          if (next.length < ahead) next.add(t);
        }
      }
      done.sort((a, b) => (_doneAt[b.id] ?? 0).compareTo(_doneAt[a.id] ?? 0));
      nextBySubject.add(next);
      doneBySubject.add(done.take(behind).toList());
    }
    // Next topics first, one per subject in turn, then the recent finished.
    for (var i = 0; i < ahead; i++) {
      for (final n in nextBySubject) {
        if (i < n.length) wanted[n[i].id] = n[i];
      }
    }
    for (final d in doneBySubject) {
      for (final t in d) {
        wanted[t.id] = t;
      }
    }

    // ── Clean-up first (frees space before downloading) ─────────────────────
    final keepUrls = <String>{};
    for (final t in wanted.values) {
      keepUrls.addAll(t.urls);
    }
    for (final id in _topics.keys.toList()) {
      if (wanted.containsKey(id)) continue;
      final listed = all[id];
      if (listed != null && !isDone(id)) {
        keepUrls.addAll(listed.urls); // unfinished → never removed
        _topics[id] = listed.urls;
      } else if (listed == null && all.isEmpty) {
        keepUrls.addAll(_topics[id]!); // empty list (offline?) → keep as is
      } else {
        _topics.remove(id); // finished beyond the last 3, or withdrawn
      }
    }
    for (final url in _files.keys.toList()) {
      if (keepUrls.contains(url)) continue;
      final name = _files.remove(url)!;
      try {
        final f = File('${dir.path}/$name');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await _save();

    // ── Downloads ───────────────────────────────────────────────────────────
    for (final t in wanted.values) {
      _topics[t.id] = t.urls;
      for (final url in t.urls) {
        if (_again) return; // a newer plan arrived → restart with it
        if (!TerritoryGate.syncAllowed) return; // only from the home state
        if (await pathFor(url) != null) continue;
        final name = _nameFor(url);
        if (await _download(url, File('${dir.path}/$name'))) {
          _files[url] = name;
        }
      }
      await _save();
    }
  }

  Future<bool> _download(String url, File dest) async {
    final part = File('${dest.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        return false;
      }
      final total = res.contentLength; // -1 when unknown
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk
            in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
        }
      } finally {
        await sink.close();
      }
      if (got == 0 || (total > 0 && got != total)) {
        if (part.existsSync()) part.deleteSync();
        return false;
      }
      if (dest.existsSync()) dest.deleteSync();
      part.renameSync(dest.path);
      return true;
    } catch (e) {
      debugPrint('📦 TopicCache download failed: $e');
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      return false;
    } finally {
      client.close();
    }
  }
}
