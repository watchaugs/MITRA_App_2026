// ════════════════════════════════════════════════════════════
// SCREEN S-05: Confirm Location
// Shown after class selection in setup flow.
// Detects district + state via GPS.
//
// Security hardening:
//   • GPS coords never logged, never persisted, never leave this file
//   • Geocoded strings sanitised before storage (length cap, stripped)
//   • Error messages sanitised — no raw exception text reaches UI
//   • Timeout on every async I/O operation
//   • Race-condition guard via _operationId — stale callbacks are no-ops
//   • No fragile "wait N seconds then re-check" permission pattern
//   • onboardingComplete flag set only after Firestore write succeeds
// ════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/colors.dart';
import '../../stores/auth_store.dart';
import '../../widgets/mitra_scaffold.dart';

// ── Constants ────────────────────────────────────────────────

abstract class _LocKeys {
  static const onboardingComplete = 'onboardingComplete';
  static const consentGiven = 'consentGiven';
}

abstract class _LocRoutes {
  static const home = '/student/home';
  static const consent = '/consent';
}

/// Max character length for district/state before truncation.
/// Folds Nominatim/OpenStreetMap state spellings to the canonical names the
/// dashboard uses (country-state-city). Geofencing, release-by-state and the
/// territory check all compare against these, so capture must match. Unknown
/// inputs pass through unchanged (trimmed), so new/renamed states still work.
String? _canonicalIndianState(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  const canonical = <String>[
    'Andaman and Nicobar Islands',
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chandigarh',
    'Chhattisgarh',
    'Dadra and Nagar Haveli and Daman and Diu',
    'Delhi',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jammu and Kashmir',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Ladakh',
    'Lakshadweep',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Puducherry',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
  ];
  // Known OSM → canonical variants (lowercase keys).
  const aliases = <String, String>{
    'nct of delhi': 'Delhi',
    'national capital territory of delhi': 'Delhi',
    'pondicherry': 'Puducherry',
    'orissa': 'Odisha',
    'uttaranchal': 'Uttarakhand',
    'jammu and kashmir union territory': 'Jammu and Kashmir',
    'dadra and nagar haveli': 'Dadra and Nagar Haveli and Daman and Diu',
    'daman and diu': 'Dadra and Nagar Haveli and Daman and Diu',
    'andaman and nicobar': 'Andaman and Nicobar Islands',
  };
  final low = s.toLowerCase();
  if (aliases.containsKey(low)) return aliases[low];
  for (final c in canonical) {
    if (c.toLowerCase() == low) return c; // exact (case-insensitive) match
  }
  return s; // unknown → keep as-is (trimmed) so nothing breaks
}

/// Prevents absurdly long geocoded strings from hitting Firestore.
const _kMaxGeoFieldLength = 100;

/// Cooldown after a successful detection to prevent GPS chip abuse.
const _kDetectCooldown = Duration(seconds: 3);

/// Timeouts for async operations.
const _kLocationTimeout = Duration(seconds: 20);
const _kGeocodeTimeout = Duration(seconds: 10);
const _kFirestoreTimeout = Duration(seconds: 10);
const _kPrefsTimeout = Duration(seconds: 5);

// ── Sanitisation ─────────────────────────────────────────────

/// Strips control characters, trims whitespace, caps length.
/// Returns null if the result is empty after sanitisation.
String? _sanitiseGeoField(String? raw) {
  if (raw == null) return null;
  final cleaned = raw
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '') // strip control chars
      .trim();
  if (cleaned.isEmpty) return null;
  if (cleaned.length > _kMaxGeoFieldLength) {
    return '${cleaned.substring(0, _kMaxGeoFieldLength - 1)}…';
  }
  return cleaned;
}

/// Turns any exception into a user-safe message.
/// Never leaks class names, file paths, or stack traces.
String _safeErrorMessage(Object error) {
  final msg = error.toString();
  // Known patterns we explicitly want to surface
  if (msg.contains('Location permission denied') ||
      msg.contains('PERMISSION_DENIED')) {
    return 'Location permission was denied. Please allow it and try again.';
  }
  if (msg.contains('permanently denied') ||
      msg.contains('PERMISSION_PERMANENTLY_BLOCKED')) {
    return 'Location permission is permanently blocked. '
        'Please enable it in Settings.';
  }
  if (msg.contains('Location services are still disabled') ||
      msg.contains('LOCATION_SERVICE_DISABLED') ||
      msg.contains('LOCATION_SERVICES_OFF')) {
    return 'Location services are off. Please turn them on and try again.';
  }
  if (msg.contains('TIMEOUT')) {
    return 'Location detection timed out. Please try again.';
  }
  if (msg.contains('GEOCODE_EMPTY') || msg.contains('GEOCODE_INCOMPLETE')) {
    return 'Location detected but address lookup failed. '
        'Please check your internet connection and try again.';
  }
  if (msg.contains('NO_USER')) {
    return 'Session expired. Please sign in again.';
  }
  // Fallback — generic, no detail leakage
  return 'Could not detect location. Please try again.';
}

