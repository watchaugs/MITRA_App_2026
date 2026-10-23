// ═══════════════════════════════════════════════════════════════════════════
// ConsentI18n — loads a consent_<code>.json pack and looks up keys, with an
// English fallback baked in so the screen ALWAYS renders even if a pack is
// missing a key. Used only by the consent screen.
//
// Packs live in assets/locales/consent_<code>.json (en + 22 scheduled langs).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/auth/state_language_map.dart';

// English source strings — the guaranteed fallback for every key.
const Map<String, String> kConsentEn = {
  'consent.title': 'Consent Required',
  'consent.eyebrow': 'Data & Privacy',
  'consent.badge_moe': '🇮🇳  MoE',
  'consent.intro':
      'MITRA collects learning data under the Digital Personal Data Protection Act, 2023 (DPDPA). Please read and confirm below before continuing.',
  'consent.collect_title': '📋  What MITRA Collects',
  'consent.collect_1': 'Quiz scores & attempts',
  'consent.collect_2': 'AR session duration & topics viewed',
  'consent.collect_3': 'Time spent learning per subject',
  'consent.collect_4': 'Device type & connectivity (rural/urban)',
  'consent.collect_5': 'State & district (not GPS location)',
  'consent.reason_title': '🎯  Why We Collect It',
  'consent.reason_1': 'Track your learning progress',
  'consent.reason_2': 'Anonymised reports to Ministry of Education',
  'consent.reason_3': 'Improve app quality & safety',
  'consent.rights_title': 'Your Rights under DPDPA 2023',
  'consent.right_1': 'Access your data anytime from Profile',
  'consent.right_2': 'Request deletion — erased within 72 hours',
  'consent.right_3': 'Withdraw consent — account will be deactivated',
  'consent.right_4': 'Data never sold to third parties',
  'consent.right_5': 'All data encrypted at rest and in transit',
  'consent.parent_pre':
      "I confirm I am a parent/guardian (or above 18) and consent to MITRA collecting my child's learning data as described above under ",
  'consent.parent_link': 'DPDPA 2023',
  'consent.terms_pre': 'I have read and agree to the ',
  'consent.terms_link': 'Terms of Use',
  'consent.terms_and': ' and ',
  'consent.privacy_link': 'Privacy Policy',
  'consent.accept': 'Accept & Continue',
  'consent.decline': 'Decline & Sign Out',
  'consent.decline_hint':
      'Declining will sign you out. You can re-consent on next login.',
  'consent.lang_label': 'Language',
};

class ConsentI18nState {
  final String langCode;
  final Map<String, dynamic> strings; // loaded pack (may be partial)
  const ConsentI18nState({this.langCode = 'en', this.strings = const {}});

  /// Look up a key: pack value → English fallback → the key itself.
  String t(String key) {
    final v = strings[key];
    if (v is String && v.isNotEmpty) return v;
    return kConsentEn[key] ?? key;
  }
}

class ConsentI18nNotifier extends Notifier<ConsentI18nState> {
  @override
  ConsentI18nState build() => const ConsentI18nState();

  /// Load a specific language pack by code (e.g. 'gu').
  Future<void> load(String code) async {
    if (code == 'en') {
      state = const ConsentI18nState(langCode: 'en', strings: {});
      return;
    }
    try {
      final raw =
          await rootBundle.loadString('assets/locales/consent_$code.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      state = ConsentI18nState(langCode: code, strings: map);
    } catch (_) {
      // Missing/corrupt pack → English (never breaks the screen).
      state = const ConsentI18nState(langCode: 'en', strings: {});
    }
  }

  /// Auto-select the language for a detected state (falls back to English).
  Future<void> autoSelectForState(String? state) async {
    await load(consentLangForState(state));
  }
}

final consentI18nProvider =
    NotifierProvider<ConsentI18nNotifier, ConsentI18nState>(
  ConsentI18nNotifier.new,
);

// The languages offered in the selector bar, in display order.
// (code, native name) — names come from the packs' _lang_name, listed here so
// the bar needs no async load to render.
const List<MapEntry<String, String>> kConsentLangs = [
  MapEntry('en', 'English'),
  MapEntry('hi', 'हिन्दी'),
  MapEntry('bn', 'বাংলা'),
  MapEntry('mr', 'मराठी'),
  MapEntry('te', 'తెలుగు'),
  MapEntry('ta', 'தமிழ்'),
  MapEntry('gu', 'ગુજરાતી'),
  MapEntry('ur', 'اردو'),
  MapEntry('kn', 'ಕನ್ನಡ'),
  MapEntry('or', 'ଓଡ଼ିଆ'),
  MapEntry('ml', 'മലയാളം'),
  MapEntry('pa', 'ਪੰਜਾਬੀ'),
  MapEntry('as', 'অসমীয়া'),
  MapEntry('mai', 'मैथिली'),
  MapEntry('ne', 'नेपाली'),
  MapEntry('kok', 'कोंकणी'),
  MapEntry('sa', 'संस्कृतम्'),
  MapEntry('doi', 'डोगरी'),
  MapEntry('brx', 'बड़ो'),
  MapEntry('sd', 'سنڌي'),
  MapEntry('ks', 'کٲشُر'),
  MapEntry('mni', 'ꯃꯤꯇꯩꯂꯣꯟ'),
  MapEntry('sat', 'ᱥᱟᱱᱛᱟᱲᱤ'),
];
