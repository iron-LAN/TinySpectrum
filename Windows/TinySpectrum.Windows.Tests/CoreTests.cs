using System.Buffers.Binary;
using System.Text;

namespace TinySpectrum.Windows.Tests;

public sealed class CoreTests
{
    [Fact]
    public void ScanColorNotifiesWhenPalettePositionChanges()
    {
        var scan = new SpectrumScan();
        var changed = new List<string?>();
        scan.PropertyChanged += (_, eventArgs) => changed.Add(eventArgs.PropertyName);

        scan.DisplayColor = ScanPalette.At(2);

        Assert.Equal(ScanPalette.At(2), scan.DisplayColor);
        Assert.Contains(nameof(SpectrumScan.DisplayColor), changed);
    }

    [Fact]
    public void SweepEstimatorCouplesSpanResolutionAndInterval()
    {
        const double span = 700_000_000;
        Assert.Equal("100 kHz", SweepEstimator.Finest(span, IntervalOption.All[0]).Label);
        Assert.Equal("30 kHz (AD600 scan)", SweepEstimator.Finest(span, IntervalOption.All[2]).Label);
        Assert.Equal("5m", SweepEstimator.Shortest(span, RbwOption.All[3]).Label);
        Assert.True(SweepEstimator.Duration(span, RbwOption.All[5]) < SweepEstimator.Duration(span, RbwOption.All[4]));
    }

    [Fact]
    public void PeakHoldIsCumulativeAtTimelinePosition()
    {
        var start = DateTimeOffset.Parse("2026-07-24T10:00:00Z");
        var scan = new SpectrumScan
        {
            StartHz = 100_000,
            StopHz = 150_000,
            Captures =
            [
                Capture(start, -80, -70, -60),
                Capture(start.AddSeconds(1), -90, -80, -70),
                Capture(start.AddSeconds(2), -75, -85, -55)
            ]
        };
        Assert.Equal([-80, -70, -60], scan.PeakHoldAt(0).Select(x => x.Level));
        Assert.Equal([-80, -70, -60], scan.PeakHoldAt(1).Select(x => x.Level));
        Assert.Equal([-75, -70, -55], scan.PeakHoldAt(2).Select(x => x.Level));
    }

    [Fact]
    public async Task WwbTimelineHasOneCurveValidRecordsAndCounters()
    {
        var start = DateTimeOffset.Parse("2026-07-24T10:00:00Z");
        var captures = Enumerable.Range(0, 100).Select(i => Capture(start.AddSeconds(i), -80 + i % 3, -70, -60)).ToList();
        var scan = new SpectrumScan { StartHz = 100_000, StopHz = 150_000, Rbw = "30 kHz", Captures = captures, Points = captures[^1].Points };
        await using var output = new MemoryStream();
        await WwbTimelineExporter.WriteAsync(scan, output);
        var data = output.ToArray();
        var text = Encoding.UTF8.GetString(data);
        Assert.Contains("\"Name\": \"Antenna A\"", text);
        Assert.DoesNotContain("Antenna B", text);
        var binaryStart = Find(data, Encoding.UTF8.GetBytes("@Binary:")) + 8;
        const int recordSize = 20;
        const int records = 103;
        Assert.Equal("@Extended:", Encoding.UTF8.GetString(data, binaryStart + records * recordSize, 10));
        for (var i = 0; i < records; i++)
        {
            var record = data.AsSpan(binaryStart + i * recordSize, recordSize);
            Assert.True(record[..4].SequenceEqual("@Swp"u8));
            Assert.Equal(WwbTimelineExporter.Crc16(record[..^2]), BinaryPrimitives.ReadUInt16BigEndian(record[^2..]));
        }
        Assert.Equal(1u, BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(binaryStart + 4, 4)));
        Assert.Equal(0u, BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(binaryStart + 8, 4)));
        Assert.Equal(-800, BinaryPrimitives.ReadInt16BigEndian(data.AsSpan(binaryStart + 12, 2)));
        var end = LastFind(data, Encoding.UTF8.GetBytes("@End"));
        Assert.Equal(100u, BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(end + 4, 4)));
        Assert.Equal(103u, BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(end + 8, 4)));
    }

    [Fact]
    public void FrequencyViewportZoomsAroundPointerAndClampsPanning()
    {
        var zoomed = FrequencyViewport.Zoom((100, 200), (100, 200), .25, .5);
        Assert.Equal((112.5, 162.5), zoomed);
        Assert.Equal((150d, 200d), FrequencyViewport.Pan(zoomed, (100, 200), -10));
        Assert.Equal((100d, 200d), FrequencyViewport.Zoom(zoomed, (100, 200), .5, 10));
    }

    [Fact]
    public void FrequencyAxisIncludesEdgesWithoutOverlappingAndStopsAt25KHz()
    {
        var step = FrequencyAxis.TickStep(470_000_000, 470_040_000, 600);
        Assert.Equal(25_000, step);
        var values = FrequencyAxis.LabelValues(100_000_000, 800_000_000, 520, FrequencyAxis.TickStep(100_000_000, 800_000_000, 520));
        Assert.Equal(100_000_000, values[0]);
        Assert.Equal(800_000_000, values[^1]);
        var positions = values.Select(value => (value - values[0]) / (values[^1] - values[0]) * 520).ToArray();
        Assert.All(positions.Zip(positions.Skip(1)), pair => Assert.True(pair.Second - pair.First >= 100));
    }

    [Fact]
    public void ExportNameUsesShortDateLocationAndTrailingUnderscore()
    {
        var date = new DateTimeOffset(2026, 7, 26, 18, 30, 0, TimeSpan.FromHours(2));
        Assert.Equal("26-07-26_Ziggo-Dome-Amsterdam_", ExportFileName.BaseName(date, "Ziggo Dome, Amsterdam"));
        Assert.Equal("26-07-26_UnknownLocation_", ExportFileName.BaseName(date, null));
    }

    private static ScanCapture Capture(DateTimeOffset date, params double[] levels) => new(date,
        levels.Select((level, i) => new ScanPoint(100_000 + i * 25_000, level)).ToList());
    private static int Find(byte[] data, byte[] pattern) => data.AsSpan().IndexOf(pattern);
    private static int LastFind(byte[] data, byte[] pattern) => data.AsSpan().LastIndexOf(pattern);
}
