import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/zoom_repository.dart';
import '../../theme/app_theme.dart';

/// Zoom meetings on the web use the Zoom Meeting SDK in-browser. On mobile we open
/// the stored join URL in the system browser (or Zoom app) so subscribers/publishers
/// can still reach the same meeting links from Firestore `zoomCalls`.
class ZoomMeetingScreen extends StatelessWidget {
  const ZoomMeetingScreen({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ZoomRepository>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Zoom meeting'),
      ),
      body: FutureBuilder(
        future: repo.getCall(callId),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final call = snap.data!;
          final url = call.launchableUrl;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(call.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (call.meetingNumber != null)
                  Text('Meeting #: ${call.meetingNumber}',
                      style: const TextStyle(color: AppColors.mutedForeground)),
                const SizedBox(height: 20),
                if (url == null)
                  const Text(
                    'No join URL is stored for this call. Ask your administrator to add a link or meeting number.',
                  )
                else
                  ElevatedButton(
                    onPressed: () async {
                      final uri = Uri.parse(url);
                      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not open link.')),
                          );
                        }
                      }
                    },
                    child: const Text('Open Zoom link'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
