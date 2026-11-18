// ═══════════════════════════════════════════════════════════════════════════
// Shown instead of every student screen while the home-state rule locks the
// app (outside the home state, or location can't be confirmed and the grace
// period is over), and for an unsaved lesson during grace (?reason=unsaved).
//
// Only what the law requires stays open here: consent withdrawal, data export
// / deletion requests, the grievance officer and legal pages, and sign-out.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/colors.dart';
import '../../providers/tr_ext.dart';
import '../../services/geo_state_service.dart';
import '../../stores/auth_store.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/mitra_scaffold.dart';
import 'widgets/consent_manager.dart';
import 'widgets/data_rights_section.dart';

class TerritoryLockScreen extends ConsumerWidget {
  final String reason; // '' (locked) | 'unsaved' (grace, lesson not saved)
  const TerritoryLockScreen({super.key, this.reason = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geoAsync = ref.watch(geoStateProvider);
    final geo = geoAsync.valueOrNull;
    final home =
        ref.watch(currentUserProvider.select((u) => u?.assignedState ?? ''));
    final tp = ThemeHelper.ctxTextPrimary(context);
    final ts = ThemeHelper.ctxTextSecondary(context);
    final hl = Theme.of(context).colorScheme.primary;

    final unsaved = reason == 'unsaved';
    final checking = geoAsync.isLoading;
    final String icon;
    final String title;
    final String body;
    if (unsaved) {
      icon = '📦';
      title = context.tr(ref, 'terr_unsaved_title', 'Saved lessons only');
      body = context.trp(
          ref,
          'terr_unsaved_body',
          'Your location is not confirmed, so only lessons saved on this phone open. Turn on location in {state} to open this one.',
          {'state': home});
    } else if (checking && geo == null) {
      icon = '📍';
      title = context.tr(ref, 'terr_checking', 'Checking your location…');
      body = '';
    } else if (geo?.status == GeoStatus.outsideTerritory) {
      icon = '🧭';
      title = context.trp(ref, 'terr_outside_title',
          'MITRA works only in {state}', {'state': home});
      body = context.trp(
          ref,
          'terr_outside_body',
          'You are outside {state}, your registered state. Lessons, quizzes and syncing stay paused until you are back. Your progress is safe on this phone.',
          {'state': home});
    } else {
      icon = '📍';
      title = context.tr(ref, 'terr_need_location', 'Turn on location');
      body = context.trp(
          ref,
          'terr_need_location_body',
          'MITRA needs to confirm you are in {state} before lessons open. Turn on location and tap Check again.',
          {'state': home});
    }

    Widget card(Widget child) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelper.ctxGlassFill(context),
            borderRadius: BorderRadius.circular(MitraRadius.lg),
            border: Border.all(color: ThemeHelper.ctxGlassBorder(context)),
          ),
          // ListTiles inside need their own Material over this tinted box,
          // or their tap ripple is hidden (Flutter debug assertion).
          child: Material(type: MaterialType.transparency, child: child),
        );

    Widget link(String label, String route) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label,
              style: TextStyle(fontFamily: 'Mukta', color: tp, fontSize: 14)),
          trailing: Icon(Icons.chevron_right_rounded, color: ts),
          onTap: () => context.push(route),
        );

    return MitraScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          card(Column(children: [
            Text(icon, style: const TextStyle(fontSize: 46)),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: tp)),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 14,
                      color: ts,
                      height: 1.4)),
            ],
            const SizedBox(height: 14),
            if (unsaved)
              OutlinedButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/student/learn'),
                child: Text(context.tr(ref, 'terr_back', 'Back to lessons')),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: hl,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MitraRadius.pill))),
                onPressed: checking ? null : () => recheckTerritory(ref),
                icon: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                label: Text(context.tr(ref, 'terr_check_again', 'Check again'),
                    style: const TextStyle(
                        fontFamily: 'Baloo2', fontWeight: FontWeight.w700)),
              ),
          ])),
          if (!unsaved) ...[
            // ── Your data rights (always available, by law) ──
            card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr(ref, 'terr_rights', 'Your data rights'),
                  style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: tp)),
              const SizedBox(height: 6),
              const ConsentManager(),
              const SizedBox(height: 6),
              const DataRightsSection(),
              link(context.tr(ref, 'terr_grievance', 'Grievance officer'),
                  '/legal/grievance'),
              link(context.tr(ref, 'terr_privacy', 'Privacy policy'),
                  '/legal/privacy'),
              link(context.tr(ref, 'terr_terms', 'Terms of use'),
                  '/legal/terms'),
            ])),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: MitraColors.crimson,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MitraRadius.pill))),
                onPressed: () => ref.read(authProvider.notifier).logout(),
                child: Text(context.tr(ref, 'profile_sign_out', 'Sign Out'),
                    style: const TextStyle(
                        fontFamily: 'Baloo2', fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
