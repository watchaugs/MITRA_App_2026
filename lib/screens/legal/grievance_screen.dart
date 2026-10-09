import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/colors.dart';

class GrievanceScreen extends StatefulWidget {
  const GrievanceScreen({super.key});
  @override
  State<GrievanceScreen> createState() => _GrievanceScreenState();
}

class _GrievanceScreenState extends State<GrievanceScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = FirebaseFirestore.instanceFor(
          app: Firebase.app(), databaseId: '(default)');
      final doc = await db.collection('public_config').doc('compliance').get();
      _data = doc.data();
    } catch (_) {
      _data = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final grievance = _data?['grievance_officer'] as Map<String, dynamic>?;
    final dpo = _data?['dpo'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: onSurface),
        title: Text('Grievance & Data Protection',
            style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: FontWeight.w800,
                color: onSurface)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(MitraSpacing.lg),
                children: [
                  Text(
                    'Under the Digital Personal Data Protection Act, 2023, you '
                    'may contact the officers below with any concern about your '
                    'personal data.',
                    style: TextStyle(
                        fontFamily: 'Mukta',
                        fontSize: 13,
                        color: onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 20),
                  _officerCard(
                    context,
                    role: 'Grievance Officer',
                    officer: grievance,
                    onSurface: onSurface,
                  ),
                  const SizedBox(height: 12),
                  _officerCard(
                    context,
                    role: 'Data Protection Officer (DPO)',
                    officer: dpo,
                    onSurface: onSurface,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _officerCard(
    BuildContext context, {
    required String role,
    required Map<String, dynamic>? officer,
    required Color onSurface,
  }) {
    final name = officer?['name'] as String?;
    final email = officer?['email'] as String?;
    final phone = officer?['phone'] as String?;
    final hasData = name != null && name.isNotEmpty;

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
          Text(role,
              style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: onSurface)),
          const SizedBox(height: 8),
          if (!hasData)
            Text('Details are being updated.',
                style: TextStyle(
                    fontFamily: 'Mukta',
                    fontSize: 13,
                    color: onSurface.withValues(alpha: 0.6)))
          else ...[
            Text(name,
                style: TextStyle(
                    fontFamily: 'Mukta', fontSize: 14, color: onSurface)),
            if (email != null && email.isNotEmpty)
              _linkRow(Icons.email, email, 'mailto:$email', onSurface),
            if (phone != null && phone.isNotEmpty)
              _linkRow(Icons.phone, phone, 'tel:$phone', onSurface),
          ],
        ],
      ),
    );
  }

  Widget _linkRow(IconData icon, String label, String uri, Color onSurface) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          onTap: () async {
            final u = Uri.parse(uri);
            if (await canLaunchUrl(u)) {
              await launchUrl(u, mode: LaunchMode.externalApplication);
            }
          },
          child: Row(
            children: [
              Icon(icon, size: 16, color: MitraColors.saffron),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'Mukta',
                      fontSize: 13,
                      color: MitraColors.saffron,
                      decoration: TextDecoration.underline)),
            ],
          ),
        ),
      );
}
