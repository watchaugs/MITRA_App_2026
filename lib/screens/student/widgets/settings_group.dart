import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../constants/colors.dart';
import '../../../providers/app_prefs.dart';

class SettingsGroup extends ConsumerWidget {
  const SettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final prefs = ref.watch(appPrefsProvider);

    Widget tile({
      required String emoji,
      required String label,
      Widget? trailing,
      VoidCallback? onTap,
    }) =>
        ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 20)),
          title: Text(label,
              style: TextStyle(
                  fontFamily: 'Mukta',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: onSurface)),
          trailing: trailing ??
              Icon(Icons.chevron_right,
                  color: onSurface.withValues(alpha: 0.4)),
          onTap: onTap,
        );

    Widget section(String heading, List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6, top: 8),
              child: Text(heading.toUpperCase(),
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
              child: Column(children: children),
            ),
            const SizedBox(height: 16),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── App settings ──
        section('App', [
          tile(
            emoji: '🔔',
            label: 'Notifications',
            trailing: Switch(
              value: prefs.notifications,
              onChanged: (v) =>
                  ref.read(appPrefsProvider.notifier).setNotifications(v),
            ),
          ),
          tile(
            emoji: '📉',
            label: 'Data saver',
            trailing: Switch(
              value: prefs.dataSaver,
              onChanged: (v) =>
                  ref.read(appPrefsProvider.notifier).setDataSaver(v),
            ),
          ),
        ]),

        // ── Progress shortcuts ──
        section('My Progress', [
          tile(
              emoji: '🏆',
              label: 'Achievements',
              onTap: () => context.push('/student/achievements')),
          tile(
              emoji: '📊',
              label: 'Ranks',
              onTap: () {
                // Ranks lives inside the shell; adjust if your route differs.
                context.push('/student/achievements');
              }),
        ]),

        // ── Legal & privacy (Sections 3 + 4) ──
        section('Legal & Privacy', [
          tile(
              emoji: '📄',
              label: 'Privacy Policy',
              onTap: () => context.push('/legal/privacy')),
          tile(
              emoji: '📃',
              label: 'Terms of Use',
              onTap: () => context.push('/legal/terms')),
          tile(
              emoji: '⚖️',
              label: 'Grievance & Data Protection',
              onTap: () => context.push('/legal/grievance')),
        ]),

        // ── Support ──
        section('Support', [
          tile(
              emoji: '❓', label: 'Help & FAQ', onTap: () => _showHelp(context)),
          tile(
              emoji: '🐞',
              label: 'Report a problem',
              onTap: () async {
                final uri = Uri.parse(
                    'mailto:support@mitra.gov.in?subject=MITRA%20App%20Issue');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }),
          tile(emoji: 'ℹ️', label: 'About', onTap: () => _showAbout(context)),
        ]),
      ],
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MitraColors.bgCard,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(MitraSpacing.lg),
          children: const [
            Text('Help & FAQ',
                style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
            SizedBox(height: 12),
            _Faq('How do I take a quiz?',
                'Open the Learn tab, pick a subject, tap any quiz card, and answer each question. You will see an explanation after every answer.'),
            _Faq('How do I earn XP?',
                'You earn XP by completing quizzes and viewing 3D AR lessons. Your total XP shows on your profile.'),
            _Faq('Why can I change my class only once in 90 days?',
                'Your class sets your learning path. To keep it stable, class changes are limited to once every 90 days.'),
            _Faq('How do I change the app language or theme?',
                'Go to Profile → Edit Profile for language, and Profile → Themes for appearance.'),
          ],
        ),
      ),
    );
  }

  Future<void> _showAbout(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'MITRA',
      applicationVersion: 'v${info.version} (${info.buildNumber})',
      applicationLegalese:
          'An educational initiative. Built for students under the '
          'MITRA AR-learning program.',
      children: const [
        SizedBox(height: 12),
        Text(
          'MITRA delivers curriculum-aligned lessons, 3D AR content, and '
          'quizzes for school students. Your data is handled under the DPDPA, 2023.',
        ),
      ],
    );
  }
}

class _Faq extends StatelessWidget {
  final String q, a;
  const _Faq(this.q, this.a);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q,
                style: const TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const SizedBox(height: 4),
            Text(a, style: const TextStyle(fontFamily: 'Mukta', fontSize: 13)),
          ],
        ),
      );
}
