import 'dart:math' as math;

import 'maps_service.dart';

/// Offline place suggestions used when `/api/maps/nearby` is unavailable
/// (e.g. API container not rebuilt with the latest endpoints).
class LocalPlacesFallback {
  LocalPlacesFallback._();

  static const _places = <({String name, String address, double lat, double lng, String kind})>[
    (name: 'Tim Hortons Kanata', address: 'Tim Hortons, Kanata, ON', lat: 45.3001, lng: -75.9105, kind: 'coffee'),
    (name: 'Bridgehead Coffee Westboro', address: 'Westboro, Ottawa, ON', lat: 45.3930, lng: -75.7550, kind: 'coffee'),
    (name: 'Canadian Tire Gas Barrhaven', address: 'Barrhaven, ON', lat: 45.2750, lng: -75.7360, kind: 'fuel'),
    (name: 'Renfrew Petro-Canada', address: 'Renfrew, ON', lat: 45.4747, lng: -76.6831, kind: 'fuel'),
    (name: 'Calabogie Motorsports Park', address: 'Calabogie, ON', lat: 45.3008, lng: -76.7175, kind: 'parking'),
    (name: 'Arnprior Rest Stop', address: 'Arnprior, ON', lat: 45.4333, lng: -76.3500, kind: 'rest'),
    (name: 'Mississippi Mills Parking', address: 'Mississippi Mills, ON', lat: 45.2260, lng: -76.1940, kind: 'parking'),
    (name: 'Champlain Lookout', address: 'Gatineau Park, QC', lat: 45.4890, lng: -75.8670, kind: 'viewpoint'),
    (name: 'Ottawa River Parkway View', address: 'Ottawa, ON', lat: 45.4100, lng: -75.7500, kind: 'viewpoint'),
    (name: 'The Works Gatineau', address: 'Gatineau, QC', lat: 45.4280, lng: -75.7100, kind: 'food'),
    (name: 'Ottawa', address: 'Ottawa, ON', lat: 45.4215, lng: -75.6972, kind: 'city'),
    (name: 'Kanata', address: 'Kanata, ON', lat: 45.3001, lng: -75.9105, kind: 'city'),
    (name: 'Barrhaven', address: 'Barrhaven, ON', lat: 45.2750, lng: -75.7360, kind: 'city'),
  ];

  static List<PlaceSuggestion> nearby(double lat, double lng, {String? kind}) {
    final kindFilter = kind?.toLowerCase();
    final scored = _places.map((p) {
      final km = _haversineKm(lat, lng, p.lat, p.lng);
      return (place: p, km: km);
    }).where((x) {
      if (x.km > 80) return false;
      if (kindFilter == null || kindFilter == 'other') return true;
      if (kindFilter == 'fuel' || kindFilter == 'gas') return x.place.kind == 'fuel';
      if (kindFilter == 'coffee' || kindFilter == 'cafe') return x.place.kind == 'coffee';
      if (kindFilter == 'viewpoint' || kindFilter == 'views' || kindFilter == 'scenic') {
        return x.place.kind == 'viewpoint';
      }
      if (kindFilter == 'food' || kindFilter == 'lunch' || kindFilter == 'restaurant') {
        return x.place.kind == 'food';
      }
      if (kindFilter == 'parking') return x.place.kind == 'parking';
      if (kindFilter == 'rest') return x.place.kind == 'rest';
      return true;
    }).toList()
      ..sort((a, b) => a.km.compareTo(b.km));

    return scored.take(8).map((x) {
      return PlaceSuggestion(
        placeId: 'local:${x.place.name}',
        description: x.place.address,
        mainText: x.place.name,
        secondaryText: '${x.km.toStringAsFixed(1)} km away',
      );
    }).toList();
  }

  static GeocodedPlace? resolve(String placeId) {
    final key = placeId.startsWith('local:') ? placeId.substring('local:'.length) : placeId;
    for (final p in _places) {
      if (p.name.toLowerCase() == key.toLowerCase()) {
        return GeocodedPlace(
          query: p.name,
          formattedAddress: p.address,
          lat: p.lat,
          lng: p.lng,
          placeId: 'local:${p.name}',
        );
      }
    }
    return null;
  }

  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
