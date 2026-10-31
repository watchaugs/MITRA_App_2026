// ═══════════════════════════════════════════════════════════════════════════
// SCREEN: Language selection — shown AFTER location is acquired, BEFORE consent.
//
// Shows ONLY the languages relevant to the detected state:
//   • the state's regional language (from kStateToLang), when it isn't hi/en
//   • Hindi  (always — national link language)
//   • English (always — administrative / fallback)
//
// The chosen language is loaded into BOTH translation engines:
//   • translationProvider  → whole-app UI strings (assets/locales/<code>.json)
//   • consentI18nProvider  → the consent notice (assets/locales/consent_<code>.json)
// …so the consent screen that follows is already in the selected language, and
// the rest of the app is too. The pick is persisted (app_lang) so returning
// users keep it. DPDP: consent is presented in a language the student selected.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/colors.dart';
import '../../providers/translation_provider.dart';
import '../../providers/consent_i18n.dart';
import 'state_language_map.dart';

// Native display names for every code we support (matches the JSON packs).
const Map<String, String> kLangNativeNames = {
  'en': 'English',
  'hi': 'हिन्दी',
  'bn': 'বাংলা',
  'mr': 'मराठी',
  'te': 'తెలుగు',
  'ta': 'தமிழ்',
  'gu': 'ગુજરાતી',
  'ur': 'اردو',
  'kn': 'ಕನ್ನಡ',
  'or': 'ଓଡ଼ିଆ',
  'ml': 'മലയാളം',
  'pa': 'ਪੰਜਾਬੀ',
  'as': 'অসমীয়া',
  'mai': 'मैथिली',
  'ne': 'नेपाली',
  'kok': 'कोंकणी',
  'sa': 'संस्कृतम्',
  'doi': 'डोगरी',
  'brx': 'बड़ो',
  'sd': 'سنڌي',
  'ks': 'کٲشُر',
  'mni': 'ꯃꯤꯇꯩꯂꯣꯟ',
  'sat': 'ᱥᱟᱱᱛᱟᱲᱤ',
};

// English names, for the subtitle under each option.
const Map<String, String> kLangEnglishNames = {
  'en': 'English', 'hi': 'Hindi', 'bn': 'Bengali', 'mr': 'Marathi',
  'te': 'Telugu', 'ta': 'Tamil', 'gu': 'Gujarati', 'ur': 'Urdu',
  'kn': 'Kannada', 'or': 'Odia', 'ml': 'Malayalam', 'pa': 'Punjabi',
  'as': 'Assamese', 'mai': 'Maithili', 'ne': 'Nepali', 'kok': 'Konkani',
  'sa': 'Sanskrit', 'doi': 'Dogri', 'brx': 'Bodo', 'sd': 'Sindhi',
  'ks': 'Kashmiri', 'mni': 'Manipuri', 'sat': 'Santali',
};

/// Returns the ordered list of language codes to offer for a given state:
/// [regional (if distinct), 'hi', 'en'] — de-duplicated, order preserved.
List<String> languagesForState(String? state) {
  final regional = consentLangForState(state); // 'en' when unknown/unmapped
  final out = <String>[];
  if (regional != 'hi' && regional != 'en' && kLangNativeNames.containsKey(regional)) {
    out.add(regional);
  }
  out.add('hi');
  out.add('en');
  // De-dup while preserving order.
  return out.toSet().toList();
}

class LanguageScreen extends ConsumerStatefulWidget {
  /// Where to go after the language is chosen (usually the consent route).
  final String nextRoute;

  /// The detected state (so we can filter to its regional language).
  final String? state;

  const LanguageScreen({
    super.key,
    required this.nextRoute,
    this.state,
  });

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  String? _selected;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // Pre-select the regional language so the common case is one tap.
    final codes = languagesForState(widget.state);
    _selected = codes.isNotEmpty ? codes.first : 'en';
  }

  Future<void> _apply() async {
    final code = _selected ?? 'en';
    setState(() => _applying = true);
    // Load BOTH engines so the next screen (consent) and the whole app are in
    // the chosen language.
    await ref.read(translationProvider.notifier).loadLanguagePack(code);
    await ref.read(consentI18nProvider.notifier).load(code);
    if (!mounted) return;
    setState(() => _applying = false);
    context.go(widget.nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    final codes = languagesForState(widget.state);
    final t = ref.watch(translationProvider.notifier);

    return Scaffold(
      backgroundColor: MitraColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                t.tr('select_language_title', 'Select your Language'),
                style: const TextStyle(
                  fontFamily: 'Mukta',
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.state != null && widget.state!.isNotEmpty
                    ? 'For ${widget.state}. You can change this later in Settings.'
                    : 'You can change this later in Settings.',
                style: TextStyle(
                  fontFamily: 'Mukta',
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView.separated(
                  itemCount: codes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final code = codes[i];
                    final selected = code == _selected;
                    final isRegional = i == 0 &&
                        code != 'hi' &&
                        code != 'en'; // first & distinct = regional
                    return _LangTile(
                      native: kLangNativeNames[code] ?? code,
                      english: kLangEnglishNames[code] ?? code,
                      badge: isRegional
                          ? 'Your region'
                          : (code == 'hi'
                              ? 'National'
                              : (code == 'en' ? 'Default' : null)),
                      selected: selected,
                      onTap: () => setState(() => _selected = code),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _applying ? null : _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MitraColors.saffron,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _applying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.4))
                      : Text(
                          t.tr('btn_continue', 'Continue →'),
                          style: const TextStyle(
                            fontFamily: 'Mukta',
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  final String native;
  final String english;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _LangTile({
    required this.native,
    required this.english,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? MitraColors.saffron.withValues(alpha: 0.14)
              : MitraColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? MitraColors.saffron
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    native,
                    style: const TextStyle(
                      fontFamily: 'Mukta',
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    english,
                    style: TextStyle(
                      fontFamily: 'Mukta',
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontFamily: 'Mukta',
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(Icons.check_circle,
                    color: MitraColors.saffron, size: 24),
              ),
          ],
        ),
      ),
    );
  }
}
