// ═══════════════════════════════════════════════════════════════════════════
// AR model cache — cuts repeat-download egress for AR models.
//
// WHY A LOCAL SERVER: ar_flutter_plugin_2 (v0.0.3) reliably loads a model only
// by STREAMING a URL (NodeType.webGLB). Its file-path loading
// (fileSystemAppFolderGLB) resolved to a folder the native build doesn't read,
// throwing FileNotFoundException (the earlier black screen). So to cache AND
// still load reliably, we:
//   1. download the model ONCE to disk,
//   2. run a tiny loopback HTTP server (127.0.0.1) that serves cached bytes,
//   3. hand the plugin a 127.0.0.1 URL — it still "streams a URL" (its happy
//      path), but the bytes come off the device, not the network.
//
// POLICY: keep the newest 5 models (FIFO — oldest downloaded is evicted first).
// A repeat view of a cached topic = zero network egress.
//
// Everything is best-effort: if anything fails, callers fall back to the plain
// remote URL, so AR never breaks because of caching.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ArModelCache {
  ArModelCache._();
  static final ArModelCache instance = ArModelCache._();

  // Keep this many models on the device at once (oldest-downloaded evicted).
  static const int maxModels = 5;

  static const _kOrderKey = 'ar_model_cache_order'; // FIFO list of cache keys

  HttpServer? _server;
  int _port = 0;

  Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/ar_model_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // A stable, filesystem-safe filename for a model URL.
  String _keyFor(String url) =>
      'm_${url.hashCode.toUnsigned(32).toRadixString(16)}.glb';

  File _fileFor(Directory dir, String key) => File('${dir.path}/$key');

  // ── Public: get a LOCAL loopback URL for a model, downloading + caching it on
  // first use. Returns null on any failure so the caller streams the remote URL.
  Future<String?> localUrlFor(String remoteUrl) async {
    try {
      if (remoteUrl.isEmpty || !remoteUrl.startsWith('http')) return null;
      final dir = await _cacheDir();
      final key = _keyFor(remoteUrl);
      final file = _fileFor(dir, key);

      if (!file.existsSync() || file.lengthSync() < 100) {
        // Not cached yet → download the bytes once.
        final ok = await _download(remoteUrl, file);
        if (!ok) return null;
        await _registerAndEvict(key, dir);
      } else {
        // Already cached → bump it so FIFO order stays meaningful on access.
        await _touchOrder(key);
      }

      final port = await _ensureServer(dir);
      if (port == 0) return null;
      return 'http://127.0.0.1:$port/$key';
    } catch (_) {
      return null; // fall back to remote streaming
    }
  }

  Future<bool> _download(String url, File dest) async {
    HttpClient? client;
    try {
      client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return false;
      final sink = dest.openWrite();
      await res.pipe(sink);
      await sink.close();
      return dest.existsSync() && dest.lengthSync() > 100;
    } catch (_) {
      if (dest.existsSync()) {
        try {
          dest.deleteSync();
        } catch (_) {}
      }
      return false;
    } finally {
      client?.close();
    }
  }

  // ── FIFO bookkeeping ───────────────────────────────────────────────────────
  Future<List<String>> _order() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kOrderKey) ?? <String>[];
  }

  Future<void> _saveOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kOrderKey, order);
  }

  // New download → append to the FIFO list and evict the oldest beyond the cap.
  Future<void> _registerAndEvict(String key, Directory dir) async {
    final order = await _order();
    order.remove(key); // avoid duplicates
    order.add(key); // newest at the end
    while (order.length > maxModels) {
      final oldest = order.removeAt(0); // FIFO: drop the first/oldest
      final f = _fileFor(dir, oldest);
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await _saveOrder(order);
  }

  // Keep access order sensible without changing the FIFO-by-download policy:
  // we DON'T move accessed items (FIFO is by download time, as requested), so
  // this only ensures a known key is present in the list.
  Future<void> _touchOrder(String key) async {
    final order = await _order();
    if (!order.contains(key)) {
      order.add(key);
      await _saveOrder(order);
    }
  }

  // ── Loopback server: serves cached files by key, localhost only ────────────
  Future<int> _ensureServer(Directory dir) async {
    if (_server != null && _port != 0) return _port;
    try {
      // Port 0 → OS assigns a free ephemeral port. Bound to loopback only, so
      // nothing on the network can reach it.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _port = server.port;
      server.listen((HttpRequest req) async {
        try {
          final name =
              req.uri.pathSegments.isNotEmpty ? req.uri.pathSegments.last : '';
          // Only serve our own cache keys (prevents path traversal).
          if (!name.startsWith('m_') || !name.endsWith('.glb')) {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
            return;
          }
          final file = _fileFor(dir, name);
          if (!file.existsSync()) {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
            return;
          }
          req.response.headers.contentType =
              ContentType('model', 'gltf-binary');
          req.response.headers.set('Cache-Control', 'public, max-age=2592000');
          await req.response.addStream(file.openRead());
          await req.response.close();
        } catch (_) {
          try {
            req.response.statusCode = HttpStatus.internalServerError;
            await req.response.close();
          } catch (_) {}
        }
      });
      return _port;
    } catch (_) {
      _server = null;
      _port = 0;
      return 0;
    }
  }

  // Optional: stop the server (e.g. on logout). Safe to call anytime.
  Future<void> dispose() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _port = 0;
  }
}
