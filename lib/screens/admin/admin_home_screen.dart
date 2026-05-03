import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/user_profile.dart';
import '../../services/admin_repository.dart';
import '../../state/auth_notifier.dart';
import '../../theme/app_theme.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static const _sections = [
    ('users', 'User Management'),
    ('live', 'Live rooms'),
    ('analytics', 'Analytics'),
    ('assign', 'Publisher Assignments'),
    ('streamAssign', 'Stream Assignments'),
    ('schedule', 'Today\'s Schedule'),
    ('contact', 'Contact'),
    ('reports', 'Reports'),
    ('notify', 'Notifications'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _sections.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final admin = context.watch<AdminRepository>();
    final fs = context.watch<FirebaseFirestore>();

    if (auth.profile?.role != 'admin') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/unauthorized');
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          TextButton(
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) context.go('/');
            },
            child: const Text('Sign Out'),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: [for (final s in _sections) Tab(text: s.$2)],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          StreamBuilder<List<UserProfile>>(
            stream: admin.watchUsers(),
            builder: (_, snap) {
              final users = snap.data ?? [];
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (_, i) {
                  final u = users[i];
                  return ListTile(
                    title: Text(u.displayName ?? u.email),
                    subtitle: Text('${u.role} · ${u.email}'),
                    trailing: u.isActive
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.cancel_outlined, color: AppColors.destructive),
                  );
                },
              );
            },
          ),
          StreamBuilder(
            stream: admin.watchActiveSessions(),
            builder: (_, snap) {
              final sessions = snap.data ?? [];
              if (sessions.isEmpty) {
                return const Center(
                    child: Text('No active stream sessions.',
                        style: TextStyle(color: AppColors.mutedForeground)));
              }
              return ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (_, i) {
                  final s = sessions[i];
                  return ListTile(
                    title: Text(s.title ?? 'Untitled'),
                    subtitle: Text(
                        '${s.publisherName} · ${s.roomId}${s.awaitingBroadcast == true ? ' · waiting' : ''}'),
                  );
                },
              );
            },
          ),
          FutureBuilder<_AnalyticsSnap>(
            future: _loadAnalytics(fs),
            builder: (_, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final a = snap.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Active streams: ${a.activeStreams}',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('Users (approx): ${a.users}',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('Active viewer docs: ${a.activeViewers}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  const Text(
                    'Matches web admin analytics snapshots (Firestore counts). '
                    'Charts and date filters remain on the web console if you need them.',
                    style: TextStyle(color: AppColors.mutedForeground),
                  ),
                ],
              );
            },
          ),
          FutureBuilder<int>(
            future: fs.collection('streamPermissions').count().get().then((c) => c.count ?? 0),
            builder: (_, snap) => _countCard('streamPermissions rows', snap.data),
          ),
          FutureBuilder<int>(
            future: fs.collection('streamAssignments').count().get().then((c) => c.count ?? 0),
            builder: (_, snap) => _countCard('streamAssignments rows', snap.data),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('scheduledCalls')
                .where('dateKey', isEqualTo: _dateKey())
                .snapshots(),
            builder: (_, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No scheduled calls for today.'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  return ListTile(
                    title: Text('${d['title']}'),
                    subtitle: Text(
                        '${d['publisherName']} · ${d['roomId']} · ${d['startsAt']}'),
                  );
                },
              );
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('contactMessages')
                .orderBy('createdAt', descending: true)
                .limit(40)
                .snapshots(),
            builder: (_, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No contact messages.'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  return ListTile(
                    title: Text('${d['email']}'),
                    subtitle: Text('${d['message']}'),
                  );
                },
              );
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('reports')
                .orderBy('createdAt', descending: true)
                .limit(40)
                .snapshots(),
            builder: (_, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No reports.'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  return ListTile(
                    title: Text('${d['reason'] ?? 'Report'}'),
                    subtitle: Text('${d['details'] ?? ''}'),
                  );
                },
              );
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('adminBroadcasts')
                .orderBy('createdAt', descending: true)
                .limit(30)
                .snapshots(),
            builder: (_, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No broadcasts.'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  return ListTile(
                    title: Text('${d['title'] ?? 'Broadcast'}'),
                    subtitle: Text('${d['body'] ?? ''}'),
                  );
                },
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            final n = await admin.logoutAllUsers();
            messenger.showSnackBar(SnackBar(content: Text('Cleared sessions on $n account(s).')));
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('$e')));
          }
        },
        icon: const Icon(Icons.logout),
        label: const Text('Logout all'),
      ),
    );
  }

  Widget _countCard(String label, int? count) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          count == null ? 'Loading…' : '$label: $count',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  String _dateKey() {
    final x = DateTime.now();
    final y = x.year.toString().padLeft(4, '0');
    final m = x.month.toString().padLeft(2, '0');
    final d = x.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _AnalyticsSnap {
  _AnalyticsSnap(this.activeStreams, this.users, this.activeViewers);
  final int activeStreams;
  final int users;
  final int activeViewers;
}

Future<_AnalyticsSnap> _loadAnalytics(FirebaseFirestore fs) async {
  final a = await fs
      .collection('streamSessions')
      .where('isActive', isEqualTo: true)
      .count()
      .get();
  final u = await fs.collection('users').count().get();
  final v = await fs
      .collection('activeViewers')
      .where('isActive', isEqualTo: true)
      .count()
      .get();
  return _AnalyticsSnap(a.count ?? 0, u.count ?? 0, v.count ?? 0);
}
