using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;
using System.Globalization;

namespace TinySpectrum.Windows;

public sealed record ScanPoint(double Frequency, double Level);
public sealed record ScanCapture(DateTimeOffset Date, List<ScanPoint> Points);

public static class ScanPalette
{
    public static readonly string[] Colors = ["#19D9FF", "#FF8C24", "#B05CFF", "#32E38A", "#FF4D9D", "#F5D62E"];
    public static string At(int index) => Colors[Math.Max(0, index) % Colors.Length];
}

public sealed class SpectrumScan : INotifyPropertyChanged
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public DateTimeOffset Date { get; init; } = DateTimeOffset.Now;
    public double StartHz { get; init; }
    public double StopHz { get; init; }
    public string Rbw { get; init; } = "30 kHz";
    public List<ScanPoint> Points { get; set; } = [];
    public List<ScanCapture>? Captures { get; set; }
    [JsonIgnore] public bool IsContinuous => Captures is not null;
    [JsonIgnore] public int CaptureCount => Captures?.Count ?? 1;
    [JsonIgnore] public string CaptureLabel => IsContinuous ? $"⌚ {CaptureCount} scans" : "";
    [JsonIgnore] public string Title => $"{FrequencyText.Short(StartHz)} – {FrequencyText.Short(StopHz)}";
    [JsonIgnore] public string DetailsLabel => $"{Date.LocalDateTime:dd MMM yyyy, HH:mm}  •  {Rbw}";
    private string _displayColor = ScanPalette.Colors[0];
    [JsonIgnore]
    public string DisplayColor
    {
        get => _displayColor;
        set
        {
            if (_displayColor == value) return;
            _displayColor = value;
            OnPropertyChanged();
        }
    }

    private bool _isVisible = true;
    [JsonIgnore]
    public bool IsVisible
    {
        get => _isVisible;
        set { if (_isVisible == value) return; _isVisible = value; OnPropertyChanged(); }
    }

    public IReadOnlyList<ScanPoint> PointsAt(int? captureIndex)
    {
        if (Captures is not { Count: > 0 }) return Points;
        var index = captureIndex is null ? Captures.Count - 1 : Math.Clamp(captureIndex.Value, 0, Captures.Count - 1);
        return Captures[index].Points;
    }

    public IReadOnlyList<ScanPoint> PeakHoldAt(int? captureIndex)
    {
        if (Captures is not { Count: > 0 }) return Points;
        var last = captureIndex is null ? Captures.Count - 1 : Math.Clamp(captureIndex.Value, 0, Captures.Count - 1);
        var peak = Captures[0].Points.ToArray();
        for (var captureIndexValue = 1; captureIndexValue <= last; captureIndexValue++)
        {
            var capture = Captures[captureIndexValue];
            for (var i = 0; i < Math.Min(peak.Length, capture.Points.Count); i++)
            {
                if (Math.Abs(peak[i].Frequency - capture.Points[i].Frequency) < 1 && capture.Points[i].Level > peak[i].Level)
                    peak[i] = capture.Points[i];
            }
        }
        return peak;
    }

    public void NotifyUpdated()
    {
        OnPropertyChanged(nameof(Points));
        OnPropertyChanged(nameof(CaptureCount));
        OnPropertyChanged(nameof(CaptureLabel));
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}

public sealed record ScanPreset(string Name, double StartHz, double StopHz);

public sealed record RbwOption(string Label, double BandwidthHz, string Command, double SettleSeconds)
{
    public override string ToString() => Label;
    public static readonly IReadOnlyList<RbwOption> All =
    [
        new("200 Hz", 200, "0.2", .040), new("1 kHz", 1_000, "1", .015),
        new("3 kHz", 3_000, "3", .006), new("10 kHz", 10_000, "10", .0034),
        new("30 kHz (AD600 scan)", 30_000, "30", .0018), new("100 kHz", 100_000, "100", .001),
        new("300 kHz (AD600 live)", 300_000, "300", .0007), new("600 kHz", 600_000, "600", .0006),
        new("850 kHz", 850_000, "850", .00055)
    ];
}

public sealed record IntervalOption(string Label, int Seconds)
{
    public override string ToString() => Label;
    public static readonly IReadOnlyList<IntervalOption> All =
    [new("10s", 10), new("30s", 30), new("1m", 60), new("5m", 300), new("10m", 600), new("30m", 1800)];
}

public static class SweepEstimator
{
    public static int PointCount(double spanHz, RbwOption rbw, bool continuous) =>
        continuous
            ? Math.Clamp((int)Math.Ceiling(Math.Max(1, spanHz) / Math.Max(1, rbw.BandwidthHz * .8)), 145, 450)
            : 450;

    public static double Duration(double spanHz, RbwOption rbw, int outputPoints = 145)
    {
        var measurementSteps = Math.Max(outputPoints, Math.Ceiling(Math.Max(1, spanHz) / (rbw.BandwidthHz * .8)));
        return .35 + measurementSteps * rbw.SettleSeconds;
    }

