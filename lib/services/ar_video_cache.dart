// ═══════════════════════════════════════════════════════════════════════════
// Page-video cache — the same idea as ArModelCache, for the videos that play
// on a scanned textbook page.
//
//   1. The first time a lesson video is opened it is downloaded ONCE to the
//      phone (the page scanner starts meanwhile; the video joins when ready).
//   2. Later plays come off the phone — no data, no server.
//   3. The newest 5 videos are kept (oldest downloaded is removed first).
//      Videos saved with "Save lessons offline" live in ArPackStore instead
//      and are never removed by this limit.
//
// The page scanner is a WebView, which cannot open files on the phone by
// path. So, like ArModelCache, files are handed to it through a tiny loopback
// server (127.0.0.1 only — nothing on the network can reach it). The server
// answers byte ranges, which the video player uses to seek and loop.
//
// A replaced video gets a new URL (?v=… from the dashboard) and so a new
// cache entry; the old one ages out.
//
// Everything is best-effort: on any failure callers stream the remote URL.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ArVideoCache {
  ArVideoCache._();
  static final ArVideoCache instance = ArVideoCache._();

  static const int maxVideos = 5;
  static const _kOrderKey = 'ar_video_cache_order'; // FIFO list of file names

  HttpServer? _server;
  int _port = 0;
  final Map<String, String> _served = {}; // URL token → absolute file path
  final Map<String, Future<String?>> _inFlight = {}; // remote URL → download
  final Map<String, ValueNotifier<double>> _progress = {}; // 0.0–1.0

  Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/ar_video_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // Stable across app restarts (FNV-1a), unlike String.hashCode.
  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  String _keyFor(String url) => 'v_${_hash(url)}.mp4';

  /// Download progress (0–1) of [remoteUrl] while it is downloading, else null.
  ValueListenable<double>? progressFor(String remoteUrl) =>
      _progress[remoteUrl];

  /// Loopback URL if [remoteUrl] is already on the phone, else null.
  Future<String?> cachedUrl(String remoteUrl) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${_keyFor(remoteUrl)}');
      if (!file.existsSync() || file.lengthSync() < 1000) return null;
      return urlForFile(file.path);
    } catch (_) {
      return null;
    }
  }

  /// Downloads [remoteUrl] once (shared if already running) and returns its
  /// loopback URL, or null on failure (caller then streams the remote URL).
  Future<String?> fetch(String remoteUrl) {
    final running = _inFlight[remoteUrl];
    if (running != null) return running;
    _progress[remoteUrl] = ValueNotifier<double>(0);
    final job = _fetch(remoteUrl).whenComplete(() {
      _inFlight.remove(remoteUrl);
      _progress.remove(remoteUrl);
    });
    _inFlight[remoteUrl] = job;
    return job;
  }

  Future<String?> _fetch(String remoteUrl) async {
    try {
      if (!remoteUrl.startsWith('http')) return null;
      final dir = await _cacheDir();
      final key = _keyFor(remoteUrl);
      final file = File('${dir.path}/$key');
      if (!file.existsSync() || file.lengthSync() < 1000) {
        final ok = await _download(
            remoteUrl, file, (v) => _progress[remoteUrl]?.value = v);
        if (!ok) return null;
        await _registerAndEvict(key, dir);
      }
      return urlForFile(file.path);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _download(
      String url, File dest, void Function(double) onProgress) async {
    HttpClient? client;
    final part = File('${dest.path}.part');
    try {
      client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return false;
      final total = res.contentLength; // -1 when unknown
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
      if (part.lengthSync() < 1000 || (total > 0 && got != total)) {
        part.deleteSync();
        return false;
      }
      if (dest.existsSync()) dest.deleteSync();
      part.renameSync(dest.path);
      return true;
    } catch (_) {
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      return false;
    } finally {
      client?.close();
    }
  }

  // ── FIFO: keep the newest [maxVideos] downloads ──────────────────────────
  Future<void> _registerAndEvict(String key, Directory dir) async {
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getStringList(_kOrderKey) ?? <String>[];
    order.remove(key);
    order.add(key);
    while (order.length > maxVideos) {
      final oldest = order.removeAt(0);
      try {
        final f = File('${dir.path}/$oldest');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await prefs.setStringList(_kOrderKey, order);
  }

  /// Loopback URL that serves the file at [path] (a cached video or a file
  /// saved by "Save lessons offline"). Null if the server can't start.
  Future<String?> urlForFile(String path) async {
    if (!File(path).existsSync()) return null;
    final port = await _ensureServer();
    if (port == 0) return null;
    final dot = path.lastIndexOf('.');
    final ext = dot > 0 ? path.substring(dot).toLowerCase() : '';
    final token = 'f_${_hash(path)}$ext';
    _served[token] = path;
    return 'http://127.0.0.1:$port/$token';
  }

  static ContentType _typeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.mp4')) return ContentType('video', 'mp4');
    if (p.endsWith('.glb')) return ContentType('model', 'gltf-binary');
    if (p.endsWith('.m4a')) return ContentType('audio', 'mp4');
    if (p.endsWith('.mp3')) return ContentType('audio', 'mpeg');
    if (p.endsWith('.opus') || p.endsWith('.ogg')) {
      return ContentType('audio', 'ogg');
    }
    return ContentType.binary;
  }

  // ── Loopback server: only files registered via urlForFile, with ranges ────
  Future<int> _ensureServer() async {
    if (_server != null && _port != 0) return _port;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _port = server.port;
      server.listen(_handle);
      return _port;
    } catch (_) {
      _server = null;
      _port = 0;
      return 0;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final token =
          req.uri.pathSegments.isNotEmpty ? req.uri.pathSegments.last : '';
      final path = _served[token];
      final file = path == null ? null : File(path);
      if (file == null || !file.existsSync()) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final len = await file.length();
      // The scanner page needs CORS to draw the video into WebGL.
      res.headers.set('Access-Control-Allow-Origin', '*');
      res.headers.set('Accept-Ranges', 'bytes');
      res.headers.set('Cache-Control', 'no-store');
      res.headers.contentType = _typeFor(file.path);
      var start = 0, end = len - 1;
      var partial = false;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final m = range == null
          ? null
          : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (m != null) {
        final s = m.group(1)!, e = m.group(2)!;
        if (s.isEmpty && e.isNotEmpty) {
          start = len - int.parse(e); // last N bytes
          if (start < 0) start = 0;
        } else if (s.isNotEmpty) {
          start = int.parse(s);
          if (e.isNotEmpty) end = int.parse(e);
        }
        if (end >= len) end = len - 1;
        if (start > end || start >= len) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set('Content-Range', 'bytes */$len');
          await res.close();
          return;
        }
        partial = true;
      }
      if (partial) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set('Content-Range', 'bytes $start-$end/$len');
      }
      res.contentLength = end - start + 1;
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await res.addStream(file.openRead(start, end + 1));
      await res.close();
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }
}
