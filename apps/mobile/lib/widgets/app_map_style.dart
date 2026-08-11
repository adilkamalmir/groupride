import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Shared map look — street basemap + Google-like blue route.
class AppMapStyle {
  AppMapStyle._();

  /// Carto Voyager reads closer to Google Maps streets than plain OSM tiles.
  static const tileUrl =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  static const userAgent = 'com.groupride.mobile';

  static const routeBlue = Color(0xFF4285F4);
  static const routeOutline = Color(0xFFFFFFFF);
  static const startPin = Color(0xFF34A853);
  static const endPin = Color(0xFFEA4335);

  static TileLayer tileLayer() => TileLayer(
        urlTemplate: tileUrl,
        userAgentPackageName: userAgent,
        maxNativeZoom: 19,
      );

  static List<Polyline> routePolylines(List<LatLng> points, {double width = 5}) {
    if (points.length < 2) return const [];
    return [
      Polyline(
        points: points,
        color: routeOutline.withValues(alpha: 0.95),
        strokeWidth: width + 3,
      ),
      Polyline(
        points: points,
        color: routeBlue,
        strokeWidth: width,
      ),
    ];
  }

  static Marker pin({
    required LatLng point,
    required Color color,
    required IconData icon,
    double size = 40,
  }) {
    return Marker(
      point: point,
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}
