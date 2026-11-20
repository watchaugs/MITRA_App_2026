// ═══════════════════════════════════════════════════════════════════════════
// Content packs — new looks and content from the dashboard WITHOUT a new APK
// (Dashboard → App Manager → 📦 Content Packs).
//
// A pack is one JSON file { "mitra_pack": 1, "type": "...", "data": {...} }.
// This store:
//   • init()    — before runApp: reads the packs saved on the phone, so they
//                 work offline and from the very first frame (splash, theme);
//   • refresh() — in the background: asks the server which packs are
//                 published for this state and app build, downloads new or
//                 changed ones, checks each file's SHA-256 and saves it; packs
//                 no longer published are deleted.
// Downloads are used from the NEXT app start, so nothing changes under the
// student's finger mid-session. A pack's "show from / until" dates are checked
// on the phone too, so a festival skin turns itself on and off even offline.
//
// The app's own drawing code reads the data (theme_provider, hero_catalog,
// hero_biotech, chiku, onboarding, translation_provider, PackLottie); packs
// never contain code. Any pack problem → that pack is skipped, built-ins stay.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';

class PackStore {
  PackStore._();
  static final PackStore instance = PackStore._();

  static final RegExp _idOk = RegExp(r'^[a-z0-9][a-z0-9_-]{2,48}$');

  Directory? _dir;
  // Saved on the phone: id → {type, version, sha256, starts_at, ends_at}.
  Map<String, Map<String, dynamic>> _index = {};
  // In use this run (read by init()).
  final Map<String, Map<String, dynamic>> _data = {};
  final Map<String, String> _type = {};
  final Map<String, DateTime?> _from = {};
  final Map<String, DateTime?> _until = {};

  bool _busy = false;
  String? _queued; // a state that arrived while a check was running
  DateTime? _lastRefresh;
  String? _lastState;

