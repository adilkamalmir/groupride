class AuthResponse {
  final String token;
  final String userId;
  final String email;
  final String displayName;

  AuthResponse({
    required this.token,
    required this.userId,
    required this.email,
    required this.displayName,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> j) => AuthResponse(
        token: j['token'] as String,
        userId: j['userId'] as String,
        email: j['email'] as String,
        displayName: j['displayName'] as String,
      );
}

class BikeProfile {
  final String model;
  final double tankSizeLiters;
  final double typicalRangeKm;
  final double? distanceSinceFillKm;

  BikeProfile({
    required this.model,
    required this.tankSizeLiters,
    required this.typicalRangeKm,
    this.distanceSinceFillKm,
  });

  factory BikeProfile.fromJson(Map<String, dynamic> j) => BikeProfile(
        model: j['model'] as String,
        tankSizeLiters: (j['tankSizeLiters'] as num).toDouble(),
        typicalRangeKm: (j['typicalRangeKm'] as num).toDouble(),
        distanceSinceFillKm: (j['distanceSinceFillKm'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'model': model,
        'tankSizeLiters': tankSizeLiters,
        'typicalRangeKm': typicalRangeKm,
        'distanceSinceFillKm': distanceSinceFillKm,
      };
}

class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String? phone;
  final BikeProfile? bike;

  UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.phone,
    this.bike,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        email: j['email'] as String,
        displayName: j['displayName'] as String,
        phone: j['phone'] as String?,
        bike: j['bike'] != null
            ? BikeProfile.fromJson(j['bike'] as Map<String, dynamic>)
            : null,
      );
}

class RideStop {
  final String? id;
  final String name;
  final String? kind;
  final double lat;
  final double lng;
  final int sortOrder;
  final double? distanceFromStartKm;

  RideStop({
    this.id,
    required this.name,
    this.kind,
    required this.lat,
    required this.lng,
    required this.sortOrder,
    this.distanceFromStartKm,
  });

  factory RideStop.fromJson(Map<String, dynamic> j) => RideStop(
        id: j['id']?.toString(),
        name: j['name'] as String,
        kind: j['kind'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        sortOrder: j['sortOrder'] as int,
        distanceFromStartKm: (j['distanceFromStartKm'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'lat': lat,
        'lng': lng,
        'sortOrder': sortOrder,
        'distanceFromStartKm': distanceFromStartKm,
      };
}

class RideMember {
  final String userId;
  final String displayName;
  final String role;
  final String status;
  final String inviteStatus;
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastLocationAt;

  RideMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.status,
    required this.inviteStatus,
    this.lastLat,
    this.lastLng,
    this.lastLocationAt,
  });

  factory RideMember.fromJson(Map<String, dynamic> j) => RideMember(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        role: j['role'] as String,
        status: j['status'] as String,
        inviteStatus: j['inviteStatus'] as String,
        lastLat: (j['lastLat'] as num?)?.toDouble(),
        lastLng: (j['lastLng'] as num?)?.toDouble(),
        lastLocationAt: j['lastLocationAt'] != null
            ? DateTime.tryParse(j['lastLocationAt'] as String)
            : null,
      );
}

class Ride {
  final String id;
  final String name;
  final DateTime startAt;
  final String status;
  final String meetPointName;
  final double meetLat;
  final double meetLng;
  final String destinationName;
  final double destinationLat;
  final double destinationLng;
  final String? routePolyline;
  final double splitThresholdMeters;
  final int splitDurationSeconds;
  final int pingIntervalSeconds;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String inviteToken;
  final List<RideStop> stops;
  final List<RideMember> members;

  Ride({
    required this.id,
    required this.name,
    required this.startAt,
    required this.status,
    required this.meetPointName,
    required this.meetLat,
    required this.meetLng,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    this.routePolyline,
    required this.splitThresholdMeters,
    required this.splitDurationSeconds,
    required this.pingIntervalSeconds,
    this.startedAt,
    this.completedAt,
    required this.inviteToken,
    required this.stops,
    required this.members,
  });

  factory Ride.fromJson(Map<String, dynamic> j) => Ride(
        id: j['id'] as String,
        name: j['name'] as String,
        startAt: DateTime.parse(j['startAt'] as String),
        status: j['status'] as String,
        meetPointName: j['meetPointName'] as String,
        meetLat: (j['meetLat'] as num).toDouble(),
        meetLng: (j['meetLng'] as num).toDouble(),
        destinationName: j['destinationName'] as String,
        destinationLat: (j['destinationLat'] as num).toDouble(),
        destinationLng: (j['destinationLng'] as num).toDouble(),
        routePolyline: j['routePolyline'] as String?,
        splitThresholdMeters: (j['splitThresholdMeters'] as num).toDouble(),
        splitDurationSeconds: j['splitDurationSeconds'] as int,
        pingIntervalSeconds: j['pingIntervalSeconds'] as int,
        startedAt: j['startedAt'] != null
            ? DateTime.tryParse(j['startedAt'] as String)
            : null,
        completedAt: j['completedAt'] != null
            ? DateTime.tryParse(j['completedAt'] as String)
            : null,
        inviteToken: j['inviteToken'] as String? ?? '',
        stops: (j['stops'] as List? ?? [])
            .map((e) => RideStop.fromJson(e as Map<String, dynamic>))
            .toList(),
        members: (j['members'] as List? ?? [])
            .map((e) => RideMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get isLive => status.toLowerCase() == 'live';
  bool get isCompleted => status.toLowerCase() == 'completed';

  Duration get countdown {
    final diff = startAt.toLocal().difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
}

class RideAlert {
  final String id;
  final String type;
  final String message;
  final String? payloadJson;
  final String? relatedUserId;
  final DateTime createdAt;
  final String? recipientsJson;

  RideAlert({
    required this.id,
    required this.type,
    required this.message,
    this.payloadJson,
    this.relatedUserId,
    required this.createdAt,
    this.recipientsJson,
  });

  factory RideAlert.fromJson(Map<String, dynamic> j) => RideAlert(
        id: j['id'] as String,
        type: j['type'] as String,
        message: j['message'] as String,
        payloadJson: j['payloadJson'] as String?,
        relatedUserId: j['relatedUserId']?.toString(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        recipientsJson: j['recipientsJson'] as String?,
      );
}

class Timeline {
  final String rideId;
  final String rideName;
  final double distanceKm;
  final double durationMinutes;
  final String? routePolyline;
  final String? stopsJson;
  final String? attendanceJson;
  final String? photoUrlsJson;
  final DateTime createdAt;

  Timeline({
    required this.rideId,
    required this.rideName,
    required this.distanceKm,
    required this.durationMinutes,
    this.routePolyline,
    this.stopsJson,
    this.attendanceJson,
    this.photoUrlsJson,
    required this.createdAt,
  });

  factory Timeline.fromJson(Map<String, dynamic> j) => Timeline(
        rideId: j['rideId'] as String,
        rideName: j['rideName'] as String,
        distanceKm: (j['distanceKm'] as num).toDouble(),
        durationMinutes: (j['durationMinutes'] as num).toDouble(),
        routePolyline: j['routePolyline'] as String?,
        stopsJson: j['stopsJson'] as String?,
        attendanceJson: j['attendanceJson'] as String?,
        photoUrlsJson: j['photoUrlsJson'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class EmergencyEvent {
  final String id;
  final String userId;
  final String displayName;
  final String type;
  final double lat;
  final double lng;
  final String? notes;
  final DateTime createdAt;
  final String? acknowledgedByUserId;
  final DateTime? acknowledgedAt;
  final bool isResolved;

  EmergencyEvent({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.type,
    required this.lat,
    required this.lng,
    this.notes,
    required this.createdAt,
    this.acknowledgedByUserId,
    this.acknowledgedAt,
    required this.isResolved,
  });

  factory EmergencyEvent.fromJson(Map<String, dynamic> j) => EmergencyEvent(
        id: j['id'] as String,
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? '',
        type: j['type'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        acknowledgedByUserId: j['acknowledgedByUserId']?.toString(),
        acknowledgedAt: j['acknowledgedAt'] != null
            ? DateTime.tryParse(j['acknowledgedAt'] as String)
            : null,
        isResolved: j['isResolved'] as bool? ?? false,
      );
}

class LocationPing {
  final String rideId;
  final String userId;
  final double lat;
  final double lng;
  final double? speedMps;
  final double? heading;
  final double? accuracyMeters;
  final DateTime timestamp;
  final String source;

  LocationPing({
    required this.rideId,
    required this.userId,
    required this.lat,
    required this.lng,
    this.speedMps,
    this.heading,
    this.accuracyMeters,
    required this.timestamp,
    required this.source,
  });

  factory LocationPing.fromJson(Map<String, dynamic> j) => LocationPing(
        rideId: j['rideId'] as String,
        userId: j['userId'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        speedMps: (j['speedMps'] as num?)?.toDouble(),
        heading: (j['heading'] as num?)?.toDouble(),
        accuracyMeters: (j['accuracyMeters'] as num?)?.toDouble(),
        timestamp: DateTime.parse(j['timestamp'] as String),
        source: j['source'] as String? ?? 'unknown',
      );
}

class RiderLocation {
  final String userId;
  final String displayName;
  final String role;
  final String status;
  final double lat;
  final double lng;
  final double? speedMps;
  final double? heading;

  RiderLocation({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.status,
    required this.lat,
    required this.lng,
    this.speedMps,
    this.heading,
  });

  factory RiderLocation.fromJson(Map<String, dynamic> j) => RiderLocation(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        role: j['role'] as String? ?? 'Rider',
        status: j['status'] as String? ?? 'Riding',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        speedMps: (j['speedMps'] as num?)?.toDouble(),
        heading: (j['heading'] as num?)?.toDouble(),
      );
}

class RejoinTarget {
  final String targetType;
  final String label;
  final double lat;
  final double lng;
  final double distanceMeters;
  final double durationSeconds;
  final String? polyline;

  RejoinTarget({
    required this.targetType,
    required this.label,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    required this.durationSeconds,
    this.polyline,
  });

  factory RejoinTarget.fromJson(Map<String, dynamic> j) => RejoinTarget(
        targetType: j['targetType'] as String,
        label: j['label'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        distanceMeters: (j['distanceMeters'] as num).toDouble(),
        durationSeconds: (j['durationSeconds'] as num).toDouble(),
        polyline: j['polyline'] as String?,
      );
}
