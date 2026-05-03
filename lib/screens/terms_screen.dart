import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/auth_notifier.dart';
import '../theme/app_theme.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final redirect =
        GoRouterState.of(context).uri.queryParameters['redirect'] ?? '/dashboard';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (auth.firebaseUser != null) {
              context.go(redirect);
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text('Terms & EULA'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Sportsmagician – Last updated: March 2025',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.mutedForeground,
                ),
          ),
          const SizedBox(height: 16),
          const Text(
            'By using this service you agree to the following terms. We have zero tolerance for objectionable content or abusive behavior.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _section('1. Acceptance',
              'By accessing or using Sportsmagician (“Service”), you agree to be bound by these Terms and our content and conduct policies.'),
          _section(
              '2. No Objectionable Content or Abuse',
              'We have zero tolerance for objectionable, harassing, or abusive behavior; hate speech; impersonation; spam; or illegal content. Violations may result in suspension or termination.'),
          _section('3. Reporting and Blocking',
              'You may report content or users and block others using in-app tools where available.'),
          _section('4. Audio streams and Zoom',
              'Live audio uses Agora real-time channels tied to Firestore sessions. Separate Zoom meetings may use Zoom’s own terms when you join those links.'),
          _section('5. Disclaimer',
              'The Service is provided “as is.” We are not responsible for third-party content shared by publishers.'),
          if (auth.firebaseUser != null && auth.profile?.termsAcceptedAt == null) ...[
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await auth.acceptTerms();
                      if (context.mounted) {
                        setState(() => _busy = false);
                        context.go(redirect);
                      }
                    },
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('I accept the Terms & EULA'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: AppColors.mutedForeground)),
        ],
      ),
    );
  }
}
