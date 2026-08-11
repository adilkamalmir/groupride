namespace GroupRide.Api.Dtos;

public record RegisterRequest(string Email, string Password, string DisplayName, string? Phone);
public record LoginRequest(string Email, string Password);
public record AuthResponse(string Token, Guid UserId, string Email, string DisplayName);

public record BikeProfileDto(string Model, double TankSizeLiters, double TypicalRangeKm, double? DistanceSinceFillKm);
public record UpdateBikeRequest(string Model, double TankSizeLiters, double TypicalRangeKm, double? DistanceSinceFillKm);

public record UserProfileDto(Guid Id, string Email, string DisplayName, string? Phone, BikeProfileDto? Bike);

public record RideStopDto(Guid? Id, string Name, string? Kind, double Lat, double Lng, int SortOrder, double? DistanceFromStartKm);

public record CreateRideRequest(
    string Name,
    DateTime StartAt,
    string MeetPointName,
    double MeetLat,
    double MeetLng,
    string DestinationName,
    double DestinationLat,
    double DestinationLng,
    string? RoutePolyline,
    List<RideStopDto>? Stops,
    double? SplitThresholdMeters,
    int? SplitDurationSeconds,
    bool? ResolvePlaces,
    bool? BuildMotorcycleRoute);

public record UpdateRideRequest(
    string? Name,
    DateTime? StartAt,
    string? MeetPointName,
    double? MeetLat,
    double? MeetLng,
    string? DestinationName,
    double? DestinationLat,
    double? DestinationLng,
    string? RoutePolyline,
    List<RideStopDto>? Stops);

public record MemberDto(
    Guid UserId,
    string DisplayName,
    string Role,
    string Status,
    string InviteStatus,
    double? LastLat,
    double? LastLng,
    DateTime? LastLocationAt);

public record RideDto(
    Guid Id,
    string Name,
    DateTime StartAt,
    string Status,
    string MeetPointName,
    double MeetLat,
    double MeetLng,
    string DestinationName,
    double DestinationLat,
    double DestinationLng,
    string? RoutePolyline,
    double SplitThresholdMeters,
    int SplitDurationSeconds,
    int PingIntervalSeconds,
    DateTime? StartedAt,
    DateTime? CompletedAt,
    string InviteToken,
    List<RideStopDto> Stops,
    List<MemberDto> Members);

public record AssignRoleRequest(Guid UserId, string Role);
public record AnnouncementRequest(string Message);

public record LocationUpdateDto(
    double Lat,
    double Lng,
    double? SpeedMps,
    double? Heading,
    double? AccuracyMeters,
    DateTime? Timestamp);

public record SetStatusRequest(string Status);

public record EmergencyRequest(string Type, double Lat, double Lng, string? Notes);
public record RejoinRequest(string Target); // "group" | "next_stop"

public record RejoinTargetDto(
    string TargetType,
    string Label,
    double Lat,
    double Lng,
    double DistanceMeters,
    double DurationSeconds,
    string? Polyline);

public record TimelineDto(
    Guid RideId,
    string RideName,
    double DistanceKm,
    double DurationMinutes,
    string? RoutePolyline,
    string? StopsJson,
    string? AttendanceJson,
    string? PhotoUrlsJson,
    DateTime CreatedAt);

public record AlertDto(
    Guid Id,
    string Type,
    string Message,
    string? PayloadJson,
    Guid? RelatedUserId,
    DateTime CreatedAt,
    string? RecipientsJson = null);

public record LocationPingDto(
    Guid RideId,
    Guid UserId,
    double Lat,
    double Lng,
    double? SpeedMps,
    double? Heading,
    double? AccuracyMeters,
    DateTime Timestamp,
    string Source);

public record EmergencyDto(
    Guid Id,
    Guid UserId,
    string DisplayName,
    string Type,
    double Lat,
    double Lng,
    string? Notes,
    DateTime CreatedAt,
    Guid? AcknowledgedByUserId,
    DateTime? AcknowledgedAt,
    bool IsResolved);

public record AddTimelinePhotosRequest(List<string> PhotoUrls);
