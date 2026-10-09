import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../constants/colors.dart';
import '../../stores/auth_store.dart';

const _kFirestoreTimeout = Duration(seconds: 10);

// Reuse the SAME option lists as setup_screen.dart so nothing drifts.
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
const _kGenders = ['Male', 'Female', 'Other'];
const _kMobileOwners = ['Mother', 'Father', 'Self', 'Other'];
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
const _kLanguages = [
  ('hi', 'हिंदी'),
  ('en', 'English'),
  ('ta', 'தமிழ்'),
  ('te', 'తెలుగు'),
  ('kn', 'ಕನ್ನಡ'),
  ('bn', 'বাংলা'),
  ('mr', 'मराठी'),
  ('gu', 'ગુજ.'),
];

/// How many days the class stays locked after a change.
const int kClassLockDays = 90;

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _name;
  String _avatar = '👨‍🎓';
  String _lang = 'hi';
  String _gender = '';
  String _mobileOwner = '';
  String _class = '';

  DateTime? _classLockedAt; // read from Firestore
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    _name = TextEditingController(text: u?.fullName ?? '');
    _avatar = u?.avatarEmoji ?? '👨‍🎓';
    _lang = u?.languagePreference ?? 'hi';
    _gender = u?.gender ?? '';
    _mobileOwner = u?.mobileBelongsTo ?? '';
    _class = u?.classGrade ?? '';
    _loadLockTimestamp();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
      app: Firebase.app(), databaseId: '(default)');

  Future<void> _loadLockTimestamp() async {
    final uid = ref.read(currentUserProvider)?.id;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await _db.collection('users').doc(uid).get().timeout(
            _kFirestoreTimeout,
          );
      final ts = doc.data()?['class_locked_at'];
      if (ts is Timestamp) _classLockedAt = ts.toDate();
    } catch (_) {
      // If we can't read it, we fail SAFE: treat class as locked so a
      // student can't bypass the rule just because the read failed.
      _classLockedAt = DateTime.now();
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _daysRemaining {
    if (_classLockedAt == null) return 0;
    final unlockDate =
        _classLockedAt!.add(const Duration(days: kClassLockDays));
    final diff = unlockDate.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  bool get _classLocked => _daysRemaining > 0;

  Future<void> _save() async {
    final uid = ref.read(currentUserProvider)?.id;
    final user = ref.read(currentUserProvider);
    if (uid == null || user == null) return;

    final newName = _name.text.trim();
    if (newName.length < 2) {
      _toast('Name must be at least 2 characters.');
      return;
    }

    final classChanged = _class != (user.classGrade ?? '');

    // Guard: if class changed but is locked, block and explain.
    if (classChanged && _classLocked) {
      _toast('Class can be changed again in $_daysRemaining days.');
      return;
    }

    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'full_name': newName,
        'avatar_emoji': _avatar,
        'language_preference': _lang,
        if (_gender.isNotEmpty) 'gender': _gender,
        if (_mobileOwner.isNotEmpty) 'mobile_belongs_to': _mobileOwner,
      };
      // Only touch class + lock timestamp when it actually changed and is allowed.
      if (classChanged && !_classLocked) {
        data['class_grade'] = _class;
        data['class_locked_at'] = FieldValue.serverTimestamp();
      }

      await _db.collection('users').doc(uid).update(data).timeout(
            _kFirestoreTimeout,
          );

      ref.read(authProvider.notifier).updateUser(user.copyWith(
            fullName: newName,
            avatarEmoji: _avatar,
            languagePreference: _lang,
            gender: _gender.isNotEmpty ? _gender : null,
            mobileBelongsTo: _mobileOwner.isNotEmpty ? _mobileOwner : null,
            classGrade:
                (classChanged && !_classLocked) ? _class : user.classGrade,
          ));

      if (mounted) {
        _toast('Profile updated.');
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      _toast('Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // Shows the warning BEFORE letting the student pick a new class.
  Future<void> _onTapClass() async {
    if (_classLocked) {
      // Inside the window → block + show days remaining.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MitraColors.bgCard,
          title: const Text('Class locked'),
          content: Text(
            'You changed your class recently. To keep your learning path '
            'stable, class can only be changed once every $kClassLockDays days.\n\n'
            'You can change it again in $_daysRemaining days.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Allowed → warn about the effect, then let them pick.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MitraColors.bgCard,
        title: const Text('Change class?'),
        content: const Text(
          'Changing your class updates the subjects, topics and quizzes shown '
          'to you. Your XP and badges are kept, but your learning path will '
          'reset to the new class.\n\n'
          'You can change class again only after $kClassLockDays days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MitraColors.bgCard,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _kClasses
              .map((c) => ListTile(
                    title: Text(c),
                    trailing: c == _class
                        ? const Icon(Icons.check, color: MitraColors.emerald)
                        : null,
                    onTap: () => Navigator.pop(ctx, c),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null) setState(() => _class = picked);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Edit Profile',
            style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: FontWeight.w800,
                color: onSurface)),
        iconTheme: IconThemeData(color: onSurface),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(MitraSpacing.lg),
                children: [
                  // Name
                  _label('Name', onSurface),
                  TextField(
                    controller: _name,
                    style: TextStyle(color: onSurface),
                    decoration: _boxDeco('Your name', onSurface),
                  ),
                  const SizedBox(height: 20),

                  // Avatar
                  _label('Avatar', onSurface),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kAvatars.map((a) {
                      final sel = a == _avatar;
                      return GestureDetector(
                        onTap: () => setState(() => _avatar = a),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: sel
                                ? MitraColors.saffron.withValues(alpha: 0.2)
                                : onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: sel
                                    ? MitraColors.saffron
                                    : onSurface.withValues(alpha: 0.15)),
                          ),
                          child: Text(a, style: const TextStyle(fontSize: 28)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Language
                  _label('Language', onSurface),
                  _chips(
                    _kLanguages.map((l) => l.$1).toList(),
                    _lang,
                    (v) => setState(() => _lang = v),
                    onSurface,
                    labelFor: (code) =>
                        _kLanguages.firstWhere((l) => l.$1 == code).$2,
                  ),
                  const SizedBox(height: 20),

                  // Gender
                  _label('Gender', onSurface),
                  _chips(_kGenders, _gender, (v) => setState(() => _gender = v),
                      onSurface),
                  const SizedBox(height: 20),

                  // Mobile belongs to
                  _label('Mobile belongs to', onSurface),
                  _chips(_kMobileOwners, _mobileOwner,
                      (v) => setState(() => _mobileOwner = v), onSurface),
                  const SizedBox(height: 20),

                  // Class (gated)
                  _label('Class', onSurface),
                  GestureDetector(
                    onTap: _onTapClass,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: onSurface.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _class.isEmpty ? 'Select class' : _class,
                              style: TextStyle(
                                  color: onSurface, fontFamily: 'Baloo2'),
                            ),
                          ),
                          if (_classLocked)
                            Row(children: [
                              const Icon(Icons.lock,
                                  size: 16, color: MitraColors.textMuted),
                              const SizedBox(width: 4),
                              Text('$_daysRemaining d',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: MitraColors.textMuted)),
                            ])
                          else
                            Icon(Icons.chevron_right,
                                color: onSurface.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  ),
                  if (_classLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Class can be changed again in $_daysRemaining days.',
                        style: const TextStyle(
                            fontSize: 12, color: MitraColors.textMuted),
                      ),
                    ),
                  const SizedBox(height: 32),

                  // Save
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MitraColors.saffron,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(MitraRadius.pill)),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save',
                              style: TextStyle(
                                  fontFamily: 'Baloo2',
                                  fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _label(String t, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: c.withValues(alpha: 0.8))),
      );

  InputDecoration _boxDeco(String hint, Color c) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.withValues(alpha: 0.4)),
        filled: true,
        fillColor: c.withValues(alpha: 0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.withValues(alpha: 0.15))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.withValues(alpha: 0.15))),
      );

  Widget _chips(
    List<String> items,
    String selected,
    ValueChanged<String> onPick,
    Color c, {
    String Function(String)? labelFor,
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          final sel = item == selected;
          return GestureDetector(
            onTap: () => onPick(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: sel
                    ? MitraColors.saffron.withValues(alpha: 0.2)
                    : c.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(MitraRadius.pill),
                border: Border.all(
                    color:
                        sel ? MitraColors.saffron : c.withValues(alpha: 0.15)),
              ),
              child: Text(labelFor != null ? labelFor(item) : item,
                  style:
                      TextStyle(color: c, fontFamily: 'Mukta', fontSize: 14)),
            ),
          );
        }).toList(),
      );
}
