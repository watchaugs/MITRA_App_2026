import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ArPackStore {
  ArPackStore._();
  static final ArPackStore instance = ArPackStore._();

  final Dio _dio = Dio();
  final Map<String, String> _localModel = {};
  final Map<String, String> _localAudio = {};
  final Map<String, String> _localVideo = {}; // page videos (.mp4)
  // Source URL each saved file came from ('glb:<id>' → url). When the
  // dashboard replaces a file its URL changes (?v=…), so the saved copy is
  // treated as stale and re-downloaded on the next Save.
  final Map<String, String> _srcUrl = {};

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/ar_packs');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<bool> onWifi() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  // [url] = the lesson's current URL: a saved copy from an older URL is stale
  // (replaced on the dashboard) and is ignored, so the new file streams.
  String? _fresh(
      String kind, String id, Map<String, String> index, String? url) {
    final p = index[id];
    if (p == null || !File(p).existsSync()) return null;
    final src = _srcUrl['$kind:$id'];
    if (url != null && url.isNotEmpty && src != null && src != url) {
      return null;
    }
    return p;
  }

  String? localModel(String id, {String? url}) =>
      _fresh('glb', id, _localModel, url);

  String? localAudio(String id, {String? url}) =>
      _fresh('m4a', id, _localAudio, url);

  String? localVideo(String id, {String? url}) =>
      _fresh('mp4', id, _localVideo, url);

  Future<void> _saveSrcIndex(Directory d) async {
    try {
      await File('${d.path}/index.json').writeAsString(jsonEncode(_srcUrl));
    } catch (_) {}
  }

  Future<void> loadIndex() async {
    try {
      final d = await _dir();
      try {
        final idx = File('${d.path}/index.json');
        if (idx.existsSync()) {
          final m = jsonDecode(idx.readAsStringSync());
          if (m is Map) {
            m.forEach((k, v) => _srcUrl[k.toString()] = v.toString());
          }
        }
      } catch (_) {}
      for (final f in d.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        final id = name.substring(0, dot);
        final ext = name.substring(dot + 1).toLowerCase();
        if (ext == 'glb') {
          _localModel[id] = f.path;
        } else if (ext == 'm4a' ||
            ext == 'aac' ||
            ext == 'mp3' ||
            ext == 'opus') {
          _localAudio[id] = f.path;
        } else if (ext == 'mp4') {
          _localVideo[id] = f.path;
        }
      }
    } catch (_) {}
  }

  Future<int> downloadPack({
    required Map<String, String> models,
    required Map<String, String> audios,
    Map<String, String> videos = const {},
    bool wifiOnly = true,
  }) async {
    if (wifiOnly && !(await onWifi())) return 0;
    final d = await _dir();
    int cached = 0;

    Future<void> grab(
        String id, String url, String ext, Map<String, String> index) async {
      if (url.isEmpty) return;
      final key = '$ext:$id';
      final have = index[id] != null && File(index[id]!).existsSync();
      // Saved before URLs were recorded → keep it and record the URL.
      if (have && _srcUrl[key] == null) {
        _srcUrl[key] = url;
        return;
      }
      if (have && _srcUrl[key] == url) return; // up to date
      // New, or replaced on the dashboard → (re)download. Into a temp file
      // first, so a failed download never destroys the working copy.
      final dest = '${d.path}/$id.$ext';
      final part = '$dest.part';
      try {
        await _dio.download(url, part);
        final f = File(part);
        if (f.existsSync() && f.lengthSync() > 0) {
          final old = File(dest);
          if (old.existsSync()) old.deleteSync();
          f.renameSync(dest);
          index[id] = dest;
          _srcUrl[key] = url;
          cached++;
        }
      } catch (_) {
        try {
          final f = File(part);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }

    for (final e in models.entries) {
      await grab(e.key, e.value, 'glb', _localModel);
    }
    for (final e in audios.entries) {
      await grab(e.key, e.value, 'm4a', _localAudio);
    }
    for (final e in videos.entries) {
      await grab(e.key, e.value, 'mp4', _localVideo);
    }
    await _saveSrcIndex(d);
    return cached;
  }

  Future<void> clear() async {
    try {
      final d = await _dir();
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
    _localModel.clear();
    _localAudio.clear();
    _localVideo.clear();
    _srcUrl.clear();
  }
}
