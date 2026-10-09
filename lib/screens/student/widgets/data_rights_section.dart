import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/colors.dart';
import '../../../stores/auth_store.dart';

/// DPDPA data-rights controls: request a copy of your data, or request account
/// + data deletion. Both write to Firestore `data_requests` (one pending per
/// type); the compliance team actions them from the dashboard. No data is
/// deleted on-device here.
class DataRightsSection extends ConsumerStatefulWidget {
  const DataRightsSection({super.key});
  @override
  ConsumerState<DataRightsSection> createState() => _DataRightsSectionState();
}

class _DataRightsSectionState extends ConsumerState<DataRightsSection> {
  bool _submitting = false;

  FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
      app: Firebase.app(), databaseId: '(default)');

  Future<void> _submitRequest(String type) async {
    final user = ref.read(currentUserProvider);
    final uid = user?.id;
    if (uid == null) {
      _toast('Please sign in again.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _db.collection('data_requests').doc('${uid}_$type').set({
        'student_id': uid,
        'type': type, // 'export' | 'deletion'
        'status': 'pending',
        'requested_at': FieldValue.serverTimestamp(),
        'student_name': user?.fullName,
        'state': user?.assignedState,
        'class': user?.classGrade,
      });
      _toast(type == 'deletion'
          ? 'Deletion request submitted. Our team will process it per DPDPA.'
          : 'Data copy request submitted. We will prepare your data per DPDPA.');
    } catch (_) {
      _toast('Could not submit. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmExport() async {
    final ok = await _confirm(
      title: 'Download my data',
      message:
          'We will prepare a copy of your MITRA data (profile and learning '
          'progress) and share it with you. Under the DPDPA you have the right '
          'to a copy of your personal data.',
      confirmLabel: 'Request copy',
      danger: false,
    );
    if (ok == true) _submitRequest('export');
  }

  Future<void> _confirmDeletion() async {
    final ok = await _confirm(
      title: 'Delete my account',
      message:
          'This requests permanent deletion of your MITRA account and learning '
          'data (profile, XP, progress, quiz history). This cannot be undone '
          'once processed. Some records may be retained in anonymised form '
          'where the law requires.',
      confirmLabel: 'Request deletion',
      danger: true,
    );
    if (ok == true) _submitRequest('deletion');
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required bool danger,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MitraColors.bgCard,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: TextStyle(
                    color: danger ? MitraColors.crimson : MitraColors.saffron,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Widget tile({
      required String emoji,
      required String label,
      required VoidCallback? onTap,
      Color? labelColor,
    }) =>
        ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 20)),
          title: Text(label,
              style: TextStyle(
                  fontFamily: 'Mukta',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: labelColor ?? onSurface)),
          trailing: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.chevron_right,
                  color: onSurface.withValues(alpha: 0.4)),
          onTap: _submitting ? null : onTap,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6, top: 8),
          child: Text('ACCOUNT & DATA',
              style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 11,
                  letterSpacing: 1,
                  color: onSurface.withValues(alpha: 0.5))),
        ),
        Container(
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(MitraRadius.md),
            border: Border.all(color: onSurface.withValues(alpha: 0.12)),
          ),
          child: Column(children: [
            tile(emoji: '⬇️', label: 'Download my data', onTap: _confirmExport),
            tile(
                emoji: '🗑️',
                label: 'Delete my account',
                labelColor: MitraColors.crimson,
                onTap: _confirmDeletion),
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Your rights under the Digital Personal Data Protection Act, 2023.',
            style: TextStyle(
                fontFamily: 'Mukta',
                fontSize: 11,
                color: onSurface.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }
}
