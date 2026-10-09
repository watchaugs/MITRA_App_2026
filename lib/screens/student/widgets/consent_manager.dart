import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/colors.dart';
import '../../../services/api_service.dart';
import '../../../stores/auth_store.dart';

/// A self-contained "Manage Consent" card for the profile/settings screen.
/// Reads live status from /api/consent/status and lets the student
/// re-grant or withdraw. Withdraw is reversible (flips a flag), so we
/// word it plainly and confirm first.
class ConsentManager extends ConsumerStatefulWidget {
  const ConsentManager({super.key});

  @override
  ConsumerState<ConsentManager> createState() => _ConsentManagerState();
}

class _ConsentManagerState extends ConsumerState<ConsentManager> {
  bool _loading = true;
  bool _granted = false;
  String? _version;
  List<String> _consents = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(currentUserProvider)?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    try {
      final res = await ConsentAPI.status(studentId: uid);
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _granted = data['granted'] == true;
        _version = data['version']?.toString();
        _consents = (data['consents'] as List?)?.cast<String>() ?? const [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load consent status.';
      });
    }
  }

  Future<void> _withdraw() async {
    final uid = ref.read(currentUserProvider)?.id;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MitraColors.bgCard,
        title: const Text('Withdraw consent?'),
        content: const Text(
          'You can withdraw your consent to data collection. Some features '
          'that need your data (progress tracking, leaderboards) may stop '
          'working until you consent again. You can re-consent any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw',
                style: TextStyle(color: MitraColors.crimson)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ConsentAPI.withdraw(uid);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consent withdrawn.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not withdraw. Try again.')),
        );
      }
    }
  }

  Future<void> _regrant() async {
    final uid = ref.read(currentUserProvider)?.id;
    if (uid == null) return;
    try {
      await ConsentAPI.grant(uid, ['data_collection', 'analytics']);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consent granted.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save consent. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(MitraSpacing.lg),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(MitraRadius.md),
        border: Border.all(color: onSurface.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🛡️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Data Consent',
                  style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            Text(_error!,
                style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 13,
                    color: onSurface.withValues(alpha: 0.6)))
          else ...[
            Row(
              children: [
                Icon(_granted ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color:
                        _granted ? MitraColors.emerald : MitraColors.crimson),
                const SizedBox(width: 8),
                Text(
                  _granted ? 'Consent granted' : 'Consent not granted',
                  style: TextStyle(
                      fontFamily: 'Mukta',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: onSurface),
                ),
                if (_version != null) ...[
                  const SizedBox(width: 8),
                  Text('v$_version',
                      style: TextStyle(
                          fontFamily: 'SpaceMono',
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.5))),
                ],
              ],
            ),
            if (_consents.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Active: ${_consents.join(', ')}',
                  style: TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 12,
                      color: onSurface.withValues(alpha: 0.6))),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _granted ? _withdraw : _regrant,
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      _granted ? MitraColors.crimson : MitraColors.emerald,
                  side: BorderSide(
                      color: (_granted
                          ? MitraColors.crimson
                          : MitraColors.emerald)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MitraRadius.pill)),
                ),
                child: Text(_granted ? 'Withdraw consent' : 'Grant consent',
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
