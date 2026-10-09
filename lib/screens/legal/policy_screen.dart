import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/colors.dart';
//import '../../config/legal_config.dart';

class PolicyScreen extends StatelessWidget {
  final String title;
  final String body;
  final String? externalUrl;
  const PolicyScreen({
    super.key,
    required this.title,
    required this.body,
    this.externalUrl,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: onSurface),
        title: Text(title,
            style: TextStyle(
                fontFamily: 'Baloo2',
                fontWeight: FontWeight.w800,
                color: onSurface)),
        actions: [
          if (externalUrl != null)
            IconButton(
              tooltip: 'Open official page',
              icon: Icon(Icons.open_in_new, color: onSurface),
              onPressed: () async {
                final uri = Uri.parse(externalUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MitraSpacing.lg),
          child: Text(
            body,
            style: TextStyle(
                fontFamily: 'Mukta',
                fontSize: 14,
                height: 1.5,
                color: onSurface.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }
}
