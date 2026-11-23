// ═══════════════════════════════════════════════════════════════════════════
// Narration that starts at once.
//
// Playing the narration straight from its web address made the phone's media
// player read the file in many small requests through the MITRA server before
// the first word — 20-25 s on many phones, and again after every language
// change. Now each narration file (a 30 s narration is ~120 KB) is downloaded
// in ONE request, kept in the app's cache, and played from the phone:
//   • prefetch() fetches every language of the lesson in the background as
//     soon as the AR / 3D screen opens, so the first play and a language
//     switch are instant;
//   • play() uses the saved copy (waiting at most a few seconds for it), and
//     only if that fails streams the file as before;
//   • phones older than Android 10 can't play Opus, so they get the AAC copy
//     first instead of failing on Opus and only then trying AAC.
// Downloads follow the home-state rule (TerritoryGate.syncAllowed).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/territory_service.dart';
import '../../services/topic_cache.dart'; // narration kept with its topic

class NarrationSource {
  NarrationSource._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));
  static final Map<String, Future<String?>> _inflight = {};
  static Directory? _dir;
  static bool? _opus;

  /// How long play() waits for the saved copy before streaming instead.
  static const Duration _wait = Duration(seconds: 8);

  /// Ogg-Opus plays on Android 10 (API 29) and newer.
  static Future<bool> opusOk() async {
    final known = _opus;
    if (known != null) return known;
    var ok = true;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        ok = info.version.sdkInt >= 29;
      }
    } catch (_) {}
    _opus = ok;
    return ok;
  }

  static Future<Directory> _cacheDir() async {
    final d = _dir;
    if (d != null) return d;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/narration');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  static String _fileName(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 && path.length - dot <= 6 ? path.substring(dot) : '';
    return '${md5.convert(utf8.encode(url))}$ext';
  }

  /// The saved copy of [url] (downloaded once), or null if it can't be had.
  static Future<String?> local(String url) {
    if (!url.startsWith('http')) return Future.value(null);
    final running = _inflight[url];
    if (running != null) return running;
    final f = _fetch(url);
    _inflight[url] = f;
    unawaited(f.then((p) {
      if (p == null) _inflight.remove(url); // try again next time
    }));
    return f;
  }

  static Future<String?> _fetch(String url) async {
    try {
      final kept = await TopicCache.instance.pathFor(url);
      if (kept != null) return kept;
      final d = await _cacheDir();
      final f = File('${d.path}/${_fileName(url)}');
      if (f.existsSync() && f.lengthSync() > 0) return f.path;
      if (!TerritoryGate.syncAllowed) return null;
      final part = File('${f.path}.part');
      await _dio.download(url, part.path);
      if (!part.existsSync() || part.lengthSync() == 0) return null;
      await part.rename(f.path);
      return f.path;
    } catch (e) {
      debugPrint('🔊 Narration download failed: $e');
      return null;
    }
  }

  /// Start fetching the lesson's narration in every language (background).
  static Future<void> prefetch(
    Map<String, String> opus,
    Map<String, String> aac, {
    String? single,
  }) async {
    final useOpus = await opusOk();
    final urls = <String>{};
    if (single != null && single.startsWith('http')) urls.add(single);
    for (final lang in {...opus.keys, ...aac.keys}) {
      final o = opus[lang], a = aac[lang];
      final pick = useOpus ? (o ?? a) : (a ?? o);
      if (pick != null && pick.isNotEmpty) urls.add(pick);
    }
    for (final u in urls) {
      unawaited(local(u));
    }
  }

  /// Plays [url] (the Opus file) or [fallback] (AAC) on [player]: the saved
  /// copy when it is ready within a few seconds, else streams as before.
  /// [closing] stops it when the student has left the screen.
  static Future<void> play(
    AudioPlayer player, {
    required String url,
    String? fallback,
    required bool Function() closing,
  }) async {
    final useOpus = await opusOk();
    final String? aac =
        (fallback != null && fallback.isNotEmpty && fallback != url)
            ? fallback
            : null;
    final order = <String>[
      if (!useOpus && aac != null) aac,
      url,
      if (useOpus && aac != null) aac,
    ];
    for (final u in order) {
      if (closing()) return;
      String? path;
      try {
        path = await local(u).timeout(_wait, onTimeout: () => null);
      } catch (_) {
        path = null;
      }
      if (closing()) return;
      try {
        await player.stop();
        if (closing()) return;
        if (path != null) {
          await player.play(DeviceFileSource(path));
        } else if (u.startsWith('http')) {
          await player.play(UrlSource(u));
        } else {
          await player.play(AssetSource(u)); // e.g. 'ar/audio/xxx.mp3'
        }
        return;
      } catch (e) {
        debugPrint('🔊 Narration could not play $u: $e');
        if (path != null) {
          // A bad saved copy: drop it so it is fetched again next time.
          try {
            File(path).deleteSync();
          } catch (_) {}
          _inflight.remove(u);
        }
      }
    }
  }
}
