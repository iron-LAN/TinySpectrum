using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using System.Text.Json;

namespace TinySpectrum.Windows;

public static class WwbTimelineExporter
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static async Task WriteCsvAsync(IReadOnlyList<ScanPoint> points, Stream output)
    {
        await using var writer = new StreamWriter(output, new UTF8Encoding(false), leaveOpen: true);
        foreach (var point in points)
            await writer.WriteLineAsync(string.Create(CultureInfo.InvariantCulture, $"{point.Frequency / 1e6:F6},{point.Level:F2}"));
        await writer.FlushAsync();
    }

    public static async Task WriteAsync(SpectrumScan scan, Stream output)
    {
        if (scan.Captures is not { Count: > 0 } captures) throw new InvalidOperationException("Only continuous scans have a WWB timeline.");
        var grid = MakeGrid(captures[0].Points);
        var title = $"TinySpectrum {scan.Date:yyyy-MM-dd HH-mm}";
        var curve = new Dictionary<string, object>
        {
            ["Color"] = "#ffff00",
            ["CoordinationSource"] = true,
            ["FreqRanges"] = new[] { new Dictionary<string, object> { ["EndFreq"] = grid.StopKHz, ["StartFreq"] = grid.StartKHz, ["StepFreq"] = grid.StepKHz } },
            ["Name"] = "Antenna A",
            ["ResolutionBandWidth"] = ParseRbwKHz(scan.Rbw)
        };
        var header = new Dictionary<string, object>
        {
            ["AmplUnits"] = "dBm",
            ["BinarySchema"] = new object[]
            {
                new Dictionary<string, object> { ["Bytes"] = 4, ["DataValue"] = "start-of-sweep" },
                new Dictionary<string, object> { ["Bytes"] = 4, ["DataValue"] = "id" },
                new Dictionary<string, object> { ["Bytes"] = 4, ["DataValue"] = "timestamp" },
                new Dictionary<string, object> { ["Curve"] = curve },
                new Dictionary<string, object> { ["Bytes"] = 2, ["DataValue"] = "crc16" }
            },
            ["BitWidth"] = 16,
            ["FreqUnits"] = "KHz",
            ["NoDataValue"] = -1400,
            ["PeriodicSpecialSweeps"] = new object[]
            {
                new Dictionary<string, object> { ["Interval"] = 40, ["Type"] = "Periodic running peakhold" },
                new Dictionary<string, object> { ["Interval"] = 100, ["Type"] = "Periodic interval peakhold" }
            },
            ["Scale Factor"] = 10,
            ["ScannerModel"] = "",
            ["ScannerName"] = "AD600",
            ["StartDate"] = captures[0].Date.ToString("MM/dd/yyyy", CultureInfo.InvariantCulture),
            ["StartTime"] = captures[0].Date.ToString("HH:mm:ss", CultureInfo.InvariantCulture),
            ["Title"] = title,
            ["Version"] = "1.0.0.0"
        };
        await output.WriteAsync(Encoding.UTF8.GetBytes("//@ShureScan\n"));
        await JsonSerializer.SerializeAsync(output, header, JsonOptions);
        await output.WriteAsync(Encoding.UTF8.GetBytes("\n@Binary:"));

        var runningPeak = Enumerable.Repeat((short)-1400, grid.Count).ToArray();
        var intervalPeak = Enumerable.Repeat((short)-1400, grid.Count).ToArray();
        uint totalRecords = 0;
        for (var captureIndex = 0; captureIndex < captures.Count; captureIndex++)
        {
            var samples = Resample(captures[captureIndex].Points, grid);
            MergePeak(samples, runningPeak); MergePeak(samples, intervalPeak);
            var id = (uint)captureIndex + 1;
            var timestamp = (uint)Math.Max(0, Math.Round((captures[captureIndex].Date - captures[0].Date).TotalSeconds));
            await output.WriteAsync(Record(id, timestamp, samples)); totalRecords++;
            if (id % 40 == 0) { await output.WriteAsync(Record(0, 0, runningPeak)); totalRecords++; }
            if (id % 100 == 0)
            {
                await output.WriteAsync(Record(0, 0, intervalPeak)); totalRecords++;
                Array.Fill(intervalPeak, (short)-1400);
            }
        }

        var extended = new Dictionary<string, object>
        {
            ["Band"] = "Wideband",
            ["Creator"] = "TinySpectrum Windows 0.1.0-beta.1",
            ["ScanName"] = new[] { title },
            ["UserCurveColors"] = new[] { "#ffff00" }
        };
        await output.WriteAsync(Encoding.UTF8.GetBytes("@Extended:\n"));
        await JsonSerializer.SerializeAsync(output, extended, JsonOptions);
        await output.WriteAsync(new byte[] { 0x0A });
        await output.WriteAsync(Enumerable.Repeat((byte)0x20, Math.Max(0, grid.RecordSize - 6)).ToArray());
        await output.WriteAsync(Encoding.UTF8.GetBytes("\n@End"));
        var counters = new byte[8];
        BinaryPrimitives.WriteUInt32BigEndian(counters.AsSpan(0, 4), (uint)captures.Count);
        BinaryPrimitives.WriteUInt32BigEndian(counters.AsSpan(4, 4), totalRecords);
        await output.WriteAsync(counters);
    }

    private static Grid MakeGrid(IReadOnlyList<ScanPoint> points)
    {
        if (points.Count < 2) throw new InvalidOperationException("A WWB timeline needs at least two points.");
        var sorted = points.OrderBy(x => x.Frequency).ToArray();
        var start = (int)Math.Ceiling(sorted[0].Frequency / 1000);
        var availableStop = (int)Math.Floor(sorted[^1].Frequency / 1000);
        if (availableStop - start < 25) throw new InvalidOperationException("Wireless Workbench requires at least a 25 kHz span.");
        var sourceStep = (sorted[^1].Frequency - sorted[0].Frequency) / (sorted.Length - 1) / 1000;
        var step = Math.Max(25, (int)Math.Round(sourceStep));
        var count = Math.Max(2, (availableStop - start) / step + 1);
        return new(start, start + (count - 1) * step, step);
    }

    private static short[] Resample(IReadOnlyList<ScanPoint> source, Grid grid)
    {
        var sorted = source.OrderBy(x => x.Frequency).ToArray();
        var result = new short[grid.Count];
        var sourceIndex = 0;
        for (var i = 0; i < result.Length; i++)
        {
            var frequency = (grid.StartKHz + i * grid.StepKHz) * 1000.0;
            while (sourceIndex + 1 < sorted.Length && sorted[sourceIndex + 1].Frequency < frequency) sourceIndex++;
            double level;
            if (frequency <= sorted[0].Frequency) level = sorted[0].Level;
            else if (frequency >= sorted[^1].Frequency) level = sorted[^1].Level;
            else
            {
                var a = sorted[sourceIndex]; var b = sorted[Math.Min(sourceIndex + 1, sorted.Length - 1)];
                var ratio = (frequency - a.Frequency) / Math.Max(1, b.Frequency - a.Frequency);
                level = a.Level + (b.Level - a.Level) * ratio;
            }
            result[i] = (short)Math.Clamp((int)Math.Round(level * 10), short.MinValue, short.MaxValue);
        }
        return result;
    }

    private static byte[] Record(uint id, uint timestamp, IReadOnlyList<short> samples)
    {
        var data = new byte[12 + samples.Count * 2 + 2];
        BinaryPrimitives.WriteUInt32BigEndian(data.AsSpan(0, 4), 0xFFFFFFFF);
        BinaryPrimitives.WriteUInt32BigEndian(data.AsSpan(4, 4), id);
        BinaryPrimitives.WriteUInt32BigEndian(data.AsSpan(8, 4), timestamp);
        for (var i = 0; i < samples.Count; i++) BinaryPrimitives.WriteInt16BigEndian(data.AsSpan(12 + i * 2, 2), samples[i]);
        BinaryPrimitives.WriteUInt16BigEndian(data.AsSpan(data.Length - 2), Crc16(data.AsSpan(0, data.Length - 2)));
        return data;
    }

    public static ushort Crc16(ReadOnlySpan<byte> data)
    {
        ushort crc = 0;
        foreach (var value in data)
        {
            crc ^= value;
            for (var bit = 0; bit < 8; bit++) crc = (ushort)((crc & 1) == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1);
        }
        return crc;
    }

    private static void MergePeak(IReadOnlyList<short> samples, short[] peak)
    {
        for (var i = 0; i < Math.Min(samples.Count, peak.Length); i++) if (samples[i] > peak[i]) peak[i] = samples[i];
    }

    private static double ParseRbwKHz(string label)
    {
        var token = label.Split(' ', StringSplitOptions.RemoveEmptyEntries)[0];
        var value = double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) ? parsed : 30;
        return label.Contains("kHz", StringComparison.OrdinalIgnoreCase) ? value : value / 1000;
    }

    private sealed record Grid(int StartKHz, int StopKHz, int StepKHz)
    {
        public int Count => (StopKHz - StartKHz) / StepKHz + 1;
        public int RecordSize => 12 + Count * 2 + 2;
    }
}