    public static RbwOption Finest(double spanHz, IntervalOption interval) =>
        RbwOption.All.FirstOrDefault(x => Duration(spanHz, x) <= interval.Seconds) ?? RbwOption.All[^1];

    public static IntervalOption Shortest(double spanHz, RbwOption rbw) =>
        IntervalOption.All.FirstOrDefault(x => Duration(spanHz, rbw) <= x.Seconds) ?? IntervalOption.All[^1];
}

public static class FrequencyText
{
    public static string Short(double hz) => hz switch
    {
        >= 1e9 => $"{hz / 1e9:0.###} GHz",
        >= 1e6 => $"{hz / 1e6:0.###} MHz",
        >= 1e3 => $"{hz / 1e3:0.###} kHz",
        _ => $"{hz:0} Hz"
    };
}

public static class FrequencyViewport
{
    public static (double Start, double Stop) Zoom(
        (double Start, double Stop) current,
        (double Start, double Stop) full,
        double anchor,
        double scale)
    {
        var fullSpan = full.Stop - full.Start;
        if (fullSpan <= 0) return full;
        current = Clamp(current, full);
        var currentSpan = current.Stop - current.Start;
        var newSpan = Math.Clamp(currentSpan * scale, Math.Max(1, fullSpan / 1000), fullSpan);
        if (newSpan >= fullSpan) return full;
        var position = Math.Clamp(anchor, 0, 1);
        var anchorFrequency = current.Start + currentSpan * position;
        var start = Math.Clamp(anchorFrequency - newSpan * position, full.Start, full.Stop - newSpan);
        return (start, start + newSpan);
    }

    public static (double Start, double Stop) Pan(
        (double Start, double Stop) current,
        (double Start, double Stop) full,
        double translationFraction)
    {
        current = Clamp(current, full);
        var span = current.Stop - current.Start;
        if (span >= full.Stop - full.Start) return full;
        var start = Math.Clamp(current.Start - translationFraction * span, full.Start, full.Stop - span);
        return (start, start + span);
    }

    public static (double Start, double Stop) Clamp(
        (double Start, double Stop) range,
        (double Start, double Stop) full)
    {
        var fullSpan = full.Stop - full.Start;
        var span = Math.Clamp(range.Stop - range.Start, 0, fullSpan);
        if (span >= fullSpan) return full;
        var start = Math.Clamp(range.Start, full.Start, full.Stop - span);
        return (start, start + span);
    }
}

public static class FrequencyAxis
{
    public const double MinimumTickStep = 25_000;
    public const double MinimumLabelSpacing = 100;

    public static double TickStep(double start, double stop, double plotWidth)
    {
        var span = Math.Max(1, stop - start);
        var intervals = Math.Max(1, Math.Floor(plotWidth / MinimumLabelSpacing));
        var rawStep = span / intervals;
        var magnitude = Math.Pow(10, Math.Floor(Math.Log10(rawStep)));
        var normalized = rawStep / magnitude;
        var multiplier = new[] { 1d, 2d, 2.5, 5d, 10d }.First(value => value >= normalized);
        return Math.Max(MinimumTickStep, multiplier * magnitude);
    }

    public static IReadOnlyList<double> LabelValues(double start, double stop, double plotWidth, double step)
    {
        var span = stop - start;
        if (span <= 0) return [];
        var result = new List<double> { start };
        var epsilon = step * 1e-9;
        for (var value = Math.Ceiling((start - epsilon) / step) * step; value <= stop + epsilon; value += step)
        {
            if (value <= start || value >= stop) continue;
            var fromPrevious = (value - result[^1]) / span * plotWidth;
            var fromEnd = (stop - value) / span * plotWidth;
            if (fromPrevious >= MinimumLabelSpacing && fromEnd >= MinimumLabelSpacing) result.Add(value);
        }
        result.Add(stop);
        return result;
    }

    public static string Label(double frequency) =>
        frequency >= 1e6
            ? string.Create(CultureInfo.InvariantCulture, $"{frequency / 1e6:F3} MHz")
            : string.Create(CultureInfo.InvariantCulture, $"{frequency / 1e3:F3} kHz");
}

public static class ExportFileName
{
    public static string BaseName(DateTimeOffset date, string? location)
    {
        var safeLocation = SafePart(string.IsNullOrWhiteSpace(location) ? "UnknownLocation" : location);
        return $"{date.LocalDateTime:dd-MM-yy}_{safeLocation}_";
    }

    private static string SafePart(string value)
    {
        var words = value.Split(value.Where(character => !char.IsLetterOrDigit(character) && character != '-').Distinct().ToArray(),
            StringSplitOptions.RemoveEmptyEntries);
        return words.Length == 0 ? "Unknown" : string.Join("-", words);
    }
}
