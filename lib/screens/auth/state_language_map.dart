// ═══════════════════════════════════════════════════════════════════════════
// State / UT → primary official language mapping (DPDPA consent auto-language).
//
// Maps a detected Indian state/UT name to the language code of its primary
// official language, so the consent notice opens in the regional language.
// Unmapped / undetected → English. The student can still override via the tabs.
//
// Language codes match the consent_<code>.json packs in assets/locales/.
// ═══════════════════════════════════════════════════════════════════════════

const Map<String, String> kStateToLang = {
  // ── States ──────────────────────────────────────────────────────────────
  'andhra pradesh': 'te',
  'arunachal pradesh': 'en', // no single scheduled primary; English administrative
  'assam': 'as',
  'bihar': 'hi',
  'chhattisgarh': 'hi',
  'goa': 'kok',
  'gujarat': 'gu',
  'haryana': 'hi',
  'himachal pradesh': 'hi',
  'jharkhand': 'hi',
  'karnataka': 'kn',
  'kerala': 'ml',
  'madhya pradesh': 'hi',
  'maharashtra': 'mr',
  'manipur': 'mni',
  'meghalaya': 'en',
  'mizoram': 'en',
  'nagaland': 'en',
  'odisha': 'or',
  'punjab': 'pa',
  'rajasthan': 'hi',
  'sikkim': 'ne',
  'tamil nadu': 'ta',
  'telangana': 'te',
  'tripura': 'bn',
  'uttar pradesh': 'hi',
  'uttarakhand': 'hi',
  'west bengal': 'bn',

  // ── Union Territories ───────────────────────────────────────────────────
  'andaman and nicobar islands': 'hi',
  'chandigarh': 'hi',
  'dadra and nagar haveli and daman and diu': 'gu',
  'delhi': 'hi',
  'jammu and kashmir': 'ur', // Urdu + others official; Kashmiri (ks) also available
  'ladakh': 'hi',
  'lakshadweep': 'ml',
  'puducherry': 'ta',
};

/// The consent language for a detected state. Case/whitespace-insensitive.
/// Returns 'en' when the state is null, empty, or unmapped.
String consentLangForState(String? state) {
  if (state == null) return 'en';
  // Accept both "Tamil Nadu" and "tamil_nadu" forms (the app stores either).
  final key = state.trim().toLowerCase().replaceAll('_', ' ');
  if (key.isEmpty) return 'en';
  return kStateToLang[key] ?? 'en';
}
