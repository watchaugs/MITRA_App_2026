// ═══════════════════════════════════════════════════════════════════════════
// MITRA heroes — one original superhero per curriculum subject, in a boy and a
// girl version. All designs are MITRA's own (no film/comic characters).
//
// The student's profile gender picks the version: 'Male' → boy, 'Female' →
// girl, 'Other' → the boy + girl hero team side by side.
//
// A subject name from the dashboard is matched by keywords (so "Maths",
// "Mathematics" and "Ganit" all find the maths hero). Any subject not listed
// gets the Vidya Veer / Vidya Veera hero, so no subject is ever without one.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

class HeroDef {
  final String subject; // display label of the hero's subject
  final String boyName;
  final String girlName;
  final Color main; // suit colour
  final Color accent; // cape / emblem colour
  final String emblem; // emblem key drawn by hero_svg.dart
  final Color skin;
  final Color hair;
  final String mask; // mask style key drawn by hero_svg.dart
  final List<String> keywords; // lower-case words that map a subject here

  const HeroDef({
    required this.subject,
    required this.boyName,
    required this.girlName,
    required this.main,
    required this.accent,
    required this.emblem,
    required this.skin,
    required this.hair,
    required this.mask,
    required this.keywords,
  });
}

const List<HeroDef> kHeroes = [
  HeroDef(
      subject: 'Physics', boyName: 'Vidyut', girlName: 'Vidyuta',
      main: Color(0xFF1D4ED8), accent: Color(0xFFFACC15), emblem: 'bolt',
      skin: Color(0xFF8D5524), hair: Color(0xFF111827), mask: 'goggle',
      keywords: ['physics', 'bhautik']),
  HeroDef(
      subject: 'Chemistry', boyName: 'Rasayan', girlName: 'Rasika',
      main: Color(0xFF6D28D9), accent: Color(0xFFA3E635), emblem: 'flask',
      skin: Color(0xFFE0AC69), hair: Color(0xFF3F2A14), mask: 'domino',
      keywords: ['chemistry', 'rasayan']),
  HeroDef(
      subject: 'Biology', boyName: 'Jeevak', girlName: 'Jeeva',
      main: Color(0xFF15803D), accent: Color(0xFFF472B6), emblem: 'dna',
      skin: Color(0xFFA0662F), hair: Color(0xFF1C1917), mask: 'leaf',
      keywords: ['biology', 'jeev', 'life science']),
  HeroDef(
      subject: 'Mathematics', boyName: 'Ank', girlName: 'Ankita',
      main: Color(0xFF3730A3), accent: Color(0xFFFB923C), emblem: 'pi',
      skin: Color(0xFFF1C27D), hair: Color(0xFF1C1917), mask: 'star',
      keywords: ['math', 'ganit', 'algebra', 'geometry']),
  HeroDef(
      subject: 'EVS', boyName: 'Vriksh', girlName: 'Prakriti',
      main: Color(0xFF166534), accent: Color(0xFF38BDF8), emblem: 'tree',
      skin: Color(0xFF8D5524), hair: Color(0xFF3F2A14), mask: 'leaf',
      keywords: ['evs', 'environment', 'paryavaran']),
  HeroDef(
      subject: 'History', boyName: 'Yug', girlName: 'Yuga',
      main: Color(0xFF7F1D1D), accent: Color(0xFFF59E0B), emblem: 'hour',
      skin: Color(0xFFE0AC69), hair: Color(0xFF111827), mask: 'goggle',
      keywords: ['history', 'itihas']),
  HeroDef(
      subject: 'Geography', boyName: 'Dhruv', girlName: 'Disha',
      main: Color(0xFF92400E), accent: Color(0xFF0EA5E9), emblem: 'compass',
      skin: Color(0xFFC68642), hair: Color(0xFF1C1917), mask: 'wing',
      keywords: ['geography', 'bhugol']),
  HeroDef(
      subject: 'Civics', boyName: 'Nyay', girlName: 'Nyaya',
      main: Color(0xFF1E3A8A), accent: Color(0xFFFB923C), emblem: 'scale',
      skin: Color(0xFFA0662F), hair: Color(0xFF1C1917), mask: 'domino',
      keywords: ['civics', 'political', 'nagrik', 'polity']),
  HeroDef(
      subject: 'Economics', boyName: 'Arth', girlName: 'Artha',
      main: Color(0xFFA16207), accent: Color(0xFF22C55E), emblem: 'coin',
      skin: Color(0xFFF1C27D), hair: Color(0xFF3F2A14), mask: 'star',
      keywords: ['economics', 'arthshastra', 'commerce']),
  HeroDef(
      subject: 'Social Science', boyName: 'Sangam', girlName: 'Sangini',
      main: Color(0xFFBE123C), accent: Color(0xFF2DD4BF), emblem: 'people',
      skin: Color(0xFF8D5524), hair: Color(0xFF111827), mask: 'visor',
      keywords: ['social', 'samajik', 'sst']),
  HeroDef(
      subject: 'Computer Science', boyName: 'Code Veer', girlName: 'Code Veera',
      main: Color(0xFF0F766E), accent: Color(0xFF22D3EE), emblem: 'code',
      skin: Color(0xFFA0662F), hair: Color(0xFF111827), mask: 'goggle',
      keywords: ['computer', 'coding', 'information technology', ' it']),
  HeroDef(
      subject: 'English', boyName: 'Lekh', girlName: 'Lekha',
      main: Color(0xFFB91C1C), accent: Color(0xFFFDE68A), emblem: 'quill',
      skin: Color(0xFFE0AC69), hair: Color(0xFF7C2D12), mask: 'domino',
      keywords: ['english', 'angrezi']),
  HeroDef(
      subject: 'Hindi', boyName: 'Shabd', girlName: 'Shabdika',
      main: Color(0xFFC2410C), accent: Color(0xFFE879F9), emblem: 'a',
      skin: Color(0xFFC68642), hair: Color(0xFF1C1917), mask: 'wing',
      keywords: ['hindi', 'हिंदी', 'हिन्दी']),
  HeroDef(
      subject: 'Sanskrit', boyName: 'Shlok', girlName: 'Shloka',
      main: Color(0xFF9A3412), accent: Color(0xFFFCD34D), emblem: 'scroll',
      skin: Color(0xFFE0AC69), hair: Color(0xFF111827), mask: 'visor',
      keywords: ['sanskrit', 'संस्कृत']),
  HeroDef(
      subject: 'Regional language', boyName: 'Swar', girlName: 'Bhasha',
      main: Color(0xFF7E22CE), accent: Color(0xFFFBBF24), emblem: 'bubble',
      skin: Color(0xFF8D5524), hair: Color(0xFF1C1917), mask: 'star',
      keywords: [
        'marathi', 'gujarati', 'bengali', 'bangla', 'tamil', 'telugu',
        'kannada', 'malayalam', 'odia', 'oriya', 'punjabi', 'urdu',
        'assamese', 'konkani', 'manipuri', 'nepali', 'kashmiri', 'sindhi',
        'dogri', 'maithili', 'santali', 'bodo', 'regional', 'mother tongue',
      ]),
  // Checked after the specific sciences so "Science" alone lands here.
  HeroDef(
      subject: 'Science', boyName: 'Vigyan Veer', girlName: 'Vigyan Veera',
      main: Color(0xFF0E7490), accent: Color(0xFFF0F9FF), emblem: 'atom',
      skin: Color(0xFFC68642), hair: Color(0xFF1C1917), mask: 'visor',
      keywords: ['science', 'vigyan']),
];

