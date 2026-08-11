import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/location_service.dart';
import '../services/maps_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets/place_autocomplete_field.dart';

class _StopDraft {
  _StopDraft({this.kind = 'fuel'});
  final controller = TextEditingController();
  GeocodedPlace? place;
  String kind;

  void dispose() => controller.dispose();
}

class CreateRideScreen extends StatefulWidget {
  const CreateRideScreen({super.key});

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  final _name = TextEditingController();
  final _meet = TextEditingController();
  final _dest = TextEditingController();
  final List<_StopDraft> _stops = [];

  GeocodedPlace? _meetPlace;
  GeocodedPlace? _destPlace;
  /// Always seeded with Ottawa simulator coords so suggestions are local even before GPS returns.
  double _hereLat = AppConfig.defaultLat;
  double _hereLng = AppConfig.defaultLng;
  bool _usingLiveGps = false;
  List<GeocodedPlace> _routeStopIdeas = const [];
  List<PlaceSuggestion> _nearYou = const [];

  DateTime _startAt = DateTime.now().add(const Duration(days: 1)).copyWith(
        hour: 10,
        minute: 0,
        second: 0,
        millisecond: 0,
        microsecond: 0,
      );
  bool _busy = false;
  bool _previewing = false;
  bool _loadingIdeas = false;
  String? _error;
  String? _routeSummary;
  List<LatLng> _previewPath = const [];
  final List<Marker> _previewMarkers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadNearYou();
      await _loadLocation();
    });
  }

  Future<void> _loadLocation() async {
    if (!mounted) return;
    final pos = await context.read<LocationService>().currentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _hereLat = pos.latitude;
      _hereLng = pos.longitude;
      _usingLiveGps = true;
    });
    await _loadNearYou();
  }

  Future<void> _loadNearYou() async {
    try {
      final near = await context.read<MapsService>().nearby(
            lat: _hereLat,
            lng: _hereLng,
          );
      if (!mounted) return;
      setState(() => _nearYou = near);
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _meet.dispose();
    _dest.dispose();
    for (final s in _stops) {
      s.dispose();
    }
    super.dispose();
  }

  double get _biasLat => _meetPlace?.lat ?? _hereLat;
  double get _biasLng => _meetPlace?.lng ?? _hereLng;

  @override
  Widget build(BuildContext context) {
    final locationHint = _usingLiveGps
        ? 'Near your GPS (${_hereLat.toStringAsFixed(2)}, ${_hereLng.toStringAsFixed(2)})'
        : 'Near Ottawa simulator location (${_hereLat.toStringAsFixed(2)}, ${_hereLng.toStringAsFixed(2)})';

    return Scaffold(
      appBar: AppBar(title: const Text('Create ride')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Ride name',
              hintText: 'e.g. Sunday valley loop',
            ),
          ),
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
            helperText: locationHint,
            biasLat: _biasLat,
            biasLng: _biasLng,
            onPlaceSelected: (p) {
              setState(() => _meetPlace = p);
              _maybeLoadStopIdeas();
            },
          ),
          if (_nearYou.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Near you', style: const TextStyle(color: AppTheme.steel, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _nearYou.take(6))
                  ActionChip(
                    avatar: const Icon(Icons.near_me, size: 16),
                    label: Text(s.mainText ?? s.description),
                    onPressed: () => _pickNearYou(s, isMeet: true),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          PlaceAutocompleteField(
            controller: _dest,
            label: 'Destination',
            helperText: locationHint,
            biasLat: _biasLat,
            biasLng: _biasLng,
            onPlaceSelected: (p) {
              setState(() => _destPlace = p);
              _maybeLoadStopIdeas();
            },
          ),
          if (_nearYou.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _nearYou.take(6))
                  ActionChip(
                    label: Text(s.mainText ?? s.description),
                    onPressed: () => _pickNearYou(s, isMeet: false),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Stops', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _stops.add(_StopDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Add stop'),
              ),
            ],
          ),
          if (_loadingIdeas)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          if (_routeStopIdeas.isNotEmpty) ...[
            const Text('Suggested along route', style: TextStyle(color: AppTheme.steel, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final idea in _routeStopIdeas)
                  ActionChip(
                    label: Text(idea.query.isEmpty ? idea.formattedAddress : idea.query),
                    onPressed: () => _addSuggestedStop(idea),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < _stops.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PlaceAutocompleteField(
                    controller: _stops[i].controller,
                    label: 'Stop ${i + 1}',
                    biasLat: _stopBiasLat,
                    biasLng: _stopBiasLng,
                    nearbyKind: _stops[i].kind,
                    onPlaceSelected: (p) => setState(() => _stops[i].place = p),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    DropdownButton<String>(
                      value: _stops[i].kind,
                      items: const [
                        DropdownMenuItem(value: 'fuel', child: Text('Fuel')),
                        DropdownMenuItem(value: 'lunch', child: Text('Lunch')),
                        DropdownMenuItem(value: 'rest', child: Text('Rest')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _stops[i].kind = v ?? 'fuel'),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _stops[i].dispose();
                          _stops.removeAt(i);
                        });
                      },
                      icon: const Icon(Icons.close, color: AppTheme.steel),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
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

  double get _stopBiasLat {
    if (_previewPath.length >= 2) {
      return _previewPath[_previewPath.length ~/ 2].latitude;
    }
    if (_meetPlace != null && _destPlace != null) {
      return (_meetPlace!.lat + _destPlace!.lat) / 2;
    }
    return _biasLat;
  }

  double get _stopBiasLng {
    if (_previewPath.length >= 2) {
      return _previewPath[_previewPath.length ~/ 2].longitude;
    }
    if (_meetPlace != null && _destPlace != null) {
      return (_meetPlace!.lng + _destPlace!.lng) / 2;
    }
    return _biasLng;
  }

  Future<void> _pickNearYou(PlaceSuggestion suggestion, {required bool isMeet}) async {
    final maps = context.read<MapsService>();
    final place = await maps.placeDetails(suggestion.placeId) ??
        await maps.geocode(suggestion.description);
    if (place == null || !mounted) return;
    setState(() {
      if (isMeet) {
        _meetPlace = place;
        _meet.text = place.formattedAddress;
      } else {
        _destPlace = place;
        _dest.text = place.formattedAddress;
      }
    });
    await _maybeLoadStopIdeas();
  }

  void _addSuggestedStop(GeocodedPlace idea) {
    final draft = _StopDraft(
      kind: idea.query.toLowerCase().contains('gas') ||
              idea.formattedAddress.toLowerCase().contains('gas')
          ? 'fuel'
          : 'lunch',
    );
    draft.place = idea;
    draft.controller.text = idea.formattedAddress;
    setState(() => _stops.add(draft));
  }

  Future<void> _maybeLoadStopIdeas() async {
    if (_meetPlace == null || _destPlace == null) return;
    setState(() => _loadingIdeas = true);
    try {
      final maps = context.read<MapsService>();
      var path = <({double lat, double lng})>[
        (lat: _meetPlace!.lat, lng: _meetPlace!.lng),
        (lat: _destPlace!.lat, lng: _destPlace!.lng),
      ];
      try {
        final route = await maps.motorcycleRoute([
          {'name': _meetPlace!.formattedAddress, 'lat': _meetPlace!.lat, 'lng': _meetPlace!.lng},
          {'name': _destPlace!.formattedAddress, 'lat': _destPlace!.lat, 'lng': _destPlace!.lng},
        ]);
        if (route.path.length >= 2) path = route.path;
      } catch (_) {}

      final ideas = await maps.stopsAlongRoute(
        originLat: _meetPlace!.lat,
        originLng: _meetPlace!.lng,
        destLat: _destPlace!.lat,
        destLng: _destPlace!.lng,
        path: path,
      );
      if (!mounted) return;
      setState(() => _routeStopIdeas = ideas);
    } catch (_) {
      // Suggestions are optional.
    } finally {
      if (mounted) setState(() => _loadingIdeas = false);
    }
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
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      if (s.controller.text.trim().isEmpty) continue;
      places.add(await _ensurePlace(maps, s.place, s.controller.text, 'Stop ${i + 1}'));
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
      await _maybeLoadStopIdeas();
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
      if (_name.text.trim().isEmpty) {
        throw Exception('Ride name is required');
      }
      final maps = context.read<MapsService>();
      final rides = context.read<RideService>();
      final meet = await _ensurePlace(maps, _meetPlace, _meet.text, 'Meeting point');
      final dest = await _ensurePlace(maps, _destPlace, _dest.text, 'Destination');

      final stops = <Map<String, dynamic>>[];
      var order = 1;
      for (final s in _stops) {
        if (s.controller.text.trim().isEmpty) continue;
        final place = await _ensurePlace(maps, s.place, s.controller.text, 'Stop');
        stops.add({
          'name': place.formattedAddress,
          'kind': s.kind,
          'lat': place.lat,
          'lng': place.lng,
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
