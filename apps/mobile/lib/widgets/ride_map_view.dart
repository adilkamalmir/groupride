import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../theme.dart';
import 'rider_letter_marker.dart';

class RideMapView extends StatelessWidget {
  const RideMapView({
    super.key,
    required this.ride,
    this.riders = const [],
    this.height = 240,
    this.showLegend = true,
    this.interactive = true,
    this.mapController,
    this.onMarkerTap,
  });

  final Ride ride;
  final List<RiderLocation> riders;
  final double height;
  final bool showLegend;
  final bool interactive;
  final MapController? mapController;
  final void Function(RiderLocation rider)? onMarkerTap;

  @override
  Widget build(BuildContext context) {
    final route = _parseRoute(ride.routePolyline);
    final center = riders.isNotEmpty
        ? LatLng(riders.first.lat, riders.first.lng)
        : LatLng(ride.meetLat, ride.meetLng);

    final markers = <Marker>[
      Marker(
        point: LatLng(ride.meetLat, ride.meetLng),
        width: 40,
        height: 40,
        child: const Icon(Icons.flag, color: AppTheme.signalSoft),
      ),
      Marker(
        point: LatLng(ride.destinationLat, ride.destinationLng),
        width: 40,
        height: 40,
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
            size: 28,
          ),
        ),
      ),
      ...riders.map((r) {
        return Marker(
          point: LatLng(r.lat, r.lng),
          width: 64,
          height: 56,
          child: GestureDetector(
            onTap: onMarkerTap == null ? null : () => onMarkerTap!(r),
            child: RiderLetterMarker(
              displayName: r.displayName,
              status: r.status,
              role: r.role,
            ),
          ),
        );
      }),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: height,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 11,
                interactionOptions: InteractionOptions(
                  flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
                ),
              ),
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
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: const [
              _LegendDot(color: AppTheme.riding, label: 'Riding'),
              _LegendDot(color: AppTheme.stopped, label: 'Stopped'),
              _LegendDot(color: AppTheme.emergency, label: 'Emergency'),
              _LegendDot(color: AppTheme.fuel, label: 'Fuel needed'),
            ],
          ),
        ],
      ],
    );
  }

  List<LatLng> _parseRoute(String? polyline) {
    if (polyline == null || polyline.isEmpty) {
      return [
        LatLng(ride.meetLat, ride.meetLng),
        ...ride.stops.map((s) => LatLng(s.lat, s.lng)),
        LatLng(ride.destinationLat, ride.destinationLng),
      ];
    }
    try {
      final decoded = jsonDecode(polyline);
      if (decoded is List) {
        return decoded
            .map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
            })
            .toList();
      }
    } catch (_) {}
    return [
      LatLng(ride.meetLat, ride.meetLng),
      LatLng(ride.destinationLat, ride.destinationLng),
    ];
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppTheme.steel, fontSize: 12)),
      ],
    );
  }
}
