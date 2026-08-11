import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../config.dart';
import '../models/models.dart';

class RideRealtimeService extends ChangeNotifier {
  HubConnection? _hub;
  String? _rideId;

  final List<RiderLocation> riders = [];
  final List<RideAlert> alerts = [];
  String? lastFuelMessage;
  Map<String, dynamic>? lastEmergency;
  Map<String, dynamic>? lastRegroup;
  bool connected = false;
  bool rideCompleted = false;

  Future<void> connect(String token, String rideId) async {
    await disconnect();
    _rideId = rideId;
    rideCompleted = false;
    riders.clear();
    alerts.clear();

    final hub = HubConnectionBuilder()
        .withUrl(
          '${AppConfig.hubUrl}?access_token=$token',
          options: HttpConnectionOptions(
            accessTokenFactory: () async => token,
          ),
        )
        .withAutomaticReconnect()
        .build();

    hub.on('RiderLocationsUpdated', (args) {
      if (args == null || args.isEmpty) return;
      final list = args[0];
      riders
        ..clear()
        ..addAll(_parseLocations(list));
      notifyListeners();
    });

    hub.on('AlertRaised', (args) {
      if (args == null || args.isEmpty) return;
      final map = _asMap(args[0]);
      if (map != null) {
        alerts.insert(0, RideAlert.fromJson(map));
        notifyListeners();
      }
    });

    hub.on('RegroupSuggested', (args) {
      if (args == null || args.isEmpty) return;
      lastRegroup = _asMap(args[0]);
      notifyListeners();
    });

    hub.on('EmergencyRaised', (args) {
      if (args == null || args.isEmpty) return;
      lastEmergency = _asMap(args[0]);
      notifyListeners();
    });

    hub.on('FuelStatus', (args) {
      if (args == null || args.isEmpty) return;
      final map = _asMap(args[0]);
      lastFuelMessage = map?['message'] as String?;
      notifyListeners();
    });

    hub.on('RiderStatusChanged', (args) {
      notifyListeners();
    });

    hub.on('RideCompleted', (args) {
      rideCompleted = true;
      notifyListeners();
    });

    hub.on('RideStateChanged', (args) {
      final map = args == null || args.isEmpty ? null : _asMap(args[0]);
      final status = map?['status']?.toString().toLowerCase();
      if (status == 'completed') {
        rideCompleted = true;
      }
      notifyListeners();
    });

    hub.onclose(({error}) {
      connected = false;
      notifyListeners();
    });

    hub.onreconnected(({connectionId}) async {
      connected = true;
      final rideId = _rideId;
      if (rideId != null) {
        await hub.invoke('JoinRide', args: [rideId]);
      }
      notifyListeners();
    });

    await hub.start();
    await hub.invoke('JoinRide', args: [rideId]);
    _hub = hub;
    connected = true;
    notifyListeners();
  }

  Future<void> updateLocation({
    required double lat,
    required double lng,
    double? speedMps,
    double? heading,
    double? accuracy,
  }) async {
    final hub = _hub;
    final rideId = _rideId;
    if (hub == null || rideId == null) return;
    await hub.invoke('UpdateLocation', args: [
      rideId,
      {
        'lat': lat,
        'lng': lng,
        'speedMps': speedMps,
        'heading': heading,
        'accuracyMeters': accuracy,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }
    ]);
  }

  Future<void> setStatus(String status) async {
    final hub = _hub;
    final rideId = _rideId;
    if (hub == null || rideId == null) return;
    await hub.invoke('SetStatus', args: [
      rideId,
      {'status': status}
    ]);
  }

  Future<void> announce(String message) async {
    final hub = _hub;
    final rideId = _rideId;
    if (hub == null || rideId == null) return;
    await hub.invoke('SendAnnouncement', args: [
      rideId,
      {'message': message}
    ]);
  }

  Future<void> raiseEmergency({
    required String type,
    required double lat,
    required double lng,
    String? notes,
  }) async {
    final hub = _hub;
    final rideId = _rideId;
    if (hub == null || rideId == null) return;
    await hub.invoke('RaiseEmergency', args: [
      rideId,
      {'type': type, 'lat': lat, 'lng': lng, 'notes': notes}
    ]);
  }

  Future<RejoinTarget?> requestRejoin(String target) async {
    final hub = _hub;
    final rideId = _rideId;
    if (hub == null || rideId == null) return null;
    final result = await hub.invoke('RequestRejoinTarget', args: [
      rideId,
      {'target': target}
    ]);
    final map = _asMap(result);
    return map == null ? null : RejoinTarget.fromJson(map);
  }

  Future<void> disconnect() async {
    final hub = _hub;
    final rideId = _rideId;
    _hub = null;
    connected = false;
    if (hub != null) {
      try {
        if (rideId != null) {
          await hub.invoke('LeaveRide', args: [rideId]);
        }
        await hub.stop();
      } catch (_) {}
    }
    _rideId = null;
  }

  List<RiderLocation> _parseLocations(dynamic list) {
    if (list is! List) return [];
    return list
        .map((e) => RiderLocation.fromJson(_asMap(e)!))
        .whereType<RiderLocation>()
        .toList();
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      try {
        return jsonDecode(v) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
