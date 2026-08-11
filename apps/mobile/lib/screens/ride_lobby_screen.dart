import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets/ride_map_view.dart';
import 'live_ride_screen.dart';
import 'timeline_screen.dart';

class RideLobbyScreen extends StatefulWidget {
  const RideLobbyScreen({super.key, required this.rideId});
  final String rideId;

  @override
  State<RideLobbyScreen> createState() => _RideLobbyScreenState();
}

class _RideLobbyScreenState extends State<RideLobbyScreen> {
  Ride? _ride;
  String? _error;
  Timer? _ticker;
  Map<String, dynamic>? _invite;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ride = await context.read<RideService>().getRide(widget.rideId);
      setState(() => _ride = ride);
      final me = context.read<AuthService>().userId;
      final isLeader = ride.members.any(
        (m) => m.userId == me && m.role.toLowerCase() == 'leader',
      );
      if (isLeader) {
        _invite = await context.read<RideService>().getInvite(ride.id);
        setState(() {});
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final me = context.watch<AuthService>().userId;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride')),
        body: Center(child: Text(_error!, style: const TextStyle(color: AppTheme.emergency))),
      );
    }
    if (ride == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isLeader = ride.members.any(
      (m) => m.userId == me && m.role.toLowerCase() == 'leader',
    );
    final cd = ride.countdown;

    return Scaffold(
      appBar: AppBar(
        title: Text(ride.name),
        actions: [
          if (ride.isCompleted)
            IconButton(
              icon: const Icon(Icons.photo_album_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TimelineScreen(rideId: ride.id)),
                );
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CountdownCard(duration: cd, startAt: ride.startAt),
          const SizedBox(height: 16),
          RideMapView(ride: ride, height: 220),
          const SizedBox(height: 16),
          _InfoRow(label: 'Meet', value: ride.meetPointName),
          _InfoRow(label: 'Destination', value: ride.destinationName),
          const SizedBox(height: 8),
          const Text('Stops', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ...ride.stops.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.kind == 'fuel' ? Icons.local_gas_station : Icons.restaurant,
                color: AppTheme.signalSoft,
              ),
              title: Text(s.name),
              subtitle: Text(s.kind ?? 'stop'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Riders', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ...ride.members.map((m) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppTheme.asphalt,
                child: Text(m.displayName.characters.first.toUpperCase()),
              ),
              title: Text(m.displayName),
              subtitle: Text(m.role),
              trailing: isLeader && m.role.toLowerCase() != 'leader'
                  ? PopupMenuButton<String>(
                      onSelected: (role) async {
                        await context.read<RideService>().assignRole(ride.id, m.userId, role);
                        await _load();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'Sweep', child: Text('Make sweep')),
                        PopupMenuItem(value: 'Rider', child: Text('Make rider')),
                        PopupMenuItem(value: 'Leader', child: Text('Transfer lead')),
                      ],
                    )
                  : null,
            );
          }),
          if (isLeader && _invite != null) ...[
            const SizedBox(height: 16),
            const Text('Invite', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            Center(
              child: QrImageView(
                data: _invite!['qrPayload'] as String? ?? _invite!['link'] as String,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _invite!['link'] as String? ?? '',
              style: const TextStyle(color: AppTheme.steel),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final text = _invite!['shareText'] as String? ?? _invite!['link'];
                      Share.share(text as String);
                    },
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share / SMS'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _invite!['link'] as String));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          if (isLeader && !ride.isLive && !ride.isCompleted) ...[
            ElevatedButton(
              onPressed: () async {
                await context.read<RideService>().startRide(ride.id);
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => LiveRideScreen(rideId: ride.id)),
                );
              },
              child: const Text('Start ride'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await context.read<RideService>().startDemo(ride.id);
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => LiveRideScreen(rideId: ride.id)),
                );
              },
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Start demo run'),
            ),
          ],
          if (ride.isLive)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => LiveRideScreen(rideId: ride.id)),
                );
              },
              child: const Text('Open live map'),
            ),
        ],
      ),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.duration, required this.startAt});
  final Duration duration;
  final DateTime startAt;

  @override
  Widget build(BuildContext context) {
    String text;
    if (duration == Duration.zero && startAt.isBefore(DateTime.now())) {
      text = 'Departure time passed';
    } else {
      final h = duration.inHours;
      final m = duration.inMinutes.remainder(60);
      final s = duration.inSeconds.remainder(60);
      text = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1A12), Color(0xFF1A1D23)],
        ),
        border: Border.all(color: AppTheme.signal.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Text('DEPARTURE COUNTDOWN',
              style: TextStyle(color: AppTheme.steel, letterSpacing: 1.2, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: AppTheme.signalSoft,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppTheme.steel)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
