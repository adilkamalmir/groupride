namespace GroupRide.Cohesion;

/// <summary>
/// Tracks split state per ride to emit alerts only on edge transitions.
/// </summary>
public class CohesionStateTracker
{
    private readonly Dictionary<Guid, RideCohesionState> _states = new();
    private readonly object _lock = new();

    public record RideCohesionState(
        bool IsCurrentlySplit,
        DateTime? SplitSince,
        HashSet<Guid> SplitUserIds,
        bool RegroupSuggested);

    public (bool BecameSplit, bool BecameJoined, bool ShouldSuggestRegroup, CohesionResult Result)
        Update(Guid rideId, CohesionResult result, int splitDurationSeconds)
    {
        lock (_lock)
        {
            _states.TryGetValue(rideId, out var prev);
            prev ??= new RideCohesionState(false, null, new HashSet<Guid>(), false);

            var now = DateTime.UtcNow;
            var becameSplit = false;
            var becameJoined = false;
            var shouldSuggestRegroup = false;

            if (result.IsSplit)
            {
                var splitSince = prev.SplitSince ?? now;
                var durationOk = (now - splitSince).TotalSeconds >= splitDurationSeconds;
                var ids = result.SplitRiders.Select(s => s.UserId).ToHashSet();

                if (!prev.IsCurrentlySplit && durationOk)
                {
                    becameSplit = true;
                    _states[rideId] = prev with
                    {
                        IsCurrentlySplit = true,
                        SplitSince = splitSince,
                        SplitUserIds = ids,
                        RegroupSuggested = false
                    };
                    shouldSuggestRegroup = true;
                }
                else if (!prev.IsCurrentlySplit)
                {
                    // Waiting for debounce
                    _states[rideId] = prev with { SplitSince = splitSince, SplitUserIds = ids };
                }
                else
                {
                    shouldSuggestRegroup = !prev.RegroupSuggested;
                    _states[rideId] = prev with
                    {
                        SplitUserIds = ids,
                        RegroupSuggested = prev.RegroupSuggested || shouldSuggestRegroup
                    };
                }
            }
            else
            {
                if (prev.IsCurrentlySplit)
                    becameJoined = true;

                _states[rideId] = new RideCohesionState(false, null, new HashSet<Guid>(), false);
            }

            return (becameSplit, becameJoined, shouldSuggestRegroup, result);
        }
    }

    public void MarkRegroupSuggested(Guid rideId)
    {
        lock (_lock)
        {
            if (_states.TryGetValue(rideId, out var s))
                _states[rideId] = s with { RegroupSuggested = true };
        }
    }

    public void Clear(Guid rideId)
    {
        lock (_lock) { _states.Remove(rideId); }
    }
}
