import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ride_service.dart';
import '../theme.dart';
import 'ride_lobby_screen.dart';

class JoinRideScreen extends StatefulWidget {
  const JoinRideScreen({super.key});

  @override
  State<JoinRideScreen> createState() => _JoinRideScreenState();
}

class _JoinRideScreenState extends State<JoinRideScreen> {
  final _token = TextEditingController(text: 'ottawa-valley-demo');
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join ride')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Enter an invite code from a ride leader (QR camera scanning works on a physical device).',
            style: TextStyle(color: AppTheme.steel),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _token,
            decoration: const InputDecoration(
              labelText: 'Invite code or token',
              hintText: 'ottawa-valley-demo',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : () => _join(_token.text.trim()),
            child: const Text('Join'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTheme.emergency)),
          ],
        ],
      ),
    );
  }

  Future<void> _join(String token) async {
    if (token.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ride = await context.read<RideService>().joinInvite(token);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RideLobbyScreen(rideId: ride.id)),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
