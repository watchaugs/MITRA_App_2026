// ════════════════════════════════════════════════════════════
// SCREEN A-04: Parental Consent — DPDPA 2023
// Shown ONCE after first login, before home screen.
// Consent flag: SharedPreferences key 'consentGiven'
// Design: follows MITRA design system exactly
// ════════════════════════════════════════════════════════════

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/colors.dart';
import '../../stores/auth_store.dart';
import '../../widgets/mitra_scaffold.dart';
import '../../services/api_service.dart';
import '../../theme/theme_provider.dart';

// ── Constants ────────────────────────────────────────────────

abstract class ConsentKeys {
  static const consentGiven = 'consentGiven';
  static const consentDate = 'consentDate';
}

abstract class ConsentRoutes {
  static const onboarding = '/onboarding';
}

// ── Data model ───────────────────────────────────────────────

class _DataItem {
  final IconData icon;
  final Color color;
  final String label;

  const _DataItem({
    required this.icon,
    required this.color,
    required this.label,
  });
}

// ── Static data (no rebuilds, no allocations) ───────────────

const _kCollectionItems = [
  _DataItem(
      icon: Icons.quiz_outlined,
      color: MitraColors.saffron,
      label: 'Quiz scores & attempts'),
  _DataItem(
      icon: Icons.view_in_ar_outlined,
      color: MitraColors.sky,
      label: 'AR session duration & topics viewed'),
  _DataItem(
      icon: Icons.access_time_outlined,
      color: MitraColors.emerald,
      label: 'Time spent learning per subject'),
  _DataItem(
      icon: Icons.phone_android_outlined,
      color: MitraColors.gold,
      label: 'Device type & connectivity (rural/urban)'),
  _DataItem(
      icon: Icons.location_on_outlined,
      color: MitraColors.crimson,
      label: 'State & district (not GPS location)'),
];

const _kReasonItems = [
  _DataItem(
      icon: Icons.trending_up_outlined,
      color: MitraColors.emerald,
      label: 'Track your learning progress'),
  _DataItem(
      icon: Icons.dashboard_outlined,
      color: MitraColors.indigoLight,
      label: 'Anonymised reports to Ministry of Education'),
  _DataItem(
      icon: Icons.security_outlined,
      color: MitraColors.sky,
      label: 'Improve app quality & safety'),
];

const _kRights = [
  'Access your data anytime from Profile',
  'Request deletion — erased within 72 hours',
  'Withdraw consent — account will be deactivated',
  'Data never sold to third parties',
  'All data encrypted at rest and in transit',
];

// ── Consent persistence (isolated, testable) ────────────────

class _ConsentPersistence {
  const _ConsentPersistence();

  Future<bool> saveConsent({String? uid}) async {
    try {
      // 1. Save locally first — no network dependency
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool(ConsentKeys.consentGiven, true),
        prefs.setString(
            ConsentKeys.consentDate, DateTime.now().toIso8601String()),
      ]);

      // 2. Register with backend dashboard (best-effort)
      try {
        if (uid != null) {
          await ConsentAPI.grant(uid, [
            'data_collection', // mandatory
            'analytics', // optional
            'communications', // optional
          ]);
        }
      } catch (e) {
        debugPrint(
            '⚠️ ConsentAPI.grant failed: $e — proceeding with local save');
      }

      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> clearConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(ConsentKeys.consentGiven);
      return true;
    } on Exception {
      return false;
    }
  }
}

// ── Screen ──────────────────────────────────────────────────

class ConsentScreen extends ConsumerStatefulWidget {
  final String nextRoute;

  const ConsentScreen({super.key, required this.nextRoute});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  // State
  bool _parentConsent = false;
  bool _termsAccepted = false;
  bool _isSubmitting = false;
  bool _checking = true;
  String? _errorMessage;

  // Dependency
  final _persistence = const _ConsentPersistence();

  // Gesture recognizers — created once in initState, disposed properly
  // (original code created new instances every build → memory leak)
  late final TapGestureRecognizer _dpdpaTap;
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  bool get _canProceed => _parentConsent && _termsAccepted && !_isSubmitting;

  @override
  void initState() {
    super.initState();
    _dpdpaTap = TapGestureRecognizer()..onTap = _showDpdpaInfo;
    _termsTap = TapGestureRecognizer()..onTap = _showTerms;
    _privacyTap = TapGestureRecognizer()..onTap = _showPrivacy;
    _checkBackendConsent();
  }

