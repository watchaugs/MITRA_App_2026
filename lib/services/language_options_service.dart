// ═══════════════════════════════════════════════════════════════════════════
// Region → allowed narration languages. Fetched from the backend
// (/api/ar/language-config); hi + en are universal (allowed everywhere).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../screens/auth/state_language_map.dart';

class LanguageOptionsService {
  Map<String, List<String>> _regions = {};
  List<String> _universal = const ['hi', 'en'];
  bool _loaded = false;

  static const _prefsKey = 'language_config_v1';

  // The AR / 3D screens wait for this before the narration starts, so it
  // must be quick: at most 4 s on the network, else the list saved last time
  // (or hi + en + the state's own language). It used to wait up to the API's
  // 15 s timeout, on every lesson, whenever the call failed.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final res = await ApiService.instance.dio
          .get('/api/ar/language-config')
          .timeout(const Duration(seconds: 4));
      _apply(res.data as Map);
      _loaded = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(res.data));
      } catch (_) {}
    } catch (_) {
      // Offline / slow: the list saved last time.
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw != null) _apply(jsonDecode(raw) as Map);
      } catch (_) {/* fail-open to universal hi/en */}
    }
  }

  void _apply(Map data) {
    _regions = ((data['regions'] as Map?) ?? {}).map((k, v) => MapEntry(
          k.toString().toLowerCase(),
          (v as List).map((e) => e.toString().toLowerCase()).toList(),
        ));
    _universal = ((data['universal'] as List?) ?? const ['hi', 'en'])
        .map((e) => e.toString().toLowerCase())
        .toList();
  }

  // Allowed languages for a state = universal ∪ that region's extras.
  Set<String> allowedFor(String? state) {
    final out = <String>{..._universal};
    if (state != null && state.isNotEmpty) {
      final k = state.trim().toLowerCase().replaceAll('_', ' ');
      out.addAll(_regions[k] ?? const []);
      // The state's own language always counts (Punjab → pa), even offline
      // or when the server has nothing saved for this state.
      out.add(consentLangForState(state));
    }
    return out;
  }
}

final languageOptionsServiceProvider =
    Provider<LanguageOptionsService>((ref) => LanguageOptionsService());
