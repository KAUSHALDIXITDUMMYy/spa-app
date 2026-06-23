import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/auth_notifier.dart';

class DashboardRedirectScreen extends StatelessWidget {
  const DashboardRedirectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final role = auth.profile?.role.toLowerCase().trim();
      switch (role) {
        case 'admin':
          context.go('/admin');
          break;
        case 'publisher':
          context.go('/publisher');
          break;
        case 'subscriber':
          context.go('/subscriber');
          break;
        default:
          context.go('/unauthorized');
      }
    });

    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening your dashboard…'),
          ],
        ),
      ),
    );
  }
}
