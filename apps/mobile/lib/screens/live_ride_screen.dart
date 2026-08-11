import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/ride_realtime_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import 'timeline_screen.dart';

class LiveRideScreen extends StatefulWidget {
  const LiveRideScreen({super.key, required this.rideId});
  final String rideId;

  @override
  State<LiveRideScreen> createState() => _LiveRideScreenState();
}

class _LiveRideScreenState extends State<LiveRideScreen> {
  Ride? _ride;
  final _mapController = MapController();
  String? _banner;
  String? _activeEmergencyId;
  bool _starting = true;
  bool _demoStarting = false;
  bool _fitted = false;
  late final RideRealtimeService _realtime;
  late final LocationService _location;

  @override
  void initState() {
    super.initState();
    _realtime = context.read<RideRealtimeService>();
    _location = context.read<LocationService>();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthService>();
    final rides = context.read<RideService>();

    final ride = await rides.getRide(widget.rideId);
    setState(() => _ride = ride);

    await _realtime.connect(auth.session!.token, ride.id);

    _location.onPing = (ping) async {
      await _realtime.updateLocation(
        lat: ping['lat'] as double,
        lng: ping['lng'] as double,
        speedMps: (ping['speedMps'] as num?)?.toDouble(),
        heading: (ping['heading'] as num?)?.toDouble(),
        accuracy: (ping['accuracy'] as num?)?.toDouble(),
      );
    };

    await _location.start(intervalSeconds: ride.pingIntervalSeconds);
    setState(() => _starting = false);
    _realtime.addListener(_onRealtime);
  }

  void _onRealtime() {
    final rt = _realtime;
    if (rt.rideCompleted) {
      _goToTimeline();
      return;
    }
    if (rt.alerts.isNotEmpty) {
      setState(() => _banner = rt.alerts.first.message);
    }
    if (rt.lastRegroup != null) {
      setState(() => _banner = rt.lastRegroup!['message'] as String? ?? _banner);
    }
    if (rt.lastEmergency != null) {
      final e = rt.lastEmergency!;
      setState(() {
        _banner = '${e['displayName']} needs help: ${e['type']}';
        _activeEmergencyId = e['emergencyId']?.toString();
      });
    }
    if (rt.lastFuelMessage != null) {
      setState(() => _banner = rt.lastFuelMessage);
    }
    setState(() {});
    // Fit once when we first get riders; avoid refitting every ping (NaN/Infinity risk).
    if (!_fitted) {
      _fitToRiders();
    }
  }