/// Any subject the list above doesn't know.
const HeroDef kFallbackHero = HeroDef(
    subject: 'Any subject', boyName: 'Vidya Veer', girlName: 'Vidya Veera',
    main: Color(0xFF4338CA), accent: Color(0xFFF9A8D4), emblem: 'book',
    skin: Color(0xFFC68642), hair: Color(0xFF1C1917), mask: 'domino',
    keywords: []);

/// The hero for a subject name as it comes from the dashboard.
HeroDef heroForSubject(String subject) {
  final s = ' ${subject.trim().toLowerCase()} ';
  if (s.trim().isEmpty) return kFallbackHero;
  for (final h in kHeroes) {
    for (final k in h.keywords) {
      if (s.contains(k)) return h;
    }
  }
  return kFallbackHero;
}

/// Which version(s) to show for a profile gender.
enum HeroGender { boy, girl, team }

HeroGender heroGenderFor(String? profileGender) {
  switch ((profileGender ?? '').trim().toLowerCase()) {
    case 'male':
      return HeroGender.boy;
    case 'female':
      return HeroGender.girl;
    default:
      return HeroGender.team; // 'Other' → boy + girl hero team
  }
}

String heroName(HeroDef h, HeroGender g) {
  switch (g) {
    case HeroGender.boy:
      return h.boyName;
    case HeroGender.girl:
      return h.girlName;
    case HeroGender.team:
      return '${h.boyName} & ${h.girlName}';
  }
}

/// Costume level 0..4 ↔ 20 / 40 / 60 / 80 / 100 % dressed.
const List<int> kCostumePct = [20, 40, 60, 80, 100];
