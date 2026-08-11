import '../services/api_client.dart';
import 'local_places_fallback.dart';

class GeocodedPlace {
  GeocodedPlace({
    required this.query,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    this.placeId,
  });

  final String query;
  final String formattedAddress;
  final double lat;
  final double lng;
  final String? placeId;

  factory GeocodedPlace.fromJson(Map<String, dynamic> json) => GeocodedPlace(
        query: json['query'] as String? ?? '',
        formattedAddress: json['formattedAddress'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        placeId: json['placeId'] as String?,
      );
}

class MotorcycleRoute {
  MotorcycleRoute({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.travelMode,
    required this.encodedPolyline,
    required this.path,
  });

  final double distanceMeters;
  final double durationSeconds;
  final String travelMode;
  final String encodedPolyline;
  final List<({double lat, double lng})> path;

  factory MotorcycleRoute.fromJson(Map<String, dynamic> json) {
    final pathJson = json['path'] as List? ?? const [];
    return MotorcycleRoute(
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      travelMode: json['travelMode'] as String? ?? 'unknown',
      encodedPolyline: json['encodedPolyline'] as String? ?? '',
      path: pathJson.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return (lat: (m['lat'] as num).toDouble(), lng: (m['lng'] as num).toDouble());
      }).toList(),
    );
  }
}

class MapsConfig {
  MapsConfig({
    required this.provider,
    required this.supportsMotorcycleRouting,
  });

  final String provider;
  final bool supportsMotorcycleRouting;

  factory MapsConfig.fromJson(Map<String, dynamic> json) => MapsConfig(
        provider: json['provider'] as String? ?? 'local',
        supportsMotorcycleRouting: json['supportsMotorcycleRouting'] as bool? ?? false,
      );
}

class PlaceSuggestion {
  PlaceSuggestion({
    required this.placeId,
    required this.description,
    this.mainText,
    this.secondaryText,
  });

  final String placeId;
  final String description;
  final String? mainText;
  final String? secondaryText;

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) => PlaceSuggestion(
        placeId: json['placeId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        mainText: json['mainText'] as String?,
        secondaryText: json['secondaryText'] as String?,
      );
}

class MapsService {
  MapsService(this._api);
  final ApiClient _api;

  Future<MapsConfig> getConfig() async {
    final data = await _api.get('/api/maps/config') as Map<String, dynamic>;
    return MapsConfig.fromJson(data);
  }

  Future<GeocodedPlace?> geocode(String query) async {
    try {
      final data = await _api.get('/api/maps/geocode?q=${Uri.encodeQueryComponent(query)}');
      return GeocodedPlace.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final params = <String, String>{
      if (query.trim().isNotEmpty) 'q': query.trim(),
      if (lat != null) 'lat': lat.toString(),
      if (lng != null) 'lng': lng.toString(),
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final data = await _api.get('/api/maps/autocomplete${qs.isEmpty ? '' : '?$qs'}');
    final list = data as List? ?? const [];
    return list
        .map((e) => PlaceSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((s) => s.placeId.isNotEmpty && s.description.isNotEmpty)
        .toList();
  }

  Future<List<PlaceSuggestion>> nearby({
    required double lat,
    required double lng,
    String? kind,
  }) async {
    final kindQs = kind == null ? '' : '&kind=${Uri.encodeQueryComponent(kind)}';
    try {
      final data = await _api.get('/api/maps/nearby?lat=$lat&lng=$lng$kindQs');
      final list = data as List? ?? const [];
      final parsed = list
          .map((e) => PlaceSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((s) => s.placeId.isNotEmpty && s.description.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) return parsed;
    } on ApiException catch (e) {
      // Older API builds lack /nearby — try aliases + autocomplete, then local list.
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
      try {
        final data = await _api.get('/api/maps/places-nearby?lat=$lat&lng=$lng$kindQs');
        final list = data as List? ?? const [];
        final parsed = list
            .map((e) => PlaceSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((s) => s.placeId.isNotEmpty && s.description.isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) return parsed;
      } on ApiException {
        // continue
      }
      try {
        final viaAuto = await autocomplete('', lat: lat, lng: lng);
        if (viaAuto.isNotEmpty) return viaAuto;
      } on ApiException {
        // continue
      }
    }
    return LocalPlacesFallback.nearby(lat, lng, kind: kind);
  }

  Future<GeocodedPlace?> placeDetails(String placeId) async {
    if (placeId.startsWith('local:')) {
      final local = LocalPlacesFallback.resolve(placeId);
      if (local != null) return local;
    }
    try {
      final data =
          await _api.get('/api/maps/place?placeId=${Uri.encodeQueryComponent(placeId)}');
      return GeocodedPlace.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return LocalPlacesFallback.resolve(placeId);
      }
      rethrow;
    }
  }

  Future<MotorcycleRoute> motorcycleRoute(List<Map<String, dynamic>> waypoints) async {
    final data = await _api.post('/api/maps/route', {'waypoints': waypoints});
    return MotorcycleRoute.fromJson(data as Map<String, dynamic>);
  }

  Future<List<GeocodedPlace>> stopsAlongRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    List<({double lat, double lng})>? path,
  }) async {
    final data = await _api.post('/api/maps/stops-along-route', {
      'origin': {'lat': originLat, 'lng': originLng},
      'destination': {'lat': destLat, 'lng': destLng},
      if (path != null)
        'path': [
          for (final p in path) {'lat': p.lat, 'lng': p.lng},
        ],
    });
    final list = data as List? ?? const [];
    return list.map((e) => GeocodedPlace.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}
