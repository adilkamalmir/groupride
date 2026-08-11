import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Publishes GPS every [intervalSeconds] and buffers pings while offline.
class LocationService extends ChangeNotifier {
  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool tracking = false;
  Position? lastPosition;
  final List<Map<String, dynamic>> _buffer = [];
  Future<void> Function(Map<String, dynamic> ping)? onPing;

  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      return false;
    }
    final service = await Geolocator.isLocationServiceEnabled();
    return service;
  }

  Future<Position?> currentPosition() async {
    final ok = await ensurePermission();
    if (!ok) return lastPosition;

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        lastPosition = last;
        notifyListeners();
      }
    } catch (_) {}

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      lastPosition = pos;
      notifyListeners();
      return pos;
    } catch (_) {
      return lastPosition;
    }
  }

  Future<void> start({int intervalSeconds = 8}) async {
    if (tracking) return;
    final ok = await ensurePermission();
    if (!ok) throw Exception('Location permission required');

    tracking = true;
    await _loadBuffer();

    final settings = const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      lastPosition = pos;
      notifyListeners();
    });

    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      await _emit();
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) async {
      await flushBuffer();
    });

    await _emit();
    notifyListeners();
  }

  Future<void> stop() async {
    tracking = false;
    _timer?.cancel();
    await _positionSub?.cancel();
    await _connectivitySub?.cancel();
    _timer = null;
    _positionSub = null;
    _connectivitySub = null;
    notifyListeners();
  }

  Future<void> _emit() async {
    try {
      final pos = lastPosition ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
            ),
          );
      lastPosition = pos;
      final ping = {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'speedMps': pos.speed.isNaN ? null : pos.speed,
        'heading': pos.heading.isNaN ? null : pos.heading,
        'accuracy': pos.accuracy,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      final connectivity = await Connectivity().checkConnectivity();
      final offline = connectivity.contains(ConnectivityResult.none);

      if (offline || onPing == null) {
        _buffer.add(ping);
        await _persistBuffer();
      } else {
        try {
          await onPing!(ping);
          await flushBuffer();
        } catch (_) {
          _buffer.add(ping);
          await _persistBuffer();
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Location emit failed: $e');
    }
  }

  Future<void> flushBuffer() async {
    if (onPing == null || _buffer.isEmpty) return;
    final copy = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    for (final ping in copy) {
      try {
        await onPing!(ping);
      } catch (_) {
        _buffer.add(ping);
      }
    }
    await _persistBuffer();
  }

  Future<File> _bufferFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/location_buffer.json');
  }

  Future<void> _persistBuffer() async {
    try {
      final file = await _bufferFile();
      await file.writeAsString(jsonEncode(_buffer));
    } catch (_) {}
  }

  Future<void> _loadBuffer() async {
    try {
      final file = await _bufferFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List;
        _buffer
          ..clear()
          ..addAll(data.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
  }

  int get bufferedCount => _buffer.length;
}
