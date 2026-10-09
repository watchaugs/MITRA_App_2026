/// Single source of truth for legal links + in-app policy text.
/// These are DRAFTS for legal review — replace with the authorised,
/// department-approved copy and hosted URLs before submission.
class LegalConfig {
  // ── External links (a govt reviewer will click these) ──
  // TODO: replace with the real hosted URLs before submission.
  static const String privacyPolicyUrl = 'https://mitra.gov.in/privacy';
  static const String termsUrl = 'https://mitra.gov.in/terms';

  // ── In-app policy text ──
  static const String privacyPolicyText = '''
MITRA — Privacy Policy
Draft for review · Version 1.0

MITRA ("the App") is an educational application provided by the Education
Department for school students. This policy explains what personal data we
collect, why, and the rights you have under the Digital Personal Data
Protection Act, 2023 (DPDPA).

1. What we collect
- Identity & profile: name, avatar, class/grade, state, preferred language.
- Learning activity: lessons viewed, AR sessions, quiz attempts, XP, streaks.
- Optional demographics (only if you consent): used to improve access and equity.
- Device & technical: device model, OS version, connectivity, and anonymous
  usage events that help keep the App reliable.

2. Why we collect it
We use your data only to deliver and improve learning — show the right
curriculum for your class and state, run quizzes and AR lessons, track your
personal progress, and understand overall usage in aggregate. We do not sell
your data.

3. Children & parental consent
MITRA is used by children. For a child, we require verifiable consent from a
parent or guardian before processing personal data, in line with the DPDPA. We
do not knowingly carry out tracking or targeted advertising directed at children.

4. How your data is handled
Data is processed on Government-approved secure cloud infrastructure (including
Google Firebase and Google Cloud). These providers act as our processors under
agreement and may not use your data for their own purposes.

5. Sharing
We share personal data only with: (a) the Education Department and its
authorised staff; (b) processors who help operate the App; and (c) where
required by law. We do not share your data for commercial marketing.

6. Retention
We keep your data only as long as needed to provide the service and meet legal
obligations, after which it is deleted or anonymised.

7. Your rights
You may access a copy of your data, correct it, withdraw consent, and request
deletion of your account and data. Start a data copy or deletion request from
Profile → Account & Data. You may also raise a concern with our Grievance
Officer (Profile → Grievance & Data Protection).

8. Security
We use reasonable technical and organisational safeguards to protect your data.
No system is perfectly secure; we work to reduce risk and respond to incidents.

9. Changes
We may update this policy and will notify you of material changes in the App.

10. Contact
For privacy questions, contact the officers listed under
Profile → Grievance & Data Protection.

This is a draft pending the authorised policy, to be published by the
Education Department.
''';

  static const String termsText = '''
MITRA — Terms of Use
Draft for review · Version 1.0

By using MITRA you agree to these Terms. If you are a child, a parent or
guardian must consent on your behalf.

1. The service
MITRA provides curriculum-aligned lessons, 3D/AR content, and quizzes for
school students, provided by the Education Department for educational use.

2. Eligibility & accounts
MITRA is for enrolled students (and teachers). Provide accurate information,
keep your login secure, and use one account per person.

3. Acceptable use
Do not misuse the service, attempt to access other users' data,
reverse-engineer or disrupt the App, or upload unlawful content. Misuse may
lead to suspension.

4. Learning progress
XP, badges and progress support your learning. Changing your class resets your
learning path to the new class (allowed once every 90 days); your XP and badges
are retained.

5. Content & intellectual property
Curriculum, AR assets and App content belong to the Education Department or its
licensors. You receive a limited, personal, non-transferable licence to use
them for learning.

6. Your data
Your use is governed by our Privacy Policy (Profile → Privacy Policy).

7. Availability & changes
The service is provided on an "as available" basis; features may change or be
suspended.

8. Termination
Accounts may be suspended for misuse. You may stop using MITRA and request
account deletion from Profile → Account & Data.

9. Grievances & governing law
Raise grievances via Profile → Grievance & Data Protection. These Terms are
governed by the laws of India.

10. Contact
See Profile → Grievance & Data Protection for official contacts.

This is a draft pending the authorised terms, to be published by the
Education Department.
''';
}
