import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/maps_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets/place_autocomplete_field.dart';

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final _name = TextEditingController(text: 'Sunday Ottawa Valley Ride');
  final _meet = TextEditingController();
  final _dest = TextEditingController();
  final _fuelStop = TextEditingController();
  final _lunchStop = TextEditingController();

  GeocodedPlace? _meetPlace;
  GeocodedPlace? _destPlace;
  GeocodedPlace? _fuelPlace;
  GeocodedPlace? _lunchPlace;

  DateTime _startAt = DateTime.now().add(const Duration(days: 1)).copyWith(
        hour: 10,
        minute: 0,
        second: 0,
        millisecond: 0,
        microsecond: 0,
      );
  bool _busy = false;
  bool _previewing = false;
  String? _error;
  String? _routeSummary;
  List<LatLng> _previewPath = const [];
  final List<Marker> _previewMarkers = [];

  @override
  void dispose() {
    _name.dispose();
    _meet.dispose();
    _dest.dispose();
    _fuelStop.dispose();
    _lunchStop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create ride')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Ride name')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date & time'),
            subtitle: Text(_startAt.toLocal().toString()),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDateTime,
          ),
          PlaceAutocompleteField(
            controller: _meet,
            label: 'Meeting point',
            helperText: 'Start typing — Google Places suggestions',
            onPlaceSelected: (p) => setState(() => _meetPlace = p),
          ),
          const SizedBox(height: 12),
          PlaceAutocompleteField(
            controller: _dest,
            label: 'Destination',
            helperText: 'Start typing — Google Places suggestions',
            onPlaceSelected: (p) => setState(() => _destPlace = p),
          ),
          const SizedBox(height: 12),
          PlaceAutocompleteField(
            controller: _fuelStop,
            label: 'Fuel stop',
            onPlaceSelected: (p) => setState(() => _fuelPlace = p),
          ),
          const SizedBox(height: 12),
          PlaceAutocompleteField(
            controller: _lunchStop,
            label: 'Lunch stop',
            onPlaceSelected: (p) => setState(() => _lunchPlace = p),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy || _previewing ? null : _previewRoute,
            icon: _previewing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.route),
            label: const Text('Preview motorcycle route'),
          ),
          if (_routeSummary != null) ...[
            const SizedBox(height: 8),
            Text(_routeSummary!, style: const TextStyle(color: AppTheme.steel)),
          ],
          if (_previewPath.length >= 2) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _previewPath[_previewPath.length ~/ 2],
                    initialZoom: 9,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.groupride.mobile',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _previewPath,
                          color: AppTheme.signal.withValues(alpha: 0.9),
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                    MarkerLayer(markers: _previewMarkers),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTheme.emergency)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create & open invites'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _startAt,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt),
    );
    if (time == null) return;
    setState(() {
      _startAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<GeocodedPlace> _ensurePlace(
    MapsService maps,
    GeocodedPlace? selected,
    String text,
    String label,
  ) async {
    if (selected != null &&
        (selected.formattedAddress == text.trim() || selected.query == text.trim())) {
      return selected;
    }
    final q = text.trim();
    if (q.isEmpty) throw Exception('$label is required');
    final place = await maps.geocode(q);
    if (place == null) throw Exception('Could not find $label: $q');
    return place;
  }

  Future<({List<GeocodedPlace> places, MotorcycleRoute route})?> _resolveRoute() async {
    final maps = context.read<MapsService>();
    final meet = await _ensurePlace(maps, _meetPlace, _meet.text, 'Meeting point');
    final dest = await _ensurePlace(maps, _destPlace, _dest.text, 'Destination');

    final places = <GeocodedPlace>[meet];
    if (_fuelStop.text.trim().isNotEmpty) {
      places.add(await _ensurePlace(maps, _fuelPlace, _fuelStop.text, 'Fuel stop'));
    }
    if (_lunchStop.text.trim().isNotEmpty) {
      places.add(await _ensurePlace(maps, _lunchPlace, _lunchStop.text, 'Lunch stop'));
    }
    places.add(dest);

    final route = await maps.motorcycleRoute([
      for (final p in places) {'name': p.formattedAddress, 'lat': p.lat, 'lng': p.lng},
    ]);
    return (places: places, route: route);
  }

  Future<void> _previewRoute() async {
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final resolved = await _resolveRoute();
      if (resolved == null || !mounted) return;
      final places = resolved.places;
      final route = resolved.route;
      final km = (route.distanceMeters / 1000).toStringAsFixed(1);
      final mins = (route.durationSeconds / 60).round();
      setState(() {
        _previewPath = route.path.map((p) => LatLng(p.lat, p.lng)).toList();
        if (_previewPath.length < 2) {
          _previewPath = places.map((p) => LatLng(p.lat, p.lng)).toList();
        }
        _previewMarkers
          ..clear()
          ..addAll([
            Marker(
              point: LatLng(places.first.lat, places.first.lng),
              width: 36,
              height: 36,
              child: const Icon(Icons.flag, color: AppTheme.signalSoft),
            ),
            for (var i = 1; i < places.length - 1; i++)
              Marker(
                point: LatLng(places[i].lat, places[i].lng),
                width: 36,
                height: 36,
                child: const Icon(Icons.place, color: AppTheme.fuel),
              ),
            Marker(
              point: LatLng(places.last.lat, places.last.lng),
              width: 36,
              height: 36,
              child: const Icon(Icons.sports_score, color: AppTheme.signal),
            ),
          ]);
        _routeSummary =
            '${route.travelMode} · $km km · ~$mins min (Google Maps motorbike routing)';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final maps = context.read<MapsService>();
      final rides = context.read<RideService>();
      final meet = await _ensurePlace(maps, _meetPlace, _meet.text, 'Meeting point');
      final dest = await _ensurePlace(maps, _destPlace, _dest.text, 'Destination');

      final stops = <Map<String, dynamic>>[];
      var order = 1;
      if (_fuelStop.text.trim().isNotEmpty) {
        final fuel = await _ensurePlace(maps, _fuelPlace, _fuelStop.text, 'Fuel stop');
        stops.add({
          'name': fuel.formattedAddress,
          'kind': 'fuel',
          'lat': fuel.lat,
          'lng': fuel.lng,
          'sortOrder': order++,
        });
      }
      if (_lunchStop.text.trim().isNotEmpty) {
        final lunch = await _ensurePlace(maps, _lunchPlace, _lunchStop.text, 'Lunch stop');
        stops.add({
          'name': lunch.formattedAddress,
          'kind': 'lunch',
          'lat': lunch.lat,
          'lng': lunch.lng,
          'sortOrder': order++,
        });
      }

      await rides.createRide({
        'name': _name.text.trim(),
        'startAt': _startAt.toUtc().toIso8601String(),
        'meetPointName': meet.formattedAddress,
        'meetLat': meet.lat,
        'meetLng': meet.lng,
        'destinationName': dest.formattedAddress,
        'destinationLat': dest.lat,
        'destinationLng': dest.lng,
        'resolvePlaces': false,
        'buildMotorcycleRoute': true,
        'stops': stops,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
