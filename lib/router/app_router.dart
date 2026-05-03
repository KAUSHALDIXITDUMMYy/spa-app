import 'package:go_router/go_router.dart';

import '../screens/contact_screen.dart';
import '../screens/dashboard_redirect_screen.dart';
import '../screens/login_screen.dart';
import '../screens/subscriber/subscriber_home_screen.dart';
import '../screens/publisher/publisher_home_screen.dart';
import '../screens/admin/admin_home_screen.dart';
import '../screens/terms_screen.dart';
import '../screens/unauthorized_screen.dart';
import '../screens/zoom/zoom_meeting_screen.dart';
import '../state/auth_notifier.dart';

GoRouter createAppRouter(AuthNotifier auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;
      final publicRoute =
          path == '/' || path == '/terms' || path == '/contact-us';

      if (auth.loading) return null;

      final user = auth.firebaseUser;
      final profile = auth.profile;

      if (user == null) {
        if (publicRoute) return null;
        return '/';
      }

      if (profile == null) {
        return '/';
      }

      if (profile.termsAcceptedAt == null && path != '/terms') {
        return '/terms?redirect=/dashboard';
      }

      if (publicRoute && profile.termsAcceptedAt != null && path == '/') {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const DashboardRedirectScreen(),
      ),
      GoRoute(
        path: '/publisher',
        builder: (_, __) => const PublisherHomeScreen(),
      ),
      GoRoute(
        path: '/subscriber',
        builder: (_, __) => const SubscriberHomeScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminHomeScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (_, __) => const TermsScreen(),
      ),
      GoRoute(
        path: '/contact-us',
        builder: (_, __) => const ContactScreen(),
      ),
      GoRoute(
        path: '/unauthorized',
        builder: (_, __) => const UnauthorizedScreen(),
      ),
      GoRoute(
        path: '/zoom/:id',
        builder: (_, st) => ZoomMeetingScreen(callId: st.pathParameters['id']!),
      ),
    ],
  );
}
