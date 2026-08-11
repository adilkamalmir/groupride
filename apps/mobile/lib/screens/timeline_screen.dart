import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets/ride_map_view.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.rideId});
  final String rideId;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late Future<Timeline> _future;
  Ride? _ride;

  @override
  void initState() {
    super.initState();
    _reload();
    context.read<RideService>().getRide(widget.rideId).then((r) {
      if (mounted) setState(() => _ride = r);
    });
  }

  void _reload() {
    _future = context.read<RideService>().getTimeline(widget.rideId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride timeline'),
        actions: [
          IconButton(
            tooltip: 'Add photo URL',
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: FutureBuilder<Timeline>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            if (snap.hasError) {
              return Center(
                child: Text('${snap.error}', style: const TextStyle(color: AppTheme.emergency)),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          final t = snap.data!;
          final attendance = t.attendanceJson != null
              ? (jsonDecode(t.attendanceJson!) as List)
              : <dynamic>[];
          final stops = t.stopsJson != null ? (jsonDecode(t.stopsJson!) as List) : <dynamic>[];
          final photos = t.photoUrlsJson != null
              ? (jsonDecode(t.photoUrlsJson!) as List).cast<String>()
              : <String>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.rideName,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              if (_ride != null) ...[
                RideMapView(
                  ride: _ride!,
                  height: 200,
                  interactive: false,
                  showLegend: false,
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  _Stat(label: 'Distance', value: '${t.distanceKm} km'),
                  const SizedBox(width: 12),
                  _Stat(label: 'Duration', value: '${t.durationMinutes.toStringAsFixed(0)} min'),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Stops', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ...stops.map((s) {
                final m = s as Map<String, dynamic>;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag, color: AppTheme.signalSoft),
                  title: Text(m['name'] as String? ?? ''),
                  subtitle: Text(m['kind'] as String? ?? ''),
                );
              }),
              const SizedBox(height: 16),
              const Text('Attendance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ...attendance.map((a) {
                final m = a as Map<String, dynamic>;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m['displayName'] as String? ?? ''),
                  subtitle: Text(
                    '${m['role']} · ${(m['distanceSinceStartKm'] as num?)?.toStringAsFixed(1) ?? 0} km',
                  ),
                  trailing: Icon(
                    (m['attended'] as bool?) == true ? Icons.check_circle : Icons.cancel,
                    color: (m['attended'] as bool?) == true ? AppTheme.riding : AppTheme.steel,
                  ),
                );
              }),
              const SizedBox(height: 16),
              const Text('Photos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              if (photos.isEmpty)
                const Text('No photos yet — add a URL from the app bar.',
                    style: TextStyle(color: AppTheme.steel)),
              ...photos.map(
                (url) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image, color: AppTheme.signalSoft),
                  title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addPhoto() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add photo URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'https://...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await context.read<RideService>().addTimelinePhotos(widget.rideId, [url]);
    if (!mounted) return;
    setState(_reload);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.asphaltLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.steel, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
