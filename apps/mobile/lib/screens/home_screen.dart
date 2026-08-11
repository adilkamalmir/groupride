import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import 'bike_profile_screen.dart';
import 'create_ride_screen.dart';
import 'join_ride_screen.dart';
import 'ride_lobby_screen.dart';
import 'timeline_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late Future<List<Ride>> _future;
  late final TabController _tabs;
  String _pastFilter = 'all'; // all | done | not_done

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _future = context.read<RideService>().listRides();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = context.read<RideService>().listRides();
    });
  }

  bool _isUpcoming(Ride ride) {
    final status = ride.status.toLowerCase();
    if (status == 'live') return true;
    if (status == 'completed' || status == 'cancelled') return false;
    return !ride.startAt.toLocal().isBefore(DateTime.now());
  }

  bool _isDone(Ride ride) => ride.status.toLowerCase() == 'completed';

  Future<void> _deleteRide(Ride ride) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ride?'),
        content: Text('Delete "${ride.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.emergency)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<RideService>().deleteRide(ride.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('GroupRide'),
        actions: [
          IconButton(
            tooltip: 'Bike profile',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BikeProfileScreen()),
              );
            },
            icon: const Icon(Icons.two_wheeler),
          ),
          IconButton(
            tooltip: 'Join with code',
            onPressed: () async {
              final joined = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const JoinRideScreen()),
              );
              if (joined == true) _reload();
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.signal,
          labelColor: AppTheme.mist,
          unselectedLabelColor: AppTheme.steel,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.signal,
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const CreateRideScreen()),
          );
          if (created == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Create ride'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Ride>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: ${snap.error}',
                        style: const TextStyle(color: AppTheme.emergency)),
                  ),
                ],
              );
            }
            final rides = snap.data ?? [];
            final upcoming = rides.where(_isUpcoming).toList()
              ..sort((a, b) => a.startAt.compareTo(b.startAt));
            final past = rides.where((r) => !_isUpcoming(r)).toList()
              ..sort((a, b) => b.startAt.compareTo(a.startAt));

            return TabBarView(
              controller: _tabs,
              children: [
                _RideList(
                  rides: upcoming,
                  emptyLabel: 'No upcoming rides.\nCreate one or join with a link/QR.',
                  onTap: _openRide,
                  onDelete: _deleteRide,
                ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('All')),
                          ButtonSegment(value: 'done', label: Text('Done')),
                          ButtonSegment(value: 'not_done', label: Text('Not done')),
                        ],
                        selected: {_pastFilter},
                        onSelectionChanged: (s) => setState(() => _pastFilter = s.first),
                      ),
                    ),
                    Expanded(
                      child: _RideList(
                        rides: past.where((r) {
                          if (_pastFilter == 'done') return _isDone(r);
                          if (_pastFilter == 'not_done') return !_isDone(r);
                          return true;
                        }).toList(),
                        emptyLabel: 'No past rides yet.',
                        onTap: _openRide,
                        onDelete: _deleteRide,
                        showOutcome: true,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openRide(Ride ride) async {
    if (ride.isCompleted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TimelineScreen(rideId: ride.id)),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RideLobbyScreen(rideId: ride.id)),
      );
      _reload();
    }
  }
}

class _RideList extends StatelessWidget {
  const _RideList({
    required this.rides,
    required this.emptyLabel,
    required this.onTap,
    required this.onDelete,
    this.showOutcome = false,
  });

  final List<Ride> rides;
  final String emptyLabel;
  final Future<void> Function(Ride ride) onTap;
  final Future<void> Function(Ride ride) onDelete;
  final bool showOutcome;

  @override
  Widget build(BuildContext context) {
    if (rides.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.steel),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: rides.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final ride = rides[i];
        return Dismissible(
          key: ValueKey(ride.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            await onDelete(ride);
            return false;
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppTheme.emergency.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete, color: AppTheme.emergency),
          ),
          child: _RideTile(
            ride: ride,
            showOutcome: showOutcome,
            onTap: () => onTap(ride),
            onDelete: () => onDelete(ride),
          ),
        );
      },
    );
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({
    required this.ride,
    required this.onTap,
    required this.onDelete,
    this.showOutcome = false,
  });
  final Ride ride;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool showOutcome;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, MMM d · h:mm a');
    final done = ride.status.toLowerCase() == 'completed';
    return Material(
      color: AppTheme.asphaltLight,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ride.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (showOutcome)
                    _OutcomeChip(done: done)
                  else
                    _StatusChip(status: ride.status),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.steel),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(df.format(ride.startAt.toLocal()),
                  style: const TextStyle(color: AppTheme.steel)),
              const SizedBox(height: 4),
              Text('${ride.meetPointName} → ${ride.destinationName}',
                  style: const TextStyle(color: AppTheme.mist)),
              const SizedBox(height: 8),
              Text('${ride.members.length} riders',
                  style: const TextStyle(color: AppTheme.steel, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = done ? AppTheme.riding : AppTheme.emergency;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        done ? 'DONE' : 'NOT DONE',
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status.toLowerCase()) {
      case 'live':
        c = AppTheme.riding;
        break;
      case 'completed':
        c = AppTheme.steel;
        break;
      default:
        c = AppTheme.signalSoft;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
