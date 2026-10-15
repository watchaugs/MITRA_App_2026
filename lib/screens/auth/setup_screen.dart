// ════════════════════════════════════════════════════════════
// SCREEN S-04: Profile Setup — 3-step wizard
// Step 1: Language, Step 2: Profile/Avatar, Step 3: Class
// After Step 3 → /location (new screen)
//
// Improvements:
//   • Typed data models replace raw maps
//   • Input sanitisation (length cap, control chars)
//   • Selection validated against allowed values
//   • Race-condition guard via _saveOpId
//   • Timeouts on all async I/O
//   • Only current step widget built (not all three)
//   • Proper buttons with Semantics, ripples, disabled states
//   • Inline error strip instead of blocking dialog
//   • No unused themeProvider watch
//   • No raw exceptions logged or shown
// ════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/colors.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../widgets/mitra_glass_card.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../stores/auth_store.dart';
import '../../providers/telemetry_provider.dart';
import '../../services/telemetry_enums.dart';
import '../../providers/translation_provider.dart'; // ✨ OTA TRANSLATION ENGINE

// ── Constants ────────────────────────────────────────────────

abstract class _SetupKeys {
  static const onboardingComplete = 'onboardingComplete';
  static const classLockedAt = 'classLockedAt';
}

abstract class _SetupRoutes {
  static const location = '/location';
  static const profile = '/student/profile';
}

const _kMaxNameLength = 50;
const _kFirestoreTimeout = Duration(seconds: 10);
const _kPrefsTimeout = Duration(seconds: 5);

// ── Data Models ──────────────────────────────────────────────

class _Language {
  final String code;
  final String nativeLabel;
  final String englishName;

  const _Language({
    required this.code,
    required this.nativeLabel,
    required this.englishName,
  });
}

const _kLanguages = [
  _Language(code: 'hi', nativeLabel: 'हिंदी', englishName: 'Hindi'),
  _Language(code: 'en', nativeLabel: 'English', englishName: 'English'),
  _Language(code: 'ta', nativeLabel: 'தமிழ்', englishName: 'Tamil'),
  _Language(code: 'te', nativeLabel: 'తెలుగు', englishName: 'Telugu'),
  _Language(code: 'kn', nativeLabel: 'ಕನ್ನಡ', englishName: 'Kannada'),
  _Language(code: 'bn', nativeLabel: 'বাংলা', englishName: 'Bengali'),
  _Language(code: 'mr', nativeLabel: 'मराठी', englishName: 'Marathi'),
  _Language(code: 'gu', nativeLabel: 'ગુજ.', englishName: 'Gujarati'),
];

const _kAvatars = [
  '👨‍🎓',
  '👩‍🎓',
  '🦸‍♂️',
  '🦸‍♀️',
  '🕵️‍♂️',
  '🕵️‍♀️',
  '👨‍🚀',
  '👩‍🚀',
  '🥷',
  '🧙‍♀️',
  '👨‍🎤',
  '👩‍🎤',
];

const _kGenders = ['Male', 'Female', 'Other'];

const _kMobileOwners = ['Mother', 'Father', 'Self', 'Other'];

const _kClasses = [
  'Class 1',
  'Class 2',
  'Class 3',
  'Class 4',
  'Class 5',
  'Class 6',
  'Class 7',
  'Class 8',
  'Class 9',
  'Class 10',
  'Class 11',
  'Class 12',
];

// ── Validation ───────────────────────────────────────────────

bool _isValidLanguage(String code) => _kLanguages.any((l) => l.code == code);
bool _isValidAvatar(String emoji) => _kAvatars.contains(emoji);
bool _isValidClass(String cls) => _kClasses.contains(cls);
bool _isValidGender(String gender) => _kGenders.contains(gender);
bool _isValidMobileOwner(String owner) => _kMobileOwners.contains(owner);

String _sanitiseName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  return cleaned.length > _kMaxNameLength
      ? cleaned.substring(0, _kMaxNameLength)
      : cleaned;
}

// ── Screen ──────────────────────────────────────────────────

