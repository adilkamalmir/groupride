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

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Ride>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<RideService>().listRides();
  }

  void _reload() {
    setState(() {
      _future = context.read<RideService>().listRides();
    });
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
            if (rides.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'No rides yet.\nCreate one or join with a link/QR.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.steel),
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
                return _RideTile(
                  ride: ride,
                  onTap: () async {
                    if (ride.isCompleted) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TimelineScreen(rideId: ride.id),
                        ),
                      );
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RideLobbyScreen(rideId: ride.id),
                        ),
                      );
                      _reload();
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride, required this.onTap});
  final Ride ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, MMM d · h:mm a');
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
                  _StatusChip(status: ride.status),
                ],
              ),
              const SizedBox(height: 8),
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
