namespace GroupRide.Cohesion;

public class FuelAnalyzer
{
    /// <summary>
    /// Riders whose remaining range is less than horizonKm need fuel soon.
    /// </summary>
    public IReadOnlyList<FuelEstimate> Analyze(
        IEnumerable<(Guid UserId, string DisplayName, double TypicalRangeKm, double DistanceSinceFillKm)> bikes,
        double horizonKm = 40)
    {
        return bikes
            .Select(b =>
            {
                var remaining = Math.Max(0, b.TypicalRangeKm - b.DistanceSinceFillKm);
                return new FuelEstimate(b.UserId, b.DisplayName, remaining, remaining <= horizonKm);
            })
            .OrderBy(f => f.RemainingRangeKm)
            .ToList();
    }

    public string? BuildAggregateMessage(IReadOnlyList<FuelEstimate> estimates, double horizonKm = 40)
    {
        var needy = estimates.Where(e => e.NeedsFuelSoon).ToList();
        if (needy.Count == 0) return null;
        return $"{needy.Count} rider{(needy.Count == 1 ? "" : "s")} need fuel within {horizonKm:0} km";
    }
}
