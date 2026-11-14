import 'package:flutter/material.dart';
import '../../providers/tr_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/colors.dart';
import '../../stores/auth_store.dart';

class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MitraSpacing.xl),
              decoration: const BoxDecoration(
                  gradient:
                      LinearGradient(colors: MitraColors.gradientTeacher)),
              child: Column(children: [
                Text(user?.avatarEmoji ?? '👩‍🏫',
                    style: const TextStyle(fontSize: 64)),
                const SizedBox(height: 8),
                Text(user?.fullName ?? '',
                    style: const TextStyle(
                        fontFamily: 'Baloo2',
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: MitraColors.textPrimary)),
                Text(context.trp(ref, 'teacher_teacher_v1', 'Teacher · {v1}', {'v1': '${user?.assignedState ?? ''}'}),
                    style: const TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 13,
                        color: MitraColors.textMuted)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(MitraSpacing.lg),
              child: Column(children: [
                _InfoRow(label: context.tr(ref, 'teacher_phone', 'Phone'), value: user?.phone ?? '—'),
                const SizedBox(height: 12),
                _InfoRow(label: context.tr(ref, 'teacher_state', 'State'), value: user?.assignedState ?? '—'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MitraColors.crimson,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(MitraRadius.pill)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    child: Text(context.tr(ref, 'profile_sign_out', 'Sign Out'),
                        style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(MitraSpacing.md),
        decoration: BoxDecoration(
            color: MitraColors.bgCard,
            borderRadius: BorderRadius.circular(MitraRadius.sm),
            border: Border.all(color: MitraColors.border)),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Mukta',
                  fontSize: 14,
                  color: MitraColors.textMuted)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Mukta',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: MitraColors.textPrimary)),
        ]),
      );
}