  Future<void> _checkBackendConsent() async {
    try {
      final res = await ConsentAPI.status()
          .timeout(const Duration(seconds: 4)); // never hang
      final consentRequired = res.data['consent_required'] as bool? ?? true;
      if (!consentRequired && mounted) {
        context.go(widget.nextRoute);
        return;
      }
    } catch (_) {
      // API unreachable, 401, or timeout — fall back to local
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getBool(ConsentKeys.consentGiven) ?? false) && mounted) {
        context.go(widget.nextRoute);
        return;
      }
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _dpdpaTap.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  // ── Navigation callbacks (TODO: wire to actual sheets) ──

  void _showDpdpaInfo() {
    // TODO: show DPDPA bottom sheet or navigate
  }

  void _showTerms() {
    // TODO: show Terms bottom sheet or navigate
  }

  void _showPrivacy() {
    // TODO: show Privacy bottom sheet or navigate
  }

  // ── Actions ──

  Future<void> _acceptAndContinue() async {
    if (!_canProceed) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final success =
        await _persistence.saveConsent(uid: ref.read(currentUserProvider)?.id);

    if (!mounted) return;

    if (success) {
      context.go(widget.nextRoute);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _decline() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    await _persistence.clearConsent();
    ref.read(authProvider.notifier).logout();

    if (!mounted) return;
    context.go(ConsentRoutes.onboarding);
  }

  // ── Checkbox handlers ──

  void _onParentConsentChanged(bool? value) {
    if (value == null || _isSubmitting) return;
    setState(() => _parentConsent = value);
  }

  void _onTermsConsentChanged(bool? value) {
    if (value == null || _isSubmitting) return;
    setState(() => _termsAccepted = value);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const MitraScaffold(
        body: Center(
          child: CircularProgressIndicator(color: MitraColors.saffron),
        ),
      );
    }

    return MitraScaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _GlassSection(
                        title: '📋  What MITRA Collects',
                        items: _kCollectionItems),
                    const SizedBox(height: 10),
                    const _GlassSection(
                        title: '🎯  Why We Collect It', items: _kReasonItems),
                    const SizedBox(height: 10),
                    const _RightsSection(rights: _kRights),
                    const SizedBox(height: 20),

                    _ConsentCheckbox(
                      value: _parentConsent,
                      onChanged: _onParentConsentChanged,
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontFamily: 'Mukta',
                            fontSize: 13,
                            color: MitraColors.textSecondary,
                            height: 1.5,
                          ),
                          children: [
                            const TextSpan(
                              text:
                                  'I confirm I am a parent/guardian (or above 18) and '
                                  'consent to MITRA collecting my child\'s learning data '
                                  'as described above under ',
                            ),
                            TextSpan(
                              text: 'DPDPA 2023',
                              style: const TextStyle(
                                color: MitraColors.saffron,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: MitraColors.saffron,
                              ),
                              recognizer: _dpdpaTap,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    _ConsentCheckbox(
                      value: _termsAccepted,
                      onChanged: _onTermsConsentChanged,
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontFamily: 'Mukta',
                            fontSize: 13,
                            color: MitraColors.textSecondary,
                            height: 1.5,
                          ),
                          children: [
                            const TextSpan(
                                text: 'I have read and agree to the '),
                            TextSpan(
                              text: 'Terms of Use',
                              style: const TextStyle(
                                color: MitraColors.saffron,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: MitraColors.saffron,
                              ),
                              recognizer: _termsTap,
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: const TextStyle(
                                color: MitraColors.saffron,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: MitraColors.saffron,
                              ),
                              recognizer: _privacyTap,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),

                    // Error banner (only when present)
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _errorMessage!),
                    ],

                    const SizedBox(height: 28),
                    _PrimaryActionButton(
                      enabled: _canProceed,
                      isLoading: _isSubmitting,
                      onPressed: _acceptAndContinue,
                    ),
                    const SizedBox(height: 12),
                    _GhostButton(
                      enabled: !_isSubmitting,
                      onPressed: _decline,
                      label: 'Decline & Sign Out',
                    ),
                    const SizedBox(height: 8),
                    const _DeclineHint(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Sub-widgets — each owns one visual section
// ════════════════════════════════════════════════════════════

/// Top header with shield icon, title, and MoE badge.
class _Header extends StatelessWidget {
  const _Header();

  static const _headerBg = Color(0x14FFFFFF); // 0.08 opacity
  static const _borderColor = Color(0x26FFFFFF); // 0.15 opacity

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _headerBg,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: _borderColor, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ShieldIcon(),
              SizedBox(width: 14),
              Expanded(
                child: _TitleColumn(),
              ),
              _MoeBadge(),
            ],
          ),
          SizedBox(height: 14),
          Text(
            'MITRA collects learning data under the Digital Personal Data '
            'Protection Act, 2023 (DPDPA). Please read and confirm below '
            'before continuing.',
            style: TextStyle(
              fontFamily: 'Mukta',
              fontSize: 13,
              color: MitraColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShieldIcon extends StatelessWidget {
  const _ShieldIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: MitraColors.saffron.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(MitraRadius.sm),
        border: Border.all(color: MitraColors.saffron.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.shield_outlined,
          color: MitraColors.saffron, size: 24),
    );
  }
}

class _TitleColumn extends StatelessWidget {
  const _TitleColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data & Privacy',
          style: TextStyle(
            fontFamily: 'Mukta',
            fontSize: 12,
            letterSpacing: 1.2,
            color: MitraColors.textMuted,
          ),
        ),
        Text(
          'Consent Required',
          style: TextStyle(
            fontFamily: 'Baloo2',
            fontWeight: FontWeight.w800,
            fontSize: 26,
            color: MitraColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _MoeBadge extends StatelessWidget {
  const _MoeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: MitraColors.saffron.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(MitraRadius.pill),
        border: Border.all(color: MitraColors.saffron.withValues(alpha: 0.4)),
      ),
      child: const Text(
        '🇮🇳  MoE',
        style: TextStyle(
          fontFamily: 'Mukta',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: MitraColors.saffron,
        ),
      ),
    );
  }
}

/// Glass card showing a list of data items (collection or reasons).
class _GlassSection extends StatelessWidget {
  final String title;
  final List<_DataItem> items;

  const _GlassSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MitraSpacing.lg),
      decoration: BoxDecoration(
        color: ThemeHelper.ctxGlassFill(context),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(color: ThemeHelper.ctxGlassBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: MitraColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => _DataRow(item: item)),
        ],
      ),
    );
  }
}

