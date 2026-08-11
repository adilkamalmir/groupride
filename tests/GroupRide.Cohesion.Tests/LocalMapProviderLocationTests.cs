using GroupRide.Infrastructure.Services;

namespace GroupRide.Cohesion.Tests;

public class LocalMapProviderLocationTests
{
    [Fact]
    public async Task Nearby_OttawaSimulatorCoords_ReturnsKanataAreaPlaces()
    {
        var maps = new LocalMapProvider();
        // iOS Simulator custom location used in demos
        var results = await maps.NearbySuggestionsAsync(45.31, -75.91);

        Assert.NotEmpty(results);
        Assert.Contains(results, r =>
            r.Description.Contains("Kanata", StringComparison.OrdinalIgnoreCase) ||
            r.MainText!.Contains("Kanata", StringComparison.OrdinalIgnoreCase) ||
            r.Description.Contains("Tim Hortons", StringComparison.OrdinalIgnoreCase));

        // Closest hit should be in the Ottawa west / Kanata area, not far afield.
        var first = results[0];
        Assert.DoesNotContain("Toronto", first.Description, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Autocomplete_WithOttawaBias_PrefersLocalTimHortons()
    {
        var maps = new LocalMapProvider();
        var results = await maps.AutocompleteAsync("Tim", 45.31, -75.91);

        Assert.NotEmpty(results);
        Assert.Contains(results, r =>
            r.Description.Contains("Kanata", StringComparison.OrdinalIgnoreCase) ||
            r.MainText!.Contains("Tim Hortons", StringComparison.OrdinalIgnoreCase));
    }
}