  Future<void> _goToTimeline() async {
    if (!mounted) return;
    _realtime.removeListener(_onRealtime);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TimelineScreen(rideId: widget.rideId)),
    );
  }

  @override
  void dispose() {
    _realtime.removeListener(_onRealtime);
    _location.stop();
    _realtime.disconnect();
    super.dispose();
  }

  List<LatLng> _routePoints(Ride ride) {
    try {
      if (ride.routePolyline != null) {
        final decoded = jsonDecode(ride.routePolyline!);
        if (decoded is List) {
          return decoded.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
          }).toList();
        }
      }
    } catch (_) {}
    return [
      LatLng(ride.meetLat, ride.meetLng),
      ...ride.stops.map((s) => LatLng(s.lat, s.lng)),
      LatLng(ride.destinationLat, ride.destinationLng),
    ];
  }

  List<RiderLocation> _visibleRiders(Ride ride, RideRealtimeService realtime) {
    final source = realtime.riders.isNotEmpty ? realtime.riders : ride.knownRiderLocations();
    return source
        .where((r) => r.lat.isFinite && r.lng.isFinite && r.lat.abs() <= 90 && r.lng.abs() <= 180)
        .toList();
  }

  void _fitToRiders() {
    final ride = _ride;
    if (ride == null) return;
    final riders = _visibleRiders(ride, _realtime);
    final points = <LatLng>[
      ...riders.map((r) => LatLng(r.lat, r.lng)),
      if (_location.lastPosition != null)
        LatLng(_location.lastPosition!.latitude, _location.lastPosition!.longitude),
    ].where(_isFinitePoint).toList();
    if (points.isEmpty) return;

    try {
      if (points.length == 1) {
        _mapController.move(points.first, 13);
        _fitted = true;
        return;
      }

      final bounds = LatLngBounds.fromPoints(points);
      if (!_isFinitePoint(bounds.northWest) ||
          !_isFinitePoint(bounds.southEast) ||
          ((bounds.north - bounds.south).abs() < 1e-8 &&
              (bounds.east - bounds.west).abs() < 1e-8)) {
        _mapController.move(points.first, 13);
        _fitted = true;
        return;
      }

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(48),
          maxZoom: 14,
        ),
      );
      _fitted = true;
    } catch (_) {
      // Never let map camera math crash the live ride UI.
      try {
        _mapController.move(points.first, 12);
      } catch (_) {}
    }
  }

  static bool _isFinitePoint(LatLng p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180;

  Future<void> _startDemo() async {
    setState(() {
      _demoStarting = true;
      _banner = 'Demo run starting — watch the pack move along the route';
    });
    try {
      await context.read<RideService>().startDemo(widget.rideId);
      // Refresh membership (demo riders may have been added).
      final ride = await context.read<RideService>().getRide(widget.rideId);
      if (mounted) setState(() => _ride = ride);
    } catch (e) {
      if (mounted) setState(() => _banner = 'Demo failed: $e');
    } finally {
      if (mounted) setState(() => _demoStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final realtime = context.watch<RideRealtimeService>();
    final location = context.watch<LocationService>();
    final me = context.watch<AuthService>().userId;
    final isLeader = ride?.members.any(
          (m) => m.userId == me && m.role.toLowerCase() == 'leader',
        ) ??
        false;

    if (_starting || ride == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final riders = _visibleRiders(ride, realtime);
    final center = riders.isNotEmpty
        ? LatLng(riders.first.lat, riders.first.lng)
        : location.lastPosition != null
            ? LatLng(location.lastPosition!.latitude, location.lastPosition!.longitude)
            : LatLng(ride.meetLat, ride.meetLng);
    final route = _routePoints(ride);

    final markers = <Marker>[
      Marker(
        point: LatLng(ride.meetLat, ride.meetLng),
        width: 36,
        height: 36,
        child: const Icon(Icons.flag, color: AppTheme.signalSoft),
      ),
      Marker(
        point: LatLng(ride.destinationLat, ride.destinationLng),
        width: 36,
        height: 36,
        child: const Icon(Icons.sports_score, color: AppTheme.signal),
      ),
      ...ride.stops.map(
        (s) => Marker(
          point: LatLng(s.lat, s.lng),
          width: 36,
          height: 36,
          child: Icon(
            s.kind == 'fuel' ? Icons.local_gas_station : Icons.place,
            color: AppTheme.fuel,
          ),
        ),
      ),
      ...riders.map(_riderMarker),
    ];

    if (!_fitted && riders.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToRiders());
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 12),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.groupride.mobile',
              ),
              if (route.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route,
                      color: AppTheme.signal.withValues(alpha: 0.85),
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                if (_banner != null)
                  Material(
                    color: AppTheme.signal.withValues(alpha: 0.95),
                    child: ListTile(
                      title: Text(_banner!, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: _activeEmergencyId == null
                          ? null
                          : const Text('Tap ACK if you can help'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_activeEmergencyId != null)
                            TextButton(
                              onPressed: () async {
                                await context.read<RideService>().acknowledgeEmergency(
                                      ride.id,
                                      _activeEmergencyId!,
                                    );
                                if (!mounted) return;
                                setState(() {
                                  _banner = 'Emergency acknowledged';
                                  _activeEmergencyId = null;
                                });
                              },
                              child: const Text('ACK', style: TextStyle(color: Colors.white)),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _banner = null;
                              _activeEmergencyId = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.asphalt,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: AppTheme.mist),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const Spacer(),
                      if (isLeader)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: AppTheme.asphalt.withValues(alpha: 0.9),
                              foregroundColor: AppTheme.mist,
                            ),
                            onPressed: _demoStarting ? null : _startDemo,
                            icon: _demoStarting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_circle_outline),
                            label: const Text('Demo run'),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.asphalt.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${riders.length} riders live',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                if (riders.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final r in riders)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              backgroundColor: AppTheme.asphalt.withValues(alpha: 0.85),
                              label: Text(
                                '${r.displayName.split(' ').first} · ${r.role}',
                                style: TextStyle(
                                  color: AppTheme.statusColor(r.status),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const Spacer(),
                _ActionBar(
                  onEmergency: _showEmergency,
                  onRejoin: _rejoin,
                  onStatus: _setStatus,
                  onAnnounce: isLeader ? _announce : null,
                  onAlerts: _showAlerts,
                  onEnd: isLeader
                      ? () async {
                          await context.read<RideService>().endRide(ride.id);
                          if (!mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => TimelineScreen(rideId: ride.id)),
                          );
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Marker _riderMarker(RiderLocation r) {
    final color = AppTheme.statusColor(r.status);
    final isLead = r.role.toLowerCase() == 'leader';
    final isSweep = r.role.toLowerCase() == 'sweep';
    return Marker(
      point: LatLng(r.lat, r.lng),
      width: 56,
      height: 56,
      child: Column(
        children: [
          Icon(
            isLead ? Icons.navigation : isSweep ? Icons.shield : Icons.two_wheeler,
            color: color,
            size: 28,
          ),
          Text(
            r.displayName.split(' ').first,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Future<void> _showAlerts() async {
    final alerts = await context.read<RideService>().getAlerts(widget.rideId);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (alerts.isEmpty) const Text('No alerts yet', style: TextStyle(color: AppTheme.steel)),
            ...alerts.map(
              (a) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.message),
                subtitle: Text('${a.type} · ${a.createdAt.toLocal()}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEmergency() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Need Help', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final t in ['Mechanical', 'FlatTire', 'Accident', 'Medical', 'Other'])
              ListTile(title: Text(t), onTap: () => Navigator.pop(context, t)),
          ],
        ),
      ),
    );
    if (type == null || _location.lastPosition == null) return;
    await _realtime.raiseEmergency(
      type: type,
      lat: _location.lastPosition!.latitude,
      lng: _location.lastPosition!.longitude,
    );
  }

  Future<void> _rejoin() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Rejoin Group', style: TextStyle(fontWeight: FontWeight.w800))),
            ListTile(
              leading: const Icon(Icons.groups),
              title: const Text('Current group location'),
              onTap: () => Navigator.pop(context, 'group'),
            ),
            ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('Next planned stop'),
              onTap: () => Navigator.pop(context, 'next_stop'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final target = await _realtime.requestRejoin(choice);
    if (target == null || !mounted) return;
    await launchUrl(
      Uri.parse('https://maps.apple.com/?daddr=${target.lat},${target.lng}&dirflg=d'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _setStatus() async {
    final status = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in ['Riding', 'Stopped', 'FuelNeeded'])
              ListTile(
                leading: Icon(Icons.circle, color: AppTheme.statusColor(s), size: 14),
                title: Text(s),
                onTap: () => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    );
    if (status != null) await _realtime.setStatus(status);
  }

  Future<void> _announce() async {
    final controller = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Announcement'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (msg != null && msg.isNotEmpty) await _realtime.announce(msg);
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onEmergency,
    required this.onRejoin,
    required this.onStatus,
    this.onAnnounce,
    this.onAlerts,
    this.onEnd,
  });

  final VoidCallback onEmergency;
  final VoidCallback onRejoin;
  final VoidCallback onStatus;
  final VoidCallback? onAnnounce;
  final VoidCallback? onAlerts;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    Widget mini(String label, VoidCallback? onPressed) {
      return Expanded(
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            minimumSize: const Size(0, 44),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emergency),
                  onPressed: onEmergency,
                  child: const Text('Need Help'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(onPressed: onRejoin, child: const Text('Rejoin Group')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              mini('Status', onStatus),
              if (onAlerts != null) ...[
                const SizedBox(width: 8),
                mini('Alerts', onAlerts),
              ],
              if (onAnnounce != null) ...[
                const SizedBox(width: 8),
                mini('Announce', onAnnounce),
              ],
              if (onEnd != null) ...[
                const SizedBox(width: 8),
                mini('End', onEnd),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
