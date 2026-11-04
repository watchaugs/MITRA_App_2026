// ═══════════════════════════════════════════════════════════════════════════
// Region → allowed narration languages. Fetched from the backend
// (/api/ar/language-config); hi + en are universal (allowed everywhere).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

class LanguageOptionsService {
  Map<String, List<String>> _regions = {};
  List<String> _universal = const ['hi', 'en'];
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final res = await ApiService.instance.dio.get('/api/ar/language-config');
      final data = res.data as Map;
      _regions = ((data['regions'] as Map?) ?? {}).map((k, v) => MapEntry(
            k.toString().toLowerCase(),
            (v as List).map((e) => e.toString().toLowerCase()).toList(),
          ));
      _universal = ((data['universal'] as List?) ?? const ['hi', 'en'])
          .map((e) => e.toString().toLowerCase())
          .toList();
      _loaded = true;
    } catch (_) {/* fail-open to universal hi/en */}
  }

  // Allowed languages for a state = universal ∪ that region's extras.
  Set<String> allowedFor(String? state) {
    final out = <String>{..._universal};
    if (state != null && state.isNotEmpty) {
      final k = state.trim().toLowerCase().replaceAll('_', ' ');
      out.addAll(_regions[k] ?? const []);
    }
    return out;
  }
}

final languageOptionsServiceProvider =
    Provider<LanguageOptionsService>((ref) => LanguageOptionsService());
