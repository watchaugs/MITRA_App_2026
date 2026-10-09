/// Single source of truth for legal links + in-app policy text.
/// Replace the placeholder URLs and text with the authorised versions.
class LegalConfig {
  // ── External links (a govt reviewer will click these) ──
  // TODO: replace with the real hosted URLs before submission.
  static const String privacyPolicyUrl =
      'https://mitra.gov.in/privacy'; // placeholder
  static const String termsUrl = 'https://mitra.gov.in/terms'; // placeholder

  // ── In-app fallback text (shown on the in-app pages) ──
  // TODO: replace with the authorised policy copy.
  static const String privacyPolicyText = '''
MITRA Privacy Policy (Draft — to be replaced)

MITRA is an educational application. We collect the minimum data needed to
provide learning: your name, class, state, language preference, and learning
progress (XP, quiz attempts).

We process this data under the Digital Personal Data Protection Act, 2023.
For children, we require verifiable parental/guardian consent.

You may withdraw consent, request a copy of your data, or request deletion at
any time from Settings. Contact our Grievance Officer (see Settings › Grievance)
for any concern.

This is placeholder text pending the authorised policy.
''';

  static const String termsText = '''
MITRA Terms of Use (Draft — to be replaced)

By using MITRA you agree to use it for learning purposes. Content is provided by
the education department. Do not misuse the service or attempt to access other
users' data.

This is placeholder text pending the authorised terms.
''';
}