  // ── Start-up ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/content_packs');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dir = d;
      final idx = File('${d.path}/index.json');
      if (!idx.existsSync()) return;
      final raw = jsonDecode(await idx.readAsString());
      if (raw is! Map) return;
      _index = {
        for (final e in raw.entries)
          if (e.value is Map)
            e.key.toString(): Map<String, dynamic>.from(e.value as Map)
      };
      for (final e in _index.entries) {
        try {
          final f = File('${d.path}/${e.key}.json');
          if (!f.existsSync()) continue;
          final pack = jsonDecode(await f.readAsString());
          if (pack is! Map || pack['data'] is! Map) continue;
          _data[e.key] = Map<String, dynamic>.from(pack['data'] as Map);
          _type[e.key] = (pack['type'] ?? '').toString();
          _from[e.key] =
              DateTime.tryParse((e.value['starts_at'] ?? '').toString());
          _until[e.key] =
              DateTime.tryParse((e.value['ends_at'] ?? '').toString());
        } catch (_) {/* a broken pack is skipped; the built-in look stays */}
      }
    } catch (e) {
      debugPrint('PackStore.init: $e');
    }
  }

  // ── Background download ───────────────────────────────────────────────────
  /// Checks the server for new / changed / removed packs (at most every 30
  /// minutes, or straight away when the state changes). Never throws.
  Future<void> refresh(String state, {bool force = false}) async {
    final d = _dir;
    if (d == null) return;
    if (_busy) {
      _queued = state; // checked as soon as the running check ends
      return;
    }
    final stateChanged = _lastState != state;
    if (!force &&
        !stateChanged &&
        _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < const Duration(minutes: 30)) {
      return;
    }
    _busy = true;
    try {
      var build = 0;
      try {
        build = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      } catch (_) {}
      final dio = ApiService.instance.dio;
      final res = await dio.get('/api/app-packs/manifest',
          queryParameters: {'state': state, 'build': build});
      final body = res.data;
      // No list = the server couldn't tell: keep what the phone has.
      if (body is! Map || body['packs'] is! List) return;
      _lastRefresh = DateTime.now();
      _lastState = state;

      final wifi = await _onWifi();
      final keep = <String>{};
      var changed = false;
      for (final p in (body['packs'] as List).whereType<Map>()) {
        final id = (p['id'] ?? '').toString();
        final sha = (p['sha256'] ?? '').toString();
        final url = (p['url'] ?? '').toString();
        final type = (p['type'] ?? '').toString();
        if (!_idOk.hasMatch(id) || sha.isEmpty || url.isEmpty) continue;
        keep.add(id);
        final meta = <String, dynamic>{
          'type': type,
          'version': p['version'],
          'sha256': sha,
          'starts_at': p['starts_at'],
          'ends_at': p['ends_at'],
        };
        final have = _index[id];
        if (have != null &&
            have['sha256'] == sha &&
            File('${d.path}/$id.json').existsSync()) {
          if (have['starts_at'] != meta['starts_at'] ||
              have['ends_at'] != meta['ends_at']) {
            _index[id] = meta; // dates changed only
            changed = true;
          }
          continue;
        }
        // Big pack and no Wi-Fi: keep the old copy (if any) and try later.
        if (p['wifi_only'] == true && !wifi) continue;

        final bytes = await _download(dio, url);
        if (bytes == null) continue;
        if (sha256.convert(bytes).toString() != sha) {
          debugPrint('PackStore: $id failed its checksum — skipped');
          continue;
        }
        Object? pack;
        try {
          pack = jsonDecode(utf8.decode(bytes));
        } catch (_) {
          pack = null;
        }
        if (pack is! Map || pack['data'] is! Map || pack['type'] != type) {
          continue;
        }
        await _write(d, '$id.json', bytes);
        if (type == 'lottie') {
          final anim = (pack['data'] as Map)['animation'];
          if (anim is Map) {
            await _write(d, '$id.anim.json', utf8.encode(jsonEncode(anim)));
          }
        }
        _index[id] = meta;
        changed = true;
      }
      // Unpublished / no longer for this state or build → removed.
      for (final id in _index.keys.toList()) {
        if (keep.contains(id)) continue;
        _index.remove(id);
        changed = true;
        for (final n in ['$id.json', '$id.anim.json']) {
          try {
            final f = File('${d.path}/$n');
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
      }
      if (changed) {
        await _write(d, 'index.json', utf8.encode(jsonEncode(_index)));
        debugPrint('PackStore: packs updated — used from the next app start');
      }
    } catch (e) {
      debugPrint('PackStore.refresh: $e'); // offline etc. → try again later
    } finally {
      _busy = false;
      final q = _queued;
      _queued = null;
      if (q != null && q != _lastState) unawaited(refresh(q));
    }
  }

  Future<List<int>?> _download(Dio dio, String url) async {
    try {
      final r = await dio.get<List<int>>(url,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 60),
          ));
      return r.data;
    } catch (_) {
      return null;
    }
  }

  // Write to a temp file, then rename: a half-written pack is never read.
  Future<void> _write(Directory d, String name, List<int> bytes) async {
    final tmp = File('${d.path}/$name.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename('${d.path}/$name');
  }

  Future<bool> _onWifi() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi) ||
          r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  // ── Reading packs ─────────────────────────────────────────────────────────
  bool _on(String id) {
    final now = DateTime.now();
    final a = _from[id], b = _until[id];
    if (a != null && now.isBefore(a)) return false;
    if (b != null && now.isAfter(b)) return false;
    return true;
  }

  /// Packs of one type that are on now, in id order (a later id wins).
  List<Map<String, dynamic>> _of(String type) {
    final ids = _data.keys.where((id) => _type[id] == type && _on(id)).toList()
      ..sort();
    return [for (final id in ids) _data[id]!];
  }

  static Map<String, String> _strMap(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            if (e.value is String) e.key.toString(): e.value as String
        }
      : const {};

  static List<Map<String, dynamic>> _mapList(Object? v) => v is List
      ? [for (final m in v.whereType<Map>()) Map<String, dynamic>.from(m)]
      : const [];

  /// Theme colours for [themeName] (an app theme's name): `gradient` [top,
  /// bottom] and/or `highlight`, as "#RRGGBB". '*' entries apply to every
  /// theme; a theme's own entry wins over '*'.
  Map<String, dynamic>? theme(String themeName) {
    Map<String, dynamic>? out;
    for (final pack in _of('theme')) {
      final themes = pack['themes'];
      if (themes is! Map) continue;
      for (final k in ['*', themeName]) {
        final t = themes[k];
        if (t is Map) (out ??= <String, dynamic>{}).addAll(Map<String, dynamic>.from(t));
      }
    }
    return out;
  }

  Map<String, Map<String, String>>? _texts;
  Map<String, Map<String, String>> get _textMap => _texts ??= () {
        final m = <String, Map<String, String>>{};
        for (final pack in _of('strings')) {
          for (final e in pack.entries) {
            m.putIfAbsent(e.key, () => <String, String>{}).addAll(_strMap(e.value));
          }
        }
        return m;
      }();

  /// Pack wording for [key] in [lang] (English too), or null.
  String? text(String lang, String key) => _textMap[lang]?[key];

  /// A whole language from packs (for a language the app doesn't carry).
  Map<String, String>? language(String lang) {
    final m = _textMap[lang];
    return (m == null || m.isEmpty) ? null : m;
  }

  /// A number / switch / text set by a settings pack, else [fallback].
  T setting<T>(String key, T fallback) {
    Object? v;
    for (final pack in _of('settings')) {
      if (pack.containsKey(key)) v = pack[key];
    }
    if (v is T) return v;
    if (fallback is int && v is num) return v.toInt() as T;
    if (fallback is double && v is num) return v.toDouble() as T;
    return fallback;
  }

  // Hero suits
  List<Map<String, dynamic>> get heroDefs =>
      [for (final p in _of('hero_suit')) ..._mapList(p['heroes'])];
  Map<String, String> get heroEmblems =>
      {for (final p in _of('hero_suit')) ..._strMap(p['emblems'])};
  Map<String, String> get heroMasks =>
      {for (final p in _of('hero_suit')) ..._strMap(p['masks'])};
  List<Map<String, dynamic>> get heroChunks =>
      [for (final p in _of('hero_suit')) ..._mapList(p['chunks'])];
  bool get heroReplaceBuiltIn =>
      _of('hero_suit').any((p) => p['replace_builtin_chunks'] == true);

  // Chiku
  Map<String, String> get chikuColors =>
      {for (final p in _of('chiku_look')) ..._strMap(p['colors'])};
  Map<String, String> get chikuParts =>
      {for (final p in _of('chiku_look')) ..._strMap(p['parts'])};
  String chikuExtra(String which) => [
        for (final p in _of('chiku_look'))
          if (p[which] is String) p[which] as String
      ].join();

  /// The intro-slides pack in use (the last one by id), or null.
  Map<String, dynamic>? get slides {
    final all = _of('slides');
    return all.isEmpty ? null : all.last;
  }

  /// The downloaded animation that replaces the built-in [asset], or null.
  String? lottiePath(String asset) {
    final d = _dir;
    if (d == null) return null;
    String? hit;
    final ids = _data.keys.where((id) => _type[id] == 'lottie' && _on(id)).toList()
      ..sort();
    for (final id in ids) {
      if (_data[id]!['replaces'] == asset) hit = id;
    }
    if (hit == null) return null;
    final f = File('${d.path}/$hit.anim.json');
    return f.existsSync() ? f.path : null;
  }
}