class SetupScreen extends ConsumerStatefulWidget {
  final bool classOnly;
  const SetupScreen({super.key, this.classOnly = false});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int _step = 0;
  String _lang = 'hi';
  String _avatar = '👨‍🎓';
  String _cls = '';
  String _gender = '';
  String _mobileBelongsTo = '';
  bool _saving = false;
  String? _error;
  int _saveOpId = 0;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final existingUser = ref.read(currentUserProvider);
    _nameCtrl = TextEditingController(text: existingUser?.fullName ?? '');
    final existingGender = existingUser?.gender ?? '';
    if (_isValidGender(existingGender)) _gender = existingGender;
    final existingMobileOwner = existingUser?.mobileBelongsTo ?? '';
    if (_isValidMobileOwner(existingMobileOwner)) {
      _mobileBelongsTo = existingMobileOwner;
    }
    if (widget.classOnly) _step = 2;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Validation ──

  bool _validateCurrentStep() => switch (_step) {
        0 => _isValidLanguage(_lang),
        1 => _sanitiseName(_nameCtrl.text).isNotEmpty &&
            _isValidAvatar(_avatar) &&
            _isValidGender(_gender) &&
            _isValidMobileOwner(_mobileBelongsTo),
        2 => _isValidClass(_cls),
        _ => false,
      };

  bool get _canGoNext => _validateCurrentStep() && !_saving;

  // ── Navigation ──

  void _goNext() {
    if (!_canGoNext) return;
    if (_step < 2) {
      setState(() {
        _step++;
        _error = null;
      });
    } else {
      _saveAndContinue();
    }
  }

  void _goBack() {
    if (_step > 0) {
      setState(() {
        _step--;
        _error = null;
      });
    } else {
      context.pop();
    }
  }

  // ── Save ──

  Future<void> _saveAndContinue() async {
    final sanitisedName = _sanitiseName(_nameCtrl.text);
    // Gender / mobile-owner are collected during the full onboarding
    // wizard's Profile step. classOnly mode (re-picking class for an
    // already-onboarded user) never shows that step, so don't block that
    // flow on fields it never asked for — but do require them for anyone
    // going through full setup.
    final demographicsOk = widget.classOnly ||
        (_isValidGender(_gender) && _isValidMobileOwner(_mobileBelongsTo));
    if (sanitisedName.isEmpty || !_isValidClass(_cls) || !demographicsOk) {
      setState(() => _error = 'Please fill all fields correctly.');
      return;
    }

    final opId = ++_saveOpId;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('NO_USER');

      final firestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: '(default)',
      );

      final genderValid = _isValidGender(_gender);
      final mobileOwnerValid = _isValidMobileOwner(_mobileBelongsTo);

      await firestore.collection('app_users').doc(user.id).update({
        'language_preference': _lang,
        'avatar_emoji': _avatar,
        'full_name': sanitisedName,
        if (genderValid) 'gender': _gender,
        if (mobileOwnerValid) 'mobile_belongs_to': _mobileBelongsTo,
        'class_grade': _cls,
        'class_locked_at': FieldValue.serverTimestamp(),
      }).timeout(_kFirestoreTimeout);

      // Mirror the demographic fields into the `students` collection too —
      // that's what TelemetryService/StudentContext reads its analytics
      // dimensions from, so this is what makes gender / mobile ownership
      // actually eligible for reporting rather than just stored on the
      // user's profile.
      if (genderValid || mobileOwnerValid) {
        await firestore.collection('students').doc(user.id).set({
          if (genderValid) 'gender': _gender,
          if (mobileOwnerValid) 'mobile_ownership': _mobileBelongsTo,
        }, SetOptions(merge: true)).timeout(_kFirestoreTimeout);
      }

      ref.read(authProvider.notifier).updateUser(user.copyWith(
            languagePreference: _lang,
            avatarEmoji: _avatar,
            fullName: sanitisedName,
            gender: genderValid ? _gender : null,
            mobileBelongsTo: mobileOwnerValid ? _mobileBelongsTo : null,
            classGrade: _cls,
          ));

      // Reflect the new demographics in the *current* telemetry session
      // immediately (rather than waiting for the next TelemetryService
      // reload), then log that profile setup was completed.
      if (genderValid || mobileOwnerValid) {
        final telemetry = ref.read(telemetryServiceProvider);
        if (telemetry != null) {
          telemetry.updateDemographics(
            gender: genderValid ? _gender : null,
            mobileOwnership: mobileOwnerValid
                ? MobileOwnership.fromWire(_mobileBelongsTo)
                : null,
          );
          unawaited(telemetry.logProfileSetup(
            genderProvided: genderValid,
            mobileOwnershipProvided: mobileOwnerValid,
          ));
        }
      }

