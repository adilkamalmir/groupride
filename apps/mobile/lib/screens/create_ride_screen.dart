import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/location_service.dart';
import '../services/maps_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets/app_map_style.dart';
import '../widgets/place_autocomplete_field.dart';
import '../widgets/stop_picker_section.dart';

class _StopDraft {
  _StopDraft({this.kind = 'fuel', this.place, String? label}) {
    if (place != null) {
      controller.text = place!.formattedAddress;
    } else if (label != null) {
      controller.text = label;
    }
  }
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
  double? _hereLat;
  double? _hereLng;
  bool _locating = true;
  String? _locationError;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocation());
  }

  Future<void> _loadLocation() async {
    if (!mounted) return;
    setState(() {
      _locating = true;
      _locationError = null;
    });

    final location = context.read<LocationService>();
    final permitted = await location.ensurePermission();
    if (!mounted) return;
    if (!permitted) {
      setState(() {
        _locating = false;
        _locationError =
            'Location permission is required so Google can suggest places near you.';
      });
      return;
    }

    final pos = await location.currentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() {
        _locating = false;
        _locationError =
            'Could not read your GPS. In Simulator: Features → Location → Custom Location, then tap Retry.';
      });
      return;
    }

    setState(() {
      _hereLat = pos.latitude;
      _hereLng = pos.longitude;
      _locating = false;
      _locationError = null;
    });
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

  double? get _biasLat => _meetPlace?.lat ?? _hereLat;
  double? get _biasLng => _meetPlace?.lng ?? _hereLng;
  bool get _hasGps => _hereLat != null && _hereLng != null;

  double? get _stopBiasLat {
    if (_previewPath.length >= 2) {
      return _previewPath[_previewPath.length ~/ 2].latitude;
    }
    if (_meetPlace != null && _destPlace != null) {
      return (_meetPlace!.lat + _destPlace!.lat) / 2;
    }
    return _biasLat;
  }

  double? get _stopBiasLng {
    if (_previewPath.length >= 2) {
      return _previewPath[_previewPath.length ~/ 2].longitude;
    }
    if (_meetPlace != null && _destPlace != null) {
      return (_meetPlace!.lng + _destPlace!.lng) / 2;
    }
    return _biasLng;
  }

  String _normalizeKind(String kind) {
    switch (kind.toLowerCase()) {
      case 'gas':
      case 'fuel':
        return 'fuel';
      case 'coffee':
      case 'cafe':
        return 'coffee';
      case 'viewpoint':
      case 'views':
      case 'scenic':
        return 'viewpoint';
      case 'food':
      case 'lunch':
      case 'restaurant':
        return 'lunch';
      case 'parking':
        return 'parking';
      case 'rest':
        return 'rest';
      default:
        return 'other';
    }
  }

  void _addStop(GeocodedPlace place, String kind) {
    setState(() {
      _stops.add(
        _StopDraft(
          kind: _normalizeKind(kind),
          place: place,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create ride')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_locating)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Getting your location…'),
                subtitle: Text('Suggestions will use your GPS position'),
              ),
            ),
          if (_locationError != null) ...[
            Text(_locationError!, style: const TextStyle(color: AppTheme.emergency)),
            TextButton.icon(
              onPressed: _loadLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Retry location'),
            ),
            const SizedBox(height: 8),
          ],
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
            enabled: _hasGps,
            biasLat: _biasLat,
            biasLng: _biasLng,
            onPlaceSelected: (p) => setState(() => _meetPlace = p),
          ),
          const SizedBox(height: 12),
          PlaceAutocompleteField(
            controller: _dest,
            label: 'Destination',
            enabled: _hasGps,
            biasLat: _biasLat,
            biasLng: _biasLng,
            onPlaceSelected: (p) => setState(() => _destPlace = p),
          ),
          const SizedBox(height: 20),
          const Text('Stops', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Search any place, or browse gas, coffee, views, food, and parking near the route.',
            style: TextStyle(color: AppTheme.steel, fontSize: 13),
          ),
          const SizedBox(height: 12),
          StopPickerSection(
            enabled: _hasGps,
            biasLat: _stopBiasLat,
            biasLng: _stopBiasLng,
            onStopPicked: _addStop,
          ),
          if (_stops.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Added stops', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (var i = 0; i < _stops.length; i++) ...[
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    _stopIcon(_stops[i].kind),
                    color: AppTheme.signalSoft,
                  ),
                  title: Text(
                    _stops[i].controller.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_stops[i].kind),
                  trailing: IconButton(
                    onPressed: () {
                      setState(() {
                        _stops[i].dispose();
                        _stops.removeAt(i);
                      });
                    },
                    icon: const Icon(Icons.close, color: AppTheme.steel),
                  ),
                ),
              ),
            ],
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
                height: 240,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _previewPath[_previewPath.length ~/ 2],
                    initialZoom: 10,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    AppMapStyle.tileLayer(),
                    PolylineLayer(polylines: AppMapStyle.routePolylines(_previewPath)),
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

  IconData _stopIcon(String kind) {
    switch (kind) {
      case 'fuel':
        return Icons.local_gas_station;
      case 'coffee':
        return Icons.coffee;
      case 'viewpoint':
        return Icons.landscape;
      case 'lunch':
        return Icons.restaurant;
      case 'parking':
        return Icons.local_parking;
      case 'rest':
        return Icons.airline_seat_recline_extra;
      default:
        return Icons.place;
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
            AppMapStyle.pin(
              point: LatLng(places.first.lat, places.first.lng),
              color: AppMapStyle.startPin,
              icon: Icons.flag,
            ),
            for (var i = 1; i < places.length - 1; i++)
              AppMapStyle.pin(
                point: LatLng(places[i].lat, places[i].lng),
                color: AppTheme.fuel,
                icon: Icons.place,
                size: 34,
              ),
            AppMapStyle.pin(
              point: LatLng(places.last.lat, places.last.lng),
              color: AppMapStyle.endPin,
              icon: Icons.sports_score,
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
