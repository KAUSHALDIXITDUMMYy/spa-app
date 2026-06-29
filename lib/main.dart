import 'package:audio_session/audio_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'router/app_router.dart';
import 'services/api_client.dart';
import 'services/admin_broadcasts_repository.dart';
import 'services/admin_repository.dart';
import 'services/auth_service.dart';
import 'services/chat_notification_service.dart';
import 'services/chat_repository.dart';
import 'services/daily_schedule_repository.dart';
import 'services/foreground_service_helper.dart';
import 'services/scheduled_calls_repository.dart';
import 'services/streaming_repository.dart';
import 'services/subscriber_repository.dart';
import 'services/zoom_repository.dart';
import 'state/auth_notifier.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await ChatNotificationService.initialize();

  await ForegroundServiceHelper.init();

  final audio = await AudioSession.instance;
  await audio.configure(const AudioSessionConfiguration.speech());

  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final apiClient = ApiClient(auth);
  final authService = AuthService(auth, apiClient);
  final authNotifier = AuthNotifier(authService);

  runApp(SportsmagicianApp(
    authNotifier: authNotifier,
    firestore: firestore,
    apiClient: apiClient,
  ));
}

class SportsmagicianApp extends StatefulWidget {
  const SportsmagicianApp({
    super.key,
    required this.authNotifier,
    required this.firestore,
    required this.apiClient,
  });

  final AuthNotifier authNotifier;
  final FirebaseFirestore firestore;
  final ApiClient apiClient;

  @override
  State<SportsmagicianApp> createState() => _SportsmagicianAppState();
}

class _SportsmagicianAppState extends State<SportsmagicianApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(widget.authNotifier);
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.firestore;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.authNotifier),
        Provider.value(value: fs),
        Provider.value(value: widget.apiClient),
        Provider(create: (_) => StreamingRepository(fs)),
        Provider(create: (_) => SubscriberRepository(fs)),
        Provider(create: (_) => ScheduledCallsRepository(fs)),
        Provider(create: (_) => DailyScheduleRepository(fs)),
        Provider(create: (_) => AdminBroadcastsRepository(fs)),
        Provider(create: (_) => ChatRepository(fs)),
        Provider(
          create: (ctx) => ChatNotificationService(ctx.read<ChatRepository>()),
        ),
        Provider(create: (_) => ZoomRepository(fs)),
        Provider(create: (_) => AdminRepository(fs)),
      ],
      child: MaterialApp.router(
        title: 'Sportsmagician',
        theme: buildAppTheme(),
        routerConfig: _router,
        builder: (context, child) => WithForegroundTask(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
