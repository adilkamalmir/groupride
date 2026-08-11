import '../models/models.dart';
import 'api_client.dart';

class RideService {
  RideService(this._api);
  final ApiClient _api;

  Future<List<Ride>> listRides() async {
    final data = await _api.get('/api/rides') as List;
    return data.map((e) => Ride.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Ride> getRide(String id) async {
    final data = await _api.get('/api/rides/$id');
    return Ride.fromJson(data as Map<String, dynamic>);
  }

  Future<Ride> createRide(Map<String, dynamic> body) async {
    final data = await _api.post('/api/rides', body);
    return Ride.fromJson(data as Map<String, dynamic>);
  }

  Future<Ride> startRide(String id) async {
    final data = await _api.post('/api/rides/$id/start');
    return Ride.fromJson(data as Map<String, dynamic>);
  }

  Future<Ride> endRide(String id) async {
    final data = await _api.post('/api/rides/$id/end');
    return Ride.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteRide(String id) async {
    try {
      await _api.delete('/api/rides/$id');
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) {
        await _api.post('/api/rides/$id/delete');
        return;
      }
      rethrow;
    }
  }

  Future<void> startDemo(String id) async {
    try {
      await _api.post('/api/rides/$id/demo', {});
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) {
        await _api.post('/api/rides/$id/start-demo', {});
        return;
      }
      rethrow;
    }
  }

  Future<Ride> assignRole(String rideId, String userId, String role) async {
    final data = await _api.post('/api/rides/$rideId/roles', {
      'userId': userId,
      'role': role,
    });
    return Ride.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getInvite(String rideId) async {
    return await _api.get('/api/rides/$rideId/invite') as Map<String, dynamic>;
  }

  Future<Ride> peekInvite(String token) async {
    final data = await _api.get('/api/invites/$token');
    return Ride.fromJson(data as Map<String, dynamic>);
  }

  Future<Ride> joinInvite(String token) async {
    final data = await _api.post('/api/invites/$token/join');
    return Ride.fromJson(data as Map<String, dynamic>);
  }

  Future<Timeline> getTimeline(String rideId) async {
    final data = await _api.get('/api/rides/$rideId/timeline');
    return Timeline.fromJson(data as Map<String, dynamic>);
  }

  Future<List<RideAlert>> getAlerts(String rideId) async {
    final data = await _api.get('/api/rides/$rideId/alerts') as List;
    return data.map((e) => RideAlert.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LocationPing>> getLocations(String rideId, {int limit = 200}) async {
    final data = await _api.get('/api/rides/$rideId/locations?limit=$limit') as List;
    return data.map((e) => LocationPing.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<EmergencyEvent>> getEmergencies(String rideId) async {
    final data = await _api.get('/api/rides/$rideId/emergencies') as List;
    return data.map((e) => EmergencyEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> acknowledgeEmergency(String rideId, String emergencyId) async {
    await _api.post('/api/rides/$rideId/emergencies/$emergencyId/ack');
  }

  Future<Timeline> addTimelinePhotos(String rideId, List<String> urls) async {
    final data = await _api.post('/api/rides/$rideId/timeline/photos', {
      'photoUrls': urls,
    });
    return Timeline.fromJson(data as Map<String, dynamic>);
  }
}
