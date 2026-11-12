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

  String? localModel(String id) {
    final p = _localModel[id];
    if (p != null && File(p).existsSync()) return p;
    return null;
  }

  String? localAudio(String id) {
    final p = _localAudio[id];
    if (p != null && File(p).existsSync()) return p;
    return null;
  }

  Future<void> loadIndex() async {
    try {
      final d = await _dir();
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
        }
      }
    } catch (_) {}
  }

  Future<int> downloadPack({
    required Map<String, String> models,
    required Map<String, String> audios,
    bool wifiOnly = true,
  }) async {
    if (wifiOnly && !(await onWifi())) return 0;
    final d = await _dir();
    int cached = 0;

    Future<void> grab(
        String id, String url, String ext, Map<String, String> index) async {
      if (url.isEmpty) return;
      if (index[id] != null && File(index[id]!).existsSync()) return;
      final dest = '${d.path}/$id.$ext';
      try {
        await _dio.download(url, dest);
        if (File(dest).existsSync() && File(dest).lengthSync() > 0) {
          index[id] = dest;
          cached++;
        }
      } catch (_) {}
    }

    for (final e in models.entries) {
      await grab(e.key, e.value, 'glb', _localModel);
    }
    for (final e in audios.entries) {
      await grab(e.key, e.value, 'm4a', _localAudio);
    }
    return cached;
  }

  Future<void> clear() async {
    try {
      final d = await _dir();
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
    _localModel.clear();
    _localAudio.clear();
  }
}