      final prefs =
          await SharedPreferences.getInstance().timeout(_kPrefsTimeout);
      await prefs.setBool(_SetupKeys.onboardingComplete, true);
      await prefs.setString(
          _SetupKeys.classLockedAt, DateTime.now().toIso8601String());

      if (opId != _saveOpId || !mounted) return;
      if (widget.classOnly) {
        context.go(_SetupRoutes.profile);
      } else {
        // ✨ Send directly to Location next. The Greeting should be the final step before Home!
        context.go(_SetupRoutes.location);
      }
    } on TimeoutException {
      if (opId != _saveOpId || !mounted) return;
      setState(() => _error = 'Server is taking too long. Please try again.');
    } catch (_) {
      if (opId != _saveOpId || !mounted) return;
      setState(() => _error = 'Could not save profile. Please try again.');
    } finally {
      if (opId == _saveOpId && mounted) setState(() => _saving = false);
    }
  }

  // ── Selection handlers ──

  void _selectLanguage(String code) {
    if (_saving) return;
    setState(() => _lang = code);
  }

  void _selectAvatar(String emoji) {
    if (_saving) return;
    setState(() => _avatar = emoji);
  }

  void _selectClass(String cls) {
    if (_saving) return;
    setState(() => _cls = cls);
  }

  void _selectGender(String gender) {
    if (_saving) return;
    setState(() => _gender = gender);
  }

  void _selectMobileOwner(String owner) {
    if (_saving) return;
    setState(() => _mobileBelongsTo = owner);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    if (widget.classOnly) {
      return _buildClassOnlyMode();
    }
    return _buildWizardMode();
  }

  Widget _buildClassOnlyMode() {
    return MitraScaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _ClassHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(MitraSpacing.lg),
                child: _ClassGrid(selectedClass: _cls, onSelect: _selectClass),
              ),
            ),
            if (_error != null) const _ErrorPlaceholder(),
            _BottomBar(
              canGoBack: true,
              canGoNext: _isValidClass(_cls) && !_saving,
              loading: _saving,
              onBack: () => context.pop(),
              onNext: _saveAndContinue,
              isLastStep: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWizardMode() {
    // ✨ Watch translation state for the loading spinner and text translation
    final translationState = ref.watch(translationProvider);
    final isBusy = _saving || translationState.isLoading;
    final t = ref.read(translationProvider.notifier);

    // Dynamically translate the progress bar labels
    final translatedStepLabels = [
      t.tr('step_language', 'Language'),
      t.tr('step_profile', 'Profile'),
      t.tr('step_class', 'Class'),
    ];

    return MitraScaffold(
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(labels: translatedStepLabels, currentStep: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(MitraSpacing.lg),
                child: switch (_step) {
                  0 => _LanguageStep(
                      selectedCode: _lang, onSelect: _selectLanguage),
                  1 => _ProfileStep(
                      nameController: _nameCtrl,
                      selectedAvatar: _avatar,
                      onAvatarTap: _selectAvatar,
                      selectedGender: _gender,
                      onGenderSelect: _selectGender,
                      selectedMobileOwner: _mobileBelongsTo,
                      onMobileOwnerSelect: _selectMobileOwner,
                    ),
                  2 => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _ClassHeader(),
                        const SizedBox(height: MitraSpacing.lg),
                        _ClassGrid(selectedClass: _cls, onSelect: _selectClass),
                      ],
                    ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
            if (_error != null) _ErrorStrip(message: _error!),
            _BottomBar(
              canGoBack: _step > 0,
              canGoNext: _canGoNext &&
                  !translationState.isLoading, // ✨ Lock button if loading
              loading: isBusy,
              onBack: _goBack,
              onNext: _goNext,
              isLastStep: _step == 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Step Indicator
// ════════════════════════════════════════════════════════════

class _StepIndicator extends StatelessWidget {
  final List<String> labels;
  final int currentStep;

  const _StepIndicator({required this.labels, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          MitraSpacing.lg, MitraSpacing.lg, MitraSpacing.lg, 0),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isCompleted = i < currentStep;
          final isCurrent = i == currentStep;
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    if (i > 0)
                      Expanded(
                          child: Container(
                        height: 1,
                        color: isCompleted
                            ? MitraColors.saffron
                            : Colors.white.withValues(alpha: 0.2),
                      )),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? MitraColors.emerald
                            : isCurrent
                                ? MitraColors.saffron
                                : Colors.white.withValues(alpha: 0.1),
                        border: Border.all(
                          color: isCompleted || isCurrent
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        isCompleted ? '✓' : '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Baloo2',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (i < labels.length - 1)
                      Expanded(
                          child: Container(
                        height: 1,
                        color: isCompleted
                            ? MitraColors.saffron
                            : Colors.white.withValues(alpha: 0.2),
                      )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 11,
                    color: isCurrent ? MitraColors.saffron : Colors.white70,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Step 1: Language
// ════════════════════════════════════════════════════════════

class _LanguageStep extends ConsumerWidget {
  // ✨ Upgraded to ConsumerWidget
  final String selectedCode;
  final ValueChanged<String> onSelect;

  const _LanguageStep({required this.selectedCode, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationProvider.notifier); // ✨ Translation Engine

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.tr('select_language_title', 'Select Your Language'),
            style: const TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
            )),
        const SizedBox(height: MitraSpacing.lg),
        Wrap(
          spacing: MitraSpacing.sm,
          runSpacing: MitraSpacing.sm,
          children: _kLanguages
              .map((lang) => MitraGlassCard(
                    title: lang.nativeLabel,
                    isSelected: selectedCode == lang.code,
                    activeColor: MitraColors.saffron,
                    onTap: () => onSelect(lang.code),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// Step 2: Profile
// ════════════════════════════════════════════════════════════

class _ProfileStep extends StatelessWidget {
  final TextEditingController nameController;
  final String selectedAvatar;
  final ValueChanged<String> onAvatarTap;
  final String selectedGender;
  final ValueChanged<String> onGenderSelect;
  final String selectedMobileOwner;
  final ValueChanged<String> onMobileOwnerSelect;

  const _ProfileStep({
    required this.nameController,
    required this.selectedAvatar,
    required this.onAvatarTap,
    required this.selectedGender,
    required this.onGenderSelect,
    required this.selectedMobileOwner,
    required this.onMobileOwnerSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose Your Avatar',
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
            )),
        const SizedBox(height: MitraSpacing.md),
        Wrap(
          spacing: MitraSpacing.sm,
          runSpacing: MitraSpacing.sm,
          children: _kAvatars
              .map((emoji) => _AvatarTile(
                    emoji: emoji,
                    isSelected: selectedAvatar == emoji,
                    onTap: () => onAvatarTap(emoji),
                  ))
              .toList(),
        ),
        const SizedBox(height: MitraSpacing.lg),
        const Text('Your Name',
            style: TextStyle(
              fontFamily: 'Mukta',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.white70,
              letterSpacing: 1,
            )),
        const SizedBox(height: 8),
        TextField(
          controller: nameController,
          maxLength: _kMaxNameLength,
          style: const TextStyle(fontFamily: 'Mukta', color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Full name',
            hintStyle: const TextStyle(color: Colors.white54),
            counterStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              borderSide:
                  const BorderSide(color: MitraColors.saffron, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: MitraSpacing.lg),
        _LabeledDropdown(
          label: 'Gender',
          hint: 'Select gender',
          value: selectedGender,
          options: _kGenders,
          onChanged: onGenderSelect,
        ),
        const SizedBox(height: MitraSpacing.lg),
        _LabeledDropdown(
          label: 'Mobile belongs to',
          hint: 'Select relation',
          value: selectedMobileOwner,
          options: _kMobileOwners,
          onChanged: onMobileOwnerSelect,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// Labeled Dropdown (Gender / Mobile-belongs-to)
// ════════════════════════════════════════════════════════════

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String hint;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Mukta',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.white70,
              letterSpacing: 1,
            )),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value.isEmpty ? null : value,
          isExpanded: true,
          dropdownColor: MitraColors.bgCard,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white70),
          style: const TextStyle(fontFamily: 'Mukta', color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              borderSide:
                  const BorderSide(color: MitraColors.saffron, width: 1.5),
            ),
          ),
          items: options
              .map((opt) => DropdownMenuItem<String>(
                    value: opt,
                    child: Text(opt),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ],
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  const _AvatarTile(
      {required this.emoji, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Avatar $emoji${isSelected ? ", selected" : ""}',
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MitraRadius.sm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              border: Border.all(
                color: isSelected
                    ? MitraColors.saffron
                    : Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 28)),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Step 3: Class
// ════════════════════════════════════════════════════════════

class _ClassHeader extends StatelessWidget {
  const _ClassHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Border(
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.15), width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select your Class',
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: FontWeight.w900,
                fontSize: 32,
                color: Colors.white,
                letterSpacing: -0.5,
              )),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MitraColors.saffron.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              border: Border.all(
                  color: MitraColors.saffron.withValues(alpha: 0.35)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_clock_outlined,
                    color: MitraColors.saffron, size: 18),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                  'Once selected, your class will be locked for 90 days. Choose carefully.',
                  style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 13,
                    color: MitraColors.saffron,
                    height: 1.4,
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassGrid extends StatelessWidget {
  final String selectedClass;
  final ValueChanged<String> onSelect;

  const _ClassGrid({required this.selectedClass, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: MitraSpacing.sm,
      mainAxisSpacing: MitraSpacing.sm,
      children: _kClasses
          .map((cls) => _ClassTile(
                number: cls,
                isSelected: selectedClass == cls,
                onTap: () => onSelect(cls),
              ))
          .toList(),
    );
  }
}

class _ClassTile extends StatelessWidget {
  final String number;
  final bool isSelected;
  final VoidCallback onTap;

  const _ClassTile(
      {required this.number, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Class $number${isSelected ? ", selected" : ""}',
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MitraRadius.sm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected
                  ? MitraColors.saffron.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(MitraRadius.sm),
              border: Border.all(
                color: isSelected
                    ? MitraColors.saffron
                    : Colors.white.withValues(alpha: 0.15),
                width: isSelected ? 2 : 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: MitraColors.saffron.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: isSelected ? 16 : 14,
                color: isSelected ? MitraColors.saffron : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Error Display
// ════════════════════════════════════════════════════════════

class _ErrorStrip extends StatelessWidget {
  final String message;
  const _ErrorStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: MitraSpacing.lg, vertical: 10),
      color: MitraColors.crimson.withValues(alpha: 0.10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: MitraColors.crimson, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 12,
                    color: MitraColors.crimson,
                  ))),
        ],
      ),
    );
  }
}

/// Placeholder for classOnly mode (error handled differently)
class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ════════════════════════════════════════════════════════════
// Bottom Bar
// ════════════════════════════════════════════════════════════

class _BottomBar extends ConsumerWidget {
  // ✨ Upgraded to ConsumerWidget
  final bool canGoBack;
  final bool canGoNext;
  final bool loading;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final bool isLastStep;

  const _BottomBar({
    required this.canGoBack,
    required this.canGoNext,
    required this.loading,
    required this.onBack,
    required this.onNext,
    required this.isLastStep,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationProvider.notifier); // ✨ Translation Engine

    return Padding(
      padding: const EdgeInsets.all(MitraSpacing.lg),
      child: Row(
        children: [
          if (canGoBack && onBack != null)
            Expanded(
              child: _GhostButton(
                label: t.tr('btn_back', '← Back'), // ✨ Translated
                enabled: !loading,
                onPressed: onBack!,
              ),
            )
          else if (canGoBack)
            const Expanded(child: SizedBox())
          else
            const SizedBox(),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _PrimaryButton(
              label: isLastStep
                  ? t.tr('btn_confirm_class', 'Confirm Class →')
                  : t.tr('btn_continue', 'Continue →'), // ✨ Translated
              enabled: canGoNext && !loading,
              loading: loading,
              onPressed: onNext,
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _GhostButton(
      {required this.label, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(MitraRadius.pill),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(MitraRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w700,
                  color: enabled ? Colors.white : Colors.white38,
                )),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(MitraRadius.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            decoration: BoxDecoration(
              gradient: enabled
                  ? const LinearGradient(colors: MitraColors.gradientSaffron)
                  : null,
              color:
                  enabled ? null : MitraColors.saffron.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(MitraRadius.pill),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: MitraColors.saffron.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(label,
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: enabled ? Colors.white : Colors.white54,
                    )),
          ),
        ),
      ),
    );
  }
}