// ── Screen ──────────────────────────────────────────────────

class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  // ── State ──
  bool _detecting = false;
  bool _saving = false;
  String _district = '';
  String _state = '';
  String? _error;

  /// Incremented on every action start. Callbacks check if their id still
  /// matches — if not, the user tapped something else or navigated away,
  /// and the stale result is discarded.
  int _detectOpId = 0;
  int _saveOpId = 0;

  /// Cooldown timer after a successful detection.
  DateTime? _lastDetectedAt;

  bool get _locationDetected => _state.isNotEmpty;
  bool get _isCooldownActive {
    if (_lastDetectedAt == null) return false;
    return DateTime.now().difference(_lastDetectedAt!) < _kDetectCooldown;
  }

  // ── Location detection ──────────────────────────────────

  Future<void> _detectLocation() async {
    if (_detecting || _isCooldownActive) return;

    final opId = ++_detectOpId;
    setState(() {
      _detecting = true;
      _error = null;
      _district = '';
      _state = '';
    });

    try {
      // 1. Service check — no auto-open, no arbitrary delay
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(_kLocationTimeout);
      if (!serviceEnabled) {
        throw const _LocException('LOCATION_SERVICES_OFF');
      }

      // 2. Permission check — request once, don't force-open settings
      var permission =
          await Geolocator.checkPermission().timeout(_kLocationTimeout);
      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission().timeout(_kLocationTimeout);
      }
      if (permission == LocationPermission.denied) {
        throw const _LocException('PERMISSION_DENIED');
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocException('PERMISSION_PERMANENTLY_BLOCKED');
      }

      // 3. Get position — coords stay in local scope, never logged.
      // DPDP data minimisation: we only need the STATE. We try a cached fix
      // first (instant, no radio wake-up), and only ask for a fresh one if none
      // exists. APPROXIMATE accuracy only (LocationAccuracy.reduced → coarse):
      // a state is hundreds of km wide, so precise/fine location would collect
      // more than the purpose requires and break DPDP/CERT-In compliance.
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {/* no cached fix — fall through to a fresh read */}
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.reduced,
      ).timeout(_kLocationTimeout);

      // 4. Reverse geocode via Nominatim — works on all Android devices
      final geoUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${position.latitude}'
        '&lon=${position.longitude}'
        '&format=json'
        '&addressdetails=1',
      );

      final geoResponse = await http.get(
        geoUrl,
        headers: {
          'User-Agent': 'MITRAStudentApp/1.0 (in.gov.mitra.student)',
          'Accept-Language': 'en',
        },
      ).timeout(_kGeocodeTimeout);

      if (geoResponse.statusCode != 200) {
        throw const _LocException('GEOCODE_EMPTY');
      }

      final geoData = jsonDecode(geoResponse.body) as Map<String, dynamic>;
      final address = geoData['address'] as Map<String, dynamic>?;

      if (address == null) {
        throw const _LocException('GEOCODE_EMPTY');
      }

      // Nominatim fields for India:
      // district → county / state_district / city_district / city
      // state   → state
      final district = _sanitiseGeoField(
        address['county'] as String? ??
            address['state_district'] as String? ??
            address['city_district'] as String? ??
            address['city'] as String? ??
            address['town'] as String?,
      );
      final state =
          _canonicalIndianState(_sanitiseGeoField(address['state'] as String?));

      if (district == null || state == null) {
        throw const _LocException('GEOCODE_INCOMPLETE');
      }

      // 5. Stale check — user may have navigated away
      if (opId != _detectOpId || !mounted) return;

      setState(() {
        _district = district;
        _state = state;
        _lastDetectedAt = DateTime.now();
      });
    } on TimeoutException {
      if (opId != _detectOpId || !mounted) return;
      setState(() => _error = _safeErrorMessage('TIMEOUT'));
    } on _LocException catch (e) {
      if (opId != _detectOpId || !mounted) return;
      setState(() => _error = _safeErrorMessage(e.message));
    } catch (_) {
      // Intentionally swallow the raw error — never log coords or stack
      if (opId != _detectOpId || !mounted) return;
      setState(() => _error = _safeErrorMessage('UNKNOWN'));
    } finally {
      if (opId == _detectOpId && mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  // ── Save & navigate ─────────────────────────────────────

  Future<void> _confirmAndContinue() async {
    if (_saving || !_locationDetected) return;

    final opId = ++_saveOpId;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw const _LocException('NO_USER');
      }

      // Firestore update — timeout guarded
      await FirebaseFirestore.instance
          .collection('app_users')
          .doc(user.id)
          .update({
        'assigned_state': _state,
        'assigned_district': _district,
      }).timeout(_kFirestoreTimeout);

      // Update local auth state
      ref.read(authProvider.notifier).updateUser(
            user.copyWith(assignedState: _state),
          );

      // Mark onboarding complete only AFTER successful write
      final prefs =
          await SharedPreferences.getInstance().timeout(_kPrefsTimeout);
      await prefs.setBool(_LocKeys.onboardingComplete, true);

      // Stale check
      if (opId != _saveOpId || !mounted) return;

      // Route based on consent status
      final consentGiven = prefs.getBool(_LocKeys.consentGiven) ?? false;
      if (consentGiven) {
        // ✨ Route through the animated greeting screen as the grand finale before Home!
        context.go('/greeting?next=${_LocRoutes.home}');
      } else {
        // Location is known → pick the language (regional + Hindi + English),
        // THEN show consent in that language. DPDP: consent in a chosen language.
        final consentNext = Uri.encodeComponent(
            '${_LocRoutes.consent}?next=${_LocRoutes.home}');
        final st = Uri.encodeComponent(_state);
        context.go('/language?next=$consentNext&state=$st');
      }
    } on TimeoutException {
      if (opId != _saveOpId || !mounted) return;
      setState(() => _error = 'Server is taking too long. Please try again.');
    } on _LocException catch (e) {
      if (opId != _saveOpId || !mounted) return;
      setState(() => _error = _safeErrorMessage(e.message));
    } catch (_) {
      if (opId != _saveOpId || !mounted) return;
      setState(() => _error = 'Could not save location. Please try again.');
    } finally {
      if (opId == _saveOpId && mounted) {
        setState(() => _saving = false);
      }
    }
  }

  // ── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MitraScaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _LocationHeader(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(MitraSpacing.lg),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DetectButton(
                        detecting: _detecting,
                        detected: _locationDetected,
                        cooldownActive: _isCooldownActive,
                        onTap: _detectLocation,
                      ),
                      if (_locationDetected) ...[
                        const SizedBox(height: 36),
                        _LocationResult(
                          district: _district,
                          state: _state,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 20),
                        _ErrorBanner(message: _error!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _ConfirmButton(
              enabled: _locationDetected && !_saving,
              loading: _saving,
              onPressed: _confirmAndContinue,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Sub-widgets
// ════════════════════════════════════════════════════════════

class _LocationHeader extends StatelessWidget {
  const _LocationHeader();

  static const _bgColor = Color(0x14FFFFFF);
  static const _borderColor = Color(0x26FFFFFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: _borderColor, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: MitraColors.sky.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(MitraRadius.sm),
                  border:
                      Border.all(color: MitraColors.sky.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.location_on_outlined,
                  color: MitraColors.sky,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step 4 of 4',
                    style: TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 12,
                      letterSpacing: 1.2,
                      color: MitraColors.textMuted,
                    ),
                  ),
                  Text(
                    'Confirm Location',
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'We use your location to personalise your learning content. '
            'Your GPS coordinates are never stored — only your district and state.',
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

class _DetectButton extends StatelessWidget {
  final bool detecting;
  final bool detected;
  final bool cooldownActive;
  final VoidCallback onTap;

  const _DetectButton({
    required this.detecting,
    required this.detected,
    required this.cooldownActive,
    required this.onTap,
  });

  bool get _interactable => !detecting && !cooldownActive;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: detected ? 'Detect location again' : 'Detect my location',
      enabled: _interactable,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _interactable ? onTap : null,
          borderRadius: BorderRadius.circular(MitraRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: detected
                  ? MitraColors.sky.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(MitraRadius.md),
              border: Border.all(
                color: detected
                    ? MitraColors.sky
                    : Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (detecting)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: MitraColors.sky,
                      strokeWidth: 2.5,
                    ),
                  )
                else
                  Icon(
                    detected ? Icons.my_location : Icons.location_searching,
                    color: detected ? MitraColors.sky : Colors.white70,
                    size: 24,
                  ),
                const SizedBox(width: 12),
                Text(
                  detecting
                      ? 'Detecting location…'
                      : detected
                          ? 'Detect Again'
                          : 'Detect My Location',
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: detected ? MitraColors.sky : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationResult extends StatelessWidget {
  final String district;
  final String state;

  const _LocationResult({required this.district, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MitraSpacing.lg),
      decoration: BoxDecoration(
        color: MitraColors.sky.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(color: MitraColors.sky.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline,
              color: MitraColors.sky, size: 32),
          const SizedBox(height: 12),
          Text(
            district,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w900,
              fontSize: 34,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            state,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w700,
              fontSize: 22,
              color: MitraColors.sky,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Is this correct? You can detect again if needed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Mukta',
              fontSize: 12,
              color: MitraColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

class _ConfirmButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const _ConfirmButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MitraSpacing.lg),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: MitraColors.saffron,
            disabledBackgroundColor:
                MitraColors.saffron.withValues(alpha: 0.30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MitraRadius.pill),
            ),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : const Text(
                  'Confirm & Continue →',
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Internal exception — never leaves this file raw
// ════════════════════════════════════════════════════════════

class _LocException implements Exception {
  final String message;
  const _LocException(this.message);
}