/// Single row: coloured icon + label.
class _DataRow extends StatelessWidget {
  final _DataItem item;
  const _DataRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MitraRadius.xs),
            ),
            child: Icon(item.icon, color: item.color, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.label,
              style: const TextStyle(
                fontFamily: 'Mukta',
                fontSize: 13,
                color: MitraColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Emerald-tinted rights section.
class _RightsSection extends StatelessWidget {
  final List<String> rights;
  const _RightsSection({required this.rights});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MitraSpacing.lg),
      decoration: BoxDecoration(
        color: MitraColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(color: MitraColors.emerald.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  color: MitraColors.emerald, size: 16),
              SizedBox(width: 8),
              Text(
                'Your Rights under DPDPA 2023',
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: MitraColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rights.map((text) => _RightRow(text: text)),
        ],
      ),
    );
  }
}

class _RightRow extends StatelessWidget {
  final String text;
  const _RightRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              color: MitraColors.emerald, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Mukta',
                fontSize: 12,
                color: MitraColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated checkbox container — highlights saffron when checked.
class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final Widget child;

  const _ConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? MitraColors.saffron.withValues(alpha: 0.07)
            : ThemeHelper.ctxGlassFill(context, dark: 0.05, light: 0.04),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(
          color: value
              ? MitraColors.saffron.withValues(alpha: 0.40)
              : ThemeHelper.ctxGlassBorder(context, dark: 0.12, light: 0.10),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: MitraColors.saffron,
              checkColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5)),
              side: BorderSide(
                  color: ThemeHelper.ctxGlassBorder(context,
                      dark: 0.3, light: 0.25),
                  width: 1.5),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Saffron pill — primary CTA.
class _PrimaryActionButton extends StatelessWidget {
  final bool enabled;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryActionButton({
    required this.enabled,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: MitraColors.saffron,
          disabledBackgroundColor: MitraColors.saffron.withValues(alpha: 0.30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MitraRadius.pill),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'Baloo2',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : const Text(
                'I Agree — Continue to MITRA',
                style: TextStyle(color: Colors.white),
              ),
      ),
    );
  }
}

/// Outlined ghost button — decline action.
class _GhostButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;
  final String label;

  const _GhostButton({
    required this.enabled,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MitraRadius.pill),
            side: BorderSide(color: ThemeHelper.ctxGlassBorder(context)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Mukta',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: MitraColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Error message shown below checkboxes.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MitraColors.crimson.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MitraRadius.sm),
        border: Border.all(color: MitraColors.crimson.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: MitraColors.crimson, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Mukta',
                fontSize: 13,
                color: MitraColors.crimson,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small hint text below decline button.
class _DeclineHint extends StatelessWidget {
  const _DeclineHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Declining will sign you out. You can re-consent on next login.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Mukta',
          fontSize: 11,
          color: MitraColors.textMuted,
        ),
      ),
    );
  }
}
